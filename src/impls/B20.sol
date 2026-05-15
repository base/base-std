// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Capabilities} from "../interfaces/Capabilities.sol";
import {IDefaultToken} from "../interfaces/IDefaultToken.sol";
import {IPolicyRegistry} from "../interfaces/IPolicyRegistry.sol";
import {PauseVectors} from "../interfaces/PauseVectors.sol";

/// @title B20
/// @author Coinbase
/// @notice Reference implementation of `IDefaultToken`. Combines ERC-20 with
///         memo'd transfer/mint/burn/redeem variants, OpenZeppelin
///         AccessControl-style role management (hand-ported, no inheritance),
///         granular pause vectors, supply cap, EIP-2612 permit (EOA only),
///         and ERC-7572 contract URI.
///
/// @dev    Policy enforcement strategy:
///         - Built-in policy IDs `0` (always-reject) and `1` (always-allow)
///           are trapped inside this contract, so a token configured with
///           `transferPolicyId == 1` works even before the policy registry
///           precompile is deployed.
///         - For any other policy ID, the contract staticcalls
///           `POLICY_REGISTRY`. A failing call OR a call returning `false`
///           is treated as deny; this is the safe default until the
///           singleton registry is live.
///
///         Constructor signature mirrors `ITokenFactory.CreateDefaultTokenParams`
///         positionally; this is a best-stab until the factory contract is
///         specified. Bootstrap (initial-supply) mint at construction
///         bypasses the transfer-policy check per the NatSpec on
///         `CreateDefaultTokenParams.initialSupply`.
contract B20 is IDefaultToken {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev OZ AccessControl convention: the default admin role is
    ///      `bytes32(0)`, and is its own admin role.
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);

    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant UNPAUSE_ROLE = keccak256("UNPAUSE_ROLE");

    /// @dev TODO: replace with the official Base policy-registry precompile
    ///      address once specified. The implementation is graceful when no
    ///      contract lives here: built-in IDs (0/1) still work, and any
    ///      other ID is treated as deny.
    IPolicyRegistry private constant _POLICY_REGISTRY = IPolicyRegistry(address(0x42));

    /// @dev Built-in always-reject ID per `IPolicyRegistry`.
    uint64 private constant _POLICY_REJECT = 0;

    /// @dev Built-in always-allow ID per `IPolicyRegistry`.
    uint64 private constant _POLICY_ALLOW = 1;

    /// @dev EIP-712 type hash for the EIP-2612 `Permit` struct.
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @dev EIP-712 domain type hash. Per `IDefaultToken` NatSpec, the
    ///      domain carries `chainId` and `verifyingContract` ONLY (no
    ///      name, no version); the type hash drops those fields to stay
    ///      consistent with `eip712Domain().fields == 0x0c`.
    ///
    ///      TODO: confirm with interface author whether the empty-name /
    ///      empty-version intent was "still use the 5-field type hash with
    ///      empty strings" (OZ-compatible, wallets verify) or "really drop
    ///      them" (ERC-5267 pedantic, wallets that hard-code the canonical
    ///      domain fail to verify). This implementation follows the latter.
    bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");

    /// @dev ERC-5267 `fields` value: bits 2 and 3 set, i.e. only `chainId`
    ///      and `verifyingContract` are populated.
    bytes1 private constant _EIP712_FIELDS = 0x0c;

    /// @dev `secp256k1n / 2` upper bound for canonical signatures (low-`s`).
    uint256 private constant _MAX_S = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Mirrors OZ AccessControl's `RoleData`.
    struct RoleData {
        mapping(address account => bool hasRole) members;
        bytes32 adminRole;
    }

    string private _name;
    string private _symbol;
    string private _contractURI;

    uint8 private immutable _DECIMALS;
    uint256 private immutable _CAPABILITIES;
    uint256 private immutable _CACHED_CHAIN_ID;
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;

    uint256 private _totalSupply;
    uint256 private _supplyCap;
    uint256 private _minimumRedeemable;
    uint256 private _pausedVectors;
    uint256 private _defaultAdminCount;

    uint64 private _transferPolicyId;

    mapping(address account => uint256 balance) private _balances;
    mapping(address owner => mapping(address spender => uint256 amount)) private _allowances;
    mapping(address owner => uint256 nonce) private _nonces;
    mapping(bytes32 role => RoleData data) private _roles;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Construct a Default-variant B-20 token.
    /// @dev    Argument order mirrors `ITokenFactory.CreateDefaultTokenParams`
    ///         (less `salt`, which the factory consumes). When the factory is
    ///         specified this should be revisited; either the factory passes
    ///         the struct directly or the order here gets re-pinned.
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address admin,
        uint256 capabilities_,
        uint256 initialSupply,
        address initialSupplyRecipient,
        uint64 transferPolicyId_,
        uint256 supplyCap_,
        uint256 minimumRedeemable_,
        string memory contractURI_
    ) {
        if (admin == address(0)) revert InvalidReceiver(admin);
        if (initialSupply > supplyCap_) revert SupplyCapExceeded({cap: supplyCap_, attempted: initialSupply});

        _name = name_;
        _symbol = symbol_;
        _contractURI = contractURI_;
        _DECIMALS = decimals_;
        _CAPABILITIES = capabilities_;
        _supplyCap = supplyCap_;
        _minimumRedeemable = minimumRedeemable_;
        _transferPolicyId = transferPolicyId_;

        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator();

        _grantRoleInternal({role: DEFAULT_ADMIN_ROLE, account: admin});

        if (initialSupply > 0) {
            if (initialSupplyRecipient == address(0)) revert InvalidReceiver(initialSupplyRecipient);
            _totalSupply = initialSupply;
            unchecked {
                _balances[initialSupplyRecipient] = initialSupply;
            }
            emit Transfer({from: address(0), to: initialSupplyRecipient, amount: initialSupply});
        }
    }

    /*//////////////////////////////////////////////////////////////
                              CAPABILITIES
    //////////////////////////////////////////////////////////////*/

    function capabilities() external view returns (uint256) {
        return _CAPABILITIES;
    }

    function isPausable() external view returns (bool) {
        return _hasCapability(Capabilities.PAUSABLE);
    }

    function isCapMutable() external view returns (bool) {
        return _hasCapability(Capabilities.CAP_MUTABLE);
    }

    /*//////////////////////////////////////////////////////////////
                                  ERC-20
    //////////////////////////////////////////////////////////////*/

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _DECIMALS;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer({from: msg.sender, to: to, spender: msg.sender, amount: amount});
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (from == address(0)) revert InvalidSender(from);
        _spendAllowance({owner: from, spender: msg.sender, amount: amount});
        _transfer({from: from, to: to, spender: msg.sender, amount: amount});
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve({owner: msg.sender, spender: spender, amount: amount});
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            METADATA UPDATES
    //////////////////////////////////////////////////////////////*/

    function setName(string calldata newName) external {
        _requireRole(DEFAULT_ADMIN_ROLE);
        _name = newName;
        emit NameUpdated({updater: msg.sender, newName: newName});
    }

    function setSymbol(string calldata newSymbol) external {
        _requireRole(DEFAULT_ADMIN_ROLE);
        _symbol = newSymbol;
        emit SymbolUpdated({updater: msg.sender, newSymbol: newSymbol});
    }

    /*//////////////////////////////////////////////////////////////
                          MEMO TRANSFER VARIANTS
    //////////////////////////////////////////////////////////////*/

    function transferWithMemo(address to, uint256 amount, bytes32 memo) external returns (bool) {
        _transfer({from: msg.sender, to: to, spender: msg.sender, amount: amount});
        emit Memo(memo);
        return true;
    }

    function transferFromWithMemo(address from, address to, uint256 amount, bytes32 memo) external returns (bool) {
        if (from == address(0)) revert InvalidSender(from);
        _spendAllowance({owner: from, spender: msg.sender, amount: amount});
        _transfer({from: from, to: to, spender: msg.sender, amount: amount});
        emit Memo(memo);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                              MINT / BURN
    //////////////////////////////////////////////////////////////*/

    function mint(address to, uint256 amount) external {
        _mint({to: to, amount: amount});
    }

    function mintWithMemo(address to, uint256 amount, bytes32 memo) external {
        _mint({to: to, amount: amount});
        emit Memo(memo);
    }

    function burn(uint256 amount) external {
        _burn({from: msg.sender, amount: amount});
    }

    function burnWithMemo(uint256 amount, bytes32 memo) external {
        _burn({from: msg.sender, amount: amount});
        emit Memo(memo);
    }

    /*//////////////////////////////////////////////////////////////
                                 REDEEM
    //////////////////////////////////////////////////////////////*/

    function redeem(uint256 amount) external {
        _redeem(amount);
    }

    function redeemWithMemo(uint256 amount, bytes32 memo) external {
        _redeem(amount);
        emit Memo(memo);
    }

    function minimumRedeemable() external view returns (uint256) {
        return _minimumRedeemable;
    }

    function setMinimumRedeemable(uint256 newMinimum) external {
        _requireRole(DEFAULT_ADMIN_ROLE);
        uint256 old = _minimumRedeemable;
        _minimumRedeemable = newMinimum;
        emit MinimumRedeemableUpdated({updater: msg.sender, oldMinimum: old, newMinimum: newMinimum});
    }

    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role].members[account];
    }

    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
        return _roles[role].adminRole;
    }

    function grantRole(bytes32 role, address account) external {
        _requireRole(getRoleAdmin(role));
        _grantRoleInternal({role: role, account: account});
    }

    function revokeRole(bytes32 role, address account) external {
        _requireRole(getRoleAdmin(role));
        _revokeRoleInternal({role: role, account: account});
    }

    function renounceRole(bytes32 role, address callerConfirmation) external {
        if (callerConfirmation != msg.sender) revert AccessControlBadConfirmation();
        if (!_roles[role].members[msg.sender]) return;
        if (role == DEFAULT_ADMIN_ROLE && _defaultAdminCount == 1) revert LastAdminCannotRenounce();
        _revokeRoleInternal({role: role, account: msg.sender});
    }

    function setRoleAdmin(bytes32 role, bytes32 newAdminRole) external {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _requireRole(previousAdminRole);
        _roles[role].adminRole = newAdminRole;
        emit RoleAdminChanged({role: role, previousAdminRole: previousAdminRole, newAdminRole: newAdminRole});
    }

    /*//////////////////////////////////////////////////////////////
                                  PAUSE
    //////////////////////////////////////////////////////////////*/

    function paused() public view returns (uint256) {
        if (!_hasCapability(Capabilities.PAUSABLE)) return 0;
        return _pausedVectors;
    }

    function isPaused(uint256 vector) external view returns (bool) {
        return (paused() & vector) != 0;
    }

    function pause(uint256 vectors) external {
        _requireCapability(Capabilities.PAUSABLE);
        _requireRole(PAUSE_ROLE);
        if (vectors == 0) revert InvalidAmount();
        _pausedVectors |= vectors;
        emit Paused({updater: msg.sender, vectors: vectors});
    }

    function unpause() external {
        _requireCapability(Capabilities.PAUSABLE);
        _requireRole(UNPAUSE_ROLE);
        _pausedVectors = 0;
        emit Unpaused(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                                 POLICY
    //////////////////////////////////////////////////////////////*/

    function transferPolicyId() external view returns (uint64) {
        return _transferPolicyId;
    }

    function changeTransferPolicyId(uint64 newPolicyId) external {
        _requireRole(DEFAULT_ADMIN_ROLE);
        if (newPolicyId != _POLICY_REJECT && newPolicyId != _POLICY_ALLOW) {
            if (!_policyExists(newPolicyId)) revert PolicyNotFound(newPolicyId);
        }
        uint64 old = _transferPolicyId;
        _transferPolicyId = newPolicyId;
        emit TransferPolicyUpdated({updater: msg.sender, oldPolicyId: old, newPolicyId: newPolicyId});
    }

    /*//////////////////////////////////////////////////////////////
                              SUPPLY CAP
    //////////////////////////////////////////////////////////////*/

    function supplyCap() external view returns (uint256) {
        return _supplyCap;
    }

    function setSupplyCap(uint256 newSupplyCap) external {
        _requireCapability(Capabilities.CAP_MUTABLE);
        _requireRole(DEFAULT_ADMIN_ROLE);
        if (newSupplyCap < _totalSupply) {
            revert InvalidSupplyCap({currentSupply: _totalSupply, proposedCap: newSupplyCap});
        }
        uint256 old = _supplyCap;
        _supplyCap = newSupplyCap;
        emit SupplyCapUpdated({updater: msg.sender, oldSupplyCap: old, newSupplyCap: newSupplyCap});
    }

    /*//////////////////////////////////////////////////////////////
                       PERMIT (EIP-2612 + ERC-5267)
    //////////////////////////////////////////////////////////////*/

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        if (block.chainid == _CACHED_CHAIN_ID) return _CACHED_DOMAIN_SEPARATOR;
        return _buildDomainSeparator();
    }

    function nonces(address owner) external view returns (uint256) {
        return _nonces[owner];
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        if (block.timestamp > deadline) revert ExpiredSignature(deadline);

        uint256 nonce = _nonces[owner];
        unchecked {
            _nonces[owner] = nonce + 1;
        }
        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));

        address recovered = _recover({digest: digest, v: v, r: r, s: s});
        if (recovered != owner) revert InvalidSigner({signer: recovered, owner: owner});

        _approve({owner: owner, spender: spender, amount: value});
    }

    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name_,
            string memory version_,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        return (_EIP712_FIELDS, "", "", block.chainid, address(this), bytes32(0), new uint256[](0));
    }

    /*//////////////////////////////////////////////////////////////
                          CONTRACT URI (ERC-7572)
    //////////////////////////////////////////////////////////////*/

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    function setContractURI(string calldata newURI) external {
        _requireRole(DEFAULT_ADMIN_ROLE);
        _contractURI = newURI;
        emit ContractURIUpdated();
    }

    /*//////////////////////////////////////////////////////////////
                       INTERNAL: ERC-20 PRIMITIVES
    //////////////////////////////////////////////////////////////*/

    function _transfer(address from, address to, address spender, uint256 amount) private {
        if (to == address(0)) revert InvalidReceiver(to);
        if (_pausedVectors & PauseVectors.TRANSFER != 0) revert ContractPaused(PauseVectors.TRANSFER);

        _checkTransferPolicy({from: from, to: to, spender: spender});

        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) {
            revert InsufficientBalance({sender: from, balance: fromBalance, needed: amount});
        }
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }
        emit Transfer({from: from, to: to, amount: amount});
    }

    function _mint(address to, uint256 amount) private {
        _requireRole(MINT_ROLE);
        if (to == address(0)) revert InvalidReceiver(to);
        if (_pausedVectors & PauseVectors.MINT != 0) revert ContractPaused(PauseVectors.MINT);

        uint256 newSupply = _totalSupply + amount;
        if (newSupply > _supplyCap) revert SupplyCapExceeded({cap: _supplyCap, attempted: newSupply});

        if (!_isAuthorizedMintRecipient(to)) revert PolicyForbids(_transferPolicyId);

        _totalSupply = newSupply;
        unchecked {
            _balances[to] += amount;
        }
        emit Transfer({from: address(0), to: to, amount: amount});
    }

    function _burn(address from, uint256 amount) private {
        _requireRole(BURN_ROLE);
        if (_pausedVectors & PauseVectors.BURN != 0) revert ContractPaused(PauseVectors.BURN);

        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) {
            revert InsufficientBalance({sender: from, balance: fromBalance, needed: amount});
        }
        unchecked {
            _balances[from] = fromBalance - amount;
            _totalSupply -= amount;
        }
        emit Transfer({from: from, to: address(0), amount: amount});
    }

    function _redeem(uint256 amount) private {
        uint256 minimum = _minimumRedeemable;
        if (amount == 0 || amount < minimum) revert MinimumRedeemableNotMet({amount: amount, minimum: minimum});
        if (_pausedVectors & PauseVectors.REDEEM != 0) revert ContractPaused(PauseVectors.REDEEM);

        // TODO: IPolicyRegistry.CompoundPolicyData has no redeemer slot yet
        // (sender / recipient / mintRecipient only). The IDefaultToken NatSpec
        // says redeem consults the "redeemer slot of a compound policy";
        // until the registry interface grows that slot we temporarily map
        // the redeemer check onto isAuthorizedSender, which yields the
        // closest behavior (a sanctioned holder cannot destroy supply to
        // claim off-chain).
        if (!_isAuthorizedSender(msg.sender)) revert PolicyForbids(_transferPolicyId);

        uint256 fromBalance = _balances[msg.sender];
        if (fromBalance < amount) {
            revert InsufficientBalance({sender: msg.sender, balance: fromBalance, needed: amount});
        }
        unchecked {
            _balances[msg.sender] = fromBalance - amount;
            _totalSupply -= amount;
        }
        emit Transfer({from: msg.sender, to: address(0), amount: amount});
        emit Redeemed({holder: msg.sender, amount: amount});
    }

    function _approve(address owner, address spender, uint256 amount) private {
        if (owner == address(0)) revert InvalidApprover(owner);
        if (spender == address(0)) revert InvalidSpender(spender);
        _allowances[owner][spender] = amount;
        emit Approval({owner: owner, spender: spender, amount: amount});
    }

    function _spendAllowance(address owner, address spender, uint256 amount) private {
        uint256 current = _allowances[owner][spender];
        if (current == type(uint256).max) return;
        if (current < amount) revert InsufficientAllowance({spender: spender, allowance: current, needed: amount});
        unchecked {
            _allowances[owner][spender] = current - amount;
        }
        emit Approval({owner: owner, spender: spender, amount: current - amount});
    }

    /*//////////////////////////////////////////////////////////////
                       INTERNAL: ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function _grantRoleInternal(bytes32 role, address account) private {
        if (_roles[role].members[account]) return;
        _roles[role].members[account] = true;
        if (role == DEFAULT_ADMIN_ROLE) {
            unchecked {
                _defaultAdminCount += 1;
            }
        }
        emit RoleGranted({role: role, account: account, sender: msg.sender});
    }

    function _revokeRoleInternal(bytes32 role, address account) private {
        if (!_roles[role].members[account]) return;
        _roles[role].members[account] = false;
        if (role == DEFAULT_ADMIN_ROLE) {
            unchecked {
                _defaultAdminCount -= 1;
            }
        }
        emit RoleRevoked({role: role, account: account, sender: msg.sender});
    }

    function _requireRole(bytes32 role) private view {
        if (!_roles[role].members[msg.sender]) {
            revert AccessControlUnauthorizedAccount({account: msg.sender, neededRole: role});
        }
    }

    function _requireCapability(uint256 capability) private view {
        if ((_CAPABILITIES & capability) == 0) revert FeatureDisabled(capability);
    }

    function _hasCapability(uint256 capability) private view returns (bool) {
        return (_CAPABILITIES & capability) != 0;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL: POLICY
    //////////////////////////////////////////////////////////////*/

    function _checkTransferPolicy(address from, address to, address spender) private view {
        if (!_isAuthorizedSender(from)) revert PolicyForbids(_transferPolicyId);
        if (!_isAuthorizedRecipient(to)) revert PolicyForbids(_transferPolicyId);
        if (spender != from && !_isAuthorizedSender(spender)) revert PolicyForbids(_transferPolicyId);
    }

    function _isAuthorizedSender(address user) private view returns (bool) {
        uint64 policyId = _transferPolicyId;
        if (policyId == _POLICY_ALLOW) return true;
        if (policyId == _POLICY_REJECT) return false;
        return _staticcallPolicyBool(abi.encodeCall(IPolicyRegistry.isAuthorizedSender, (policyId, user)));
    }

    function _isAuthorizedRecipient(address user) private view returns (bool) {
        uint64 policyId = _transferPolicyId;
        if (policyId == _POLICY_ALLOW) return true;
        if (policyId == _POLICY_REJECT) return false;
        return _staticcallPolicyBool(abi.encodeCall(IPolicyRegistry.isAuthorizedRecipient, (policyId, user)));
    }

    function _isAuthorizedMintRecipient(address user) private view returns (bool) {
        uint64 policyId = _transferPolicyId;
        if (policyId == _POLICY_ALLOW) return true;
        if (policyId == _POLICY_REJECT) return false;
        return _staticcallPolicyBool(abi.encodeCall(IPolicyRegistry.isAuthorizedMintRecipient, (policyId, user)));
    }

    function _policyExists(uint64 policyId) private view returns (bool) {
        return _staticcallPolicyBool(abi.encodeCall(IPolicyRegistry.policyExists, (policyId)));
    }

    /// @dev Staticcalls the policy registry and decodes a single bool.
    ///      Returns `false` on any failure (revert, no-contract, malformed
    ///      return). Safe-by-default: when the registry is missing or
    ///      misbehaving, all non-built-in policy IDs deny.
    function _staticcallPolicyBool(bytes memory data) private view returns (bool) {
        (bool ok, bytes memory ret) = address(_POLICY_REGISTRY).staticcall(data);
        if (!ok || ret.length < 32) return false;
        return abi.decode(ret, (bool));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL: EIP-712
    //////////////////////////////////////////////////////////////*/

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(_EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function _recover(bytes32 digest, uint8 v, bytes32 r, bytes32 s) private pure returns (address) {
        if (uint256(s) > _MAX_S) return address(0);
        if (v != 27 && v != 28) return address(0);
        return ecrecover(digest, v, r, s);
    }
}
