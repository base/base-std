// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";
import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";

import {MockB20Storage} from "test/lib/mocks/MockB20Storage.sol";

/// @title MockB20
/// @notice Reference implementation of the `IB20` default-token surface.
///         Etched at every default-variant B-20 token's factory-derived
///         address via `vm.etch` from `MockTokenFactory.createToken`.
///
/// @dev    Written as Solidity-as-if-Rust: the goal is unambiguous
///         spec-correspondence with the production Rust precompile, not
///         gas optimization or Solidity idiom adherence. Specifically:
///
///         - All mutable state lives in `MockB20Storage.layout()` at a
///           single ERC-7201 namespaced root. The struct field order IS
///           the slot layout the Rust impl mirrors; slot offsets are
///           named constants on `MockB20Storage`.
///         - `decimals()` is decoded from address byte `[11]` — no
///           storage slot. The Rust impl does the same.
///         - **No factory-only entrypoints exist on this contract.**
///           Initial storage state (name, symbol, supply cap, admin
///           role, `initialized` flag) is written directly by the
///           factory via `vm.store` at the slots declared in
///           `MockB20Storage`. The Rust impl writes the same slots
///           the same way; the public surface this contract exposes
///           is exactly `IB20`.
///         - The factory call-site bypass for the bootstrap window is an
///           explicit gate consulted at every authorization check:
///           `msg.sender == FACTORY && !initialized`. The factory
///           writes `initialized = true` directly (also via `vm.store`)
///           once `initCalls` have run, closing the privileged window.
///           Token invariants (supply-cap math, balance accounting)
///           are NOT bypassed during the window.
///         - Variant tokens (e.g. `MockB20Stablecoin`) extend by adding
///           a disjoint storage namespace; the factory writes the
///           variant-specific slots directly, no virtual hook needed.
///
///         **What this mock is for:** local-tests-with-vm.etch and as a
///         readable spec artifact for auditors and Rust developers. It
///         lives under `test/` and is never deployed as production code.
contract MockB20 is IB20 {
    // ============================================================
    //                          CONSTANTS
    // ============================================================

    /// @notice The factory precompile address. Calls from this address
    ///         during the bootstrap window (before the factory writes
    ///         `initialized = true` via vm.store) bypass all token-side
    ///         authorization gates.
    address internal constant FACTORY = StdPrecompiles.TOKEN_FACTORY_ADDRESS;

    /// @notice The policy registry precompile address. Consulted on
    ///         every transfer, mint, and `burnBlocked` to resolve the
    ///         token's configured policy slots.
    address internal constant POLICY_REGISTRY = StdPrecompiles.POLICY_REGISTRY_ADDRESS;

    /// @notice Default top-level admin role. Equal to `bytes32(0)` per
    ///         the OZ AccessControl convention.
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);

    /// @notice Role identifiers. Computed as `keccak256` of the role
    ///         name per the OZ AccessControl convention, so the
    ///         Rust impl can derive them identically.
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 public constant BURN_BLOCKED_ROLE = keccak256("BURN_BLOCKED_ROLE");
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant UNPAUSE_ROLE = keccak256("UNPAUSE_ROLE");

    /// @notice Policy-type identifiers. Same `keccak256` convention.
    bytes32 public constant TRANSFER_SENDER = keccak256("TRANSFER_SENDER");
    bytes32 public constant TRANSFER_RECEIVER = keccak256("TRANSFER_RECEIVER");
    bytes32 public constant TRANSFER_EXECUTOR = keccak256("TRANSFER_EXECUTOR");
    bytes32 public constant MINT_RECEIVER = keccak256("MINT_RECEIVER");

    // ============================================================
    //                          ERC-20: VIEWS
    // ============================================================

    function name() external view returns (string memory) {
        return MockB20Storage.layout().name;
    }

    function symbol() external view returns (string memory) {
        return MockB20Storage.layout().symbol;
    }

    /// @notice Decimals are encoded in address byte `[11]` by the
    ///         factory. Stateless retrieval; no storage slot.
    function decimals() external view returns (uint8) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint8(uint160(address(this)) >> 64);
    }

    function totalSupply() external view returns (uint256) {
        return MockB20Storage.layout().totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return MockB20Storage.layout().balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return MockB20Storage.layout().allowances[owner][spender];
    }

    // ============================================================
    //                       ERC-20: MUTATIONS
    // ============================================================

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (!_isPrivileged() && msg.sender != from) {
            _consumeAllowance(from, msg.sender, amount);
            _checkPolicy(TRANSFER_EXECUTOR, msg.sender);
        }
        _transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (msg.sender == address(0)) revert InvalidApprover(msg.sender);
        if (spender == address(0)) revert InvalidSpender(spender);
        MockB20Storage.layout().allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // ============================================================
    //                       MEMO TRANSFER VARIANTS
    // ============================================================

    function transferWithMemo(address to, uint256 amount, bytes32 memo) external returns (bool) {
        _transfer(msg.sender, to, amount);
        emit Memo(memo);
        return true;
    }

    function transferFromWithMemo(address from, address to, uint256 amount, bytes32 memo) external returns (bool) {
        if (!_isPrivileged() && msg.sender != from) {
            _consumeAllowance(from, msg.sender, amount);
            _checkPolicy(TRANSFER_EXECUTOR, msg.sender);
        }
        _transfer(from, to, amount);
        emit Memo(memo);
        return true;
    }

    // ============================================================
    //                         METADATA UPDATES
    // ============================================================

    function setName(string calldata newName) external {
        _requireAdmin();
        MockB20Storage.layout().name = newName;
        emit NameUpdated(msg.sender, newName);
    }

    function setSymbol(string calldata newSymbol) external {
        _requireAdmin();
        MockB20Storage.layout().symbol = newSymbol;
        emit SymbolUpdated(msg.sender, newSymbol);
    }

    // ============================================================
    //                          MINT / BURN
    // ============================================================

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function mintWithMemo(address to, uint256 amount, bytes32 memo) external {
        _mint(to, amount);
        emit Memo(memo);
    }

    function burn(uint256 amount) external {
        _burnSelf(msg.sender, amount);
    }

    function burnWithMemo(uint256 amount, bytes32 memo) external {
        _burnSelf(msg.sender, amount);
        emit Memo(memo);
    }

    function burnBlocked(address from, uint256 amount) external {
        if (!_isPrivileged()) {
            if (!hasRole(BURN_BLOCKED_ROLE, msg.sender)) {
                revert AccessControlUnauthorizedAccount(msg.sender, BURN_BLOCKED_ROLE);
            }
            if (_isPaused(PausableFeature.BURN)) revert ContractPaused(PausableFeature.BURN);
            // The point of burnBlocked is to seize from policy-blocked
            // accounts. Calling it on an authorized account is rejected.
            uint64 senderPolicyId = MockB20Storage.layout().policyIds[TRANSFER_SENDER];
            if (_policyAuthorized(senderPolicyId, from)) revert AccountNotBlocked(from);
        }
        _burnRaw(from, amount);
        emit BurnedBlocked(msg.sender, from, amount);
    }

    // ============================================================
    //                            ROLES
    // ============================================================

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return MockB20Storage.layout().roles[role][account];
    }

    function getRoleAdmin(bytes32 role) external view returns (bytes32) {
        bytes32 adminRole = MockB20Storage.layout().roleAdmins[role];
        // Default admin if not explicitly overridden via setRoleAdmin.
        return adminRole == bytes32(0) && role != DEFAULT_ADMIN_ROLE ? DEFAULT_ADMIN_ROLE : adminRole;
    }

    function grantRole(bytes32 role, address account) external {
        if (!_isPrivileged()) _requireRoleAdmin(role);
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external {
        if (!_isPrivileged()) _requireRoleAdmin(role);
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address callerConfirmation) external {
        if (callerConfirmation != msg.sender) revert AccessControlBadConfirmation();
        if (role == DEFAULT_ADMIN_ROLE && MockB20Storage.layout().adminCount == 1) {
            // Sole admin must use the explicit renounceLastAdmin path.
            revert LastAdminCannotRenounce();
        }
        _revokeRole(role, msg.sender);
    }

    function renounceLastAdmin() external {
        MockB20Storage.Layout storage $ = MockB20Storage.layout();
        if (!$.roles[DEFAULT_ADMIN_ROLE][msg.sender]) {
            revert AccessControlUnauthorizedAccount(msg.sender, DEFAULT_ADMIN_ROLE);
        }
        if ($.adminCount != 1) revert NotSoleAdmin();
        $.roles[DEFAULT_ADMIN_ROLE][msg.sender] = false;
        $.adminCount = 0;
        emit RoleRevoked(DEFAULT_ADMIN_ROLE, msg.sender, msg.sender);
        emit LastAdminRenounced(msg.sender);
    }

    function setRoleAdmin(bytes32 role, bytes32 newAdminRole) external {
        if (!_isPrivileged()) _requireRoleAdmin(role);
        bytes32 previousAdminRole = MockB20Storage.layout().roleAdmins[role];
        // Default admin if not explicitly set; expose it in the event.
        if (previousAdminRole == bytes32(0) && role != DEFAULT_ADMIN_ROLE) {
            previousAdminRole = DEFAULT_ADMIN_ROLE;
        }
        MockB20Storage.layout().roleAdmins[role] = newAdminRole;
        emit RoleAdminChanged(role, previousAdminRole, newAdminRole);
    }

    // ============================================================
    //                            PAUSE
    // ============================================================

    function pausedFeatures() external view returns (PausableFeature[] memory) {
        uint256 vectors = MockB20Storage.layout().pausedVectors;
        uint256 count;
        for (uint256 i = 0; i < 4; i++) {
            if (((vectors >> i) & uint256(1)) == 1) count++;
        }
        PausableFeature[] memory result = new PausableFeature[](count);
        uint256 idx;
        for (uint256 i = 0; i < 4; i++) {
            if (((vectors >> i) & uint256(1)) == 1) {
                // forge-lint: disable-next-line(unsafe-typecast)
                result[idx++] = PausableFeature(uint8(i));
            }
        }
        return result;
    }

    function isPaused(PausableFeature feature) public view returns (bool) {
        return _isPaused(feature);
    }

    function pause(PausableFeature[] calldata features) external {
        if (!_isPrivileged()) {
            if (!hasRole(PAUSE_ROLE, msg.sender)) {
                revert AccessControlUnauthorizedAccount(msg.sender, PAUSE_ROLE);
            }
        }
        if (features.length == 0) revert EmptyFeatureSet();
        MockB20Storage.Layout storage $ = MockB20Storage.layout();
        for (uint256 i = 0; i < features.length; i++) {
            $.pausedVectors |= uint256(1) << uint8(features[i]);
        }
        emit Paused(msg.sender, features);
    }

    function unpause(PausableFeature[] calldata features) external {
        if (!_isPrivileged()) {
            if (!hasRole(UNPAUSE_ROLE, msg.sender)) {
                revert AccessControlUnauthorizedAccount(msg.sender, UNPAUSE_ROLE);
            }
        }
        if (features.length == 0) revert EmptyFeatureSet();
        MockB20Storage.Layout storage $ = MockB20Storage.layout();
        for (uint256 i = 0; i < features.length; i++) {
            $.pausedVectors &= ~(uint256(1) << uint8(features[i]));
        }
        emit Unpaused(msg.sender, features);
    }

    // ============================================================
    //                            POLICY
    // ============================================================

    function policyId(bytes32 policyType) external view returns (uint64) {
        return MockB20Storage.layout().policyIds[policyType];
    }

    function updatePolicy(bytes32 policyType, uint64 newPolicyId) external {
        _requireAdmin();
        // Verify the target policy exists in the registry (or is built-in).
        if (!IPolicyRegistry(POLICY_REGISTRY).policyExists(newPolicyId)) {
            revert PolicyNotFound(newPolicyId);
        }
        uint64 oldPolicyId = MockB20Storage.layout().policyIds[policyType];
        MockB20Storage.layout().policyIds[policyType] = newPolicyId;
        emit PolicyUpdated(policyType, oldPolicyId, newPolicyId);
    }

    // ============================================================
    //                          SUPPLY CAP
    // ============================================================

    function supplyCap() external view returns (uint256) {
        return MockB20Storage.layout().supplyCap;
    }

    function setSupplyCap(uint256 newSupplyCap) external {
        _requireAdmin();
        uint256 currentSupply = MockB20Storage.layout().totalSupply;
        if (newSupplyCap < currentSupply) revert InvalidSupplyCap(currentSupply, newSupplyCap);
        uint256 oldSupplyCap = MockB20Storage.layout().supplyCap;
        MockB20Storage.layout().supplyCap = newSupplyCap;
        emit SupplyCapUpdated(msg.sender, oldSupplyCap, newSupplyCap);
    }

    // ============================================================
    //                  PERMIT (EIP-2612 + ERC-5267)
    // ============================================================

    /// @dev Domain content per IB20 spec: chainId and verifyingContract
    ///      only. No name, no version. Type hash is the bare EIP712Domain
    ///      with those two fields.
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");

    /// @dev EIP-2612 permit type hash.
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function nonces(address owner) external view returns (uint256) {
        return MockB20Storage.layout().nonces[owner];
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        if (block.timestamp > deadline) revert ExpiredSignature(deadline);

        MockB20Storage.Layout storage $ = MockB20Storage.layout();
        uint256 nonce = $.nonces[owner];

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));

        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0) || recovered != owner) {
            revert InvalidSigner(recovered, owner);
        }

        unchecked {
            $.nonces[owner] = nonce + 1;
        }
        $.allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name_,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        // Bits 2 and 3 set: chainId and verifyingContract are populated.
        // name, version, salt, extensions are all empty/zero.
        fields = hex"0c";
        name_ = "";
        version = "";
        chainId = block.chainid;
        verifyingContract = address(this);
        salt = bytes32(0);
        extensions = new uint256[](0);
    }

    // ============================================================
    //                      CONTRACT URI (ERC-7572)
    // ============================================================

    function contractURI() external view returns (string memory) {
        return MockB20Storage.layout().contractURI;
    }

    function setContractURI(string calldata newURI) external {
        _requireAdmin();
        MockB20Storage.layout().contractURI = newURI;
        emit ContractURIUpdated();
    }

    // ============================================================
    //                       INTERNAL HELPERS
    // ============================================================

    /// @dev True iff the caller is the factory in the bootstrap window.
    ///      Every authorization gate consults this first; if true, the
    ///      gate is skipped. Token invariants (supply-cap math, balance
    ///      accounting) are NOT gated and are always enforced.
    function _isPrivileged() internal view returns (bool) {
        return msg.sender == FACTORY && !MockB20Storage.layout().initialized;
    }

    function _requireAdmin() internal view {
        if (_isPrivileged()) return;
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, DEFAULT_ADMIN_ROLE);
        }
    }

    function _requireRoleAdmin(bytes32 role) internal view {
        bytes32 adminRole = MockB20Storage.layout().roleAdmins[role];
        if (adminRole == bytes32(0) && role != DEFAULT_ADMIN_ROLE) adminRole = DEFAULT_ADMIN_ROLE;
        if (!hasRole(adminRole, msg.sender)) revert AccessControlUnauthorizedAccount(msg.sender, adminRole);
    }

    function _isPaused(PausableFeature feature) internal view returns (bool) {
        return ((MockB20Storage.layout().pausedVectors >> uint8(feature)) & uint256(1)) == 1;
    }

    /// @dev Resolves an authorization check against the policy registry.
    ///      Reverts with `PolicyForbids` propagated from the caller, not
    ///      raised here, so callers can include the right policyType.
    function _policyAuthorized(uint64 _policyId, address account) internal view returns (bool) {
        return IPolicyRegistry(POLICY_REGISTRY).isAuthorized(_policyId, account);
    }

    function _checkPolicy(bytes32 policyType, address account) internal view {
        uint64 _policyId = MockB20Storage.layout().policyIds[policyType];
        if (!_policyAuthorized(_policyId, account)) revert PolicyForbids(policyType, _policyId);
    }

    function _grantRole(bytes32 role, address account) internal {
        MockB20Storage.Layout storage $ = MockB20Storage.layout();
        if (!$.roles[role][account]) {
            $.roles[role][account] = true;
            if (role == DEFAULT_ADMIN_ROLE) $.adminCount += 1;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _revokeRole(bytes32 role, address account) internal {
        MockB20Storage.Layout storage $ = MockB20Storage.layout();
        if ($.roles[role][account]) {
            $.roles[role][account] = false;
            if (role == DEFAULT_ADMIN_ROLE) $.adminCount -= 1;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    function _consumeAllowance(address owner, address spender, uint256 amount) internal {
        uint256 current = MockB20Storage.layout().allowances[owner][spender];
        if (current != type(uint256).max) {
            if (current < amount) revert InsufficientAllowance(spender, current, amount);
            unchecked {
                MockB20Storage.layout().allowances[owner][spender] = current - amount;
            }
        }
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert InvalidReceiver(to);
        if (from == address(0)) revert InvalidSender(from);

        if (!_isPrivileged()) {
            if (_isPaused(PausableFeature.TRANSFER)) revert ContractPaused(PausableFeature.TRANSFER);
            _checkPolicy(TRANSFER_SENDER, from);
            _checkPolicy(TRANSFER_RECEIVER, to);
        }

        MockB20Storage.Layout storage $ = MockB20Storage.layout();
        uint256 fromBalance = $.balances[from];
        if (fromBalance < amount) revert InsufficientBalance(from, fromBalance, amount);
        unchecked {
            $.balances[from] = fromBalance - amount;
            $.balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        if (to == address(0)) revert InvalidReceiver(to);

        if (!_isPrivileged()) {
            if (!hasRole(MINT_ROLE, msg.sender)) revert AccessControlUnauthorizedAccount(msg.sender, MINT_ROLE);
            if (_isPaused(PausableFeature.MINT)) revert ContractPaused(PausableFeature.MINT);
            _checkPolicy(MINT_RECEIVER, to);
        }

        MockB20Storage.Layout storage $ = MockB20Storage.layout();
        uint256 newSupply = $.totalSupply + amount;
        if (newSupply > $.supplyCap) revert SupplyCapExceeded($.supplyCap, newSupply);
        $.totalSupply = newSupply;
        unchecked {
            $.balances[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burnSelf(address from, uint256 amount) internal {
        if (!_isPrivileged()) {
            if (!hasRole(BURN_ROLE, msg.sender)) revert AccessControlUnauthorizedAccount(msg.sender, BURN_ROLE);
            if (_isPaused(PausableFeature.BURN)) revert ContractPaused(PausableFeature.BURN);
        }
        _burnRaw(from, amount);
    }

    function _burnRaw(address from, uint256 amount) internal {
        MockB20Storage.Layout storage $ = MockB20Storage.layout();
        uint256 fromBalance = $.balances[from];
        if (fromBalance < amount) revert InsufficientBalance(from, fromBalance, amount);
        unchecked {
            $.balances[from] = fromBalance - amount;
            $.totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }
}
