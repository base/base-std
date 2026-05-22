// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";
import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";

import {MockB20Storage} from "test/lib/mocks/MockB20Storage.sol";
import {B20Constants} from "src/lib/B20Constants.sol";

/// @title MockB20
/// @notice Reference implementation of the `IB20` default-token surface.
///         Etched at every default-variant B-20 token's factory-derived
///         address via `vm.etch` from `MockB20Factory.createToken`.
///
/// @dev    Written as Solidity-as-if-Rust: the goal is unambiguous
///         spec-correspondence with the production Rust precompile, not
///         gas optimization or Solidity idiom adherence. Specifically:
///
///         - All mutable state lives in `MockB20Storage.layout()` at a
///           single ERC-7201 namespaced root. The struct field order IS
///           the slot layout the Rust impl mirrors; slot offsets are
///           named constants on `MockB20Storage`.
///         - `decimals()` is a fixed `18` on the default variant — no
///           storage slot.
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
    address internal constant FACTORY = StdPrecompiles.B20_FACTORY_ADDRESS;

    /// @notice The policy registry precompile address. Consulted on
    ///         every transfer, mint, and `burnBlocked` to resolve the
    ///         token's configured policy slots.
    address internal constant POLICY_REGISTRY = StdPrecompiles.POLICY_REGISTRY_ADDRESS;

    /// @notice Default top-level admin role. Equal to `bytes32(0)` per
    ///         the OZ AccessControl convention.
    ///
    ///         The `bytes32(0)` identity is load-bearing: because the
    ///         constant equals the EVM storage zero-default, any role
    ///         whose admin has never been set via `setRoleAdmin` falls
    ///         through to DEFAULT_ADMIN_ROLE on a raw read of
    ///         `roleAdmins[role]` with no fall-through code required.
    ///         `getRoleAdmin`, `setRoleAdmin`, and `_requireRoleAdmin`
    ///         all rely on this and do not branch on `role ==
    ///         DEFAULT_ADMIN_ROLE`. The Rust precompile impl reproduces
    ///         the same identity so its own raw read returns the same
    ///         bytes32 for an unconfigured role.
    bytes32 public constant DEFAULT_ADMIN_ROLE = B20Constants.DEFAULT_ADMIN_ROLE;

    /// @notice Role identifiers. Values delegate to `B20Constants` so the
    ///         single-source-of-truth lives in one library; the Rust impl
    ///         derives the same `keccak256` of each role name.
    bytes32 public constant MINT_ROLE = B20Constants.MINT_ROLE;
    bytes32 public constant BURN_ROLE = B20Constants.BURN_ROLE;
    bytes32 public constant BURN_BLOCKED_ROLE = B20Constants.BURN_BLOCKED_ROLE;
    bytes32 public constant PAUSE_ROLE = B20Constants.PAUSE_ROLE;
    bytes32 public constant UNPAUSE_ROLE = B20Constants.UNPAUSE_ROLE;
    bytes32 public constant METADATA_ROLE = B20Constants.METADATA_ROLE;

    /// @notice Policy-type identifiers. Same `keccak256` convention as roles.
    bytes32 public constant TRANSFER_SENDER_POLICY = B20Constants.TRANSFER_SENDER_POLICY;
    bytes32 public constant TRANSFER_RECEIVER_POLICY = B20Constants.TRANSFER_RECEIVER_POLICY;
    bytes32 public constant TRANSFER_EXECUTOR_POLICY = B20Constants.TRANSFER_EXECUTOR_POLICY;
    bytes32 public constant MINT_RECEIVER_POLICY = B20Constants.MINT_RECEIVER_POLICY;

    // ============================================================
    //                          MODIFIERS
    // ============================================================

    /// @dev Gates a function on `msg.sender` holding `role`. Reverts
    ///      `AccessControlUnauthorizedAccount` if not. The factory
    ///      bootstrap window (`_isPrivileged()`) bypasses the check;
    ///      see the contract-level natspec for the bypass invariant.
    ///      Bodies of role-gated functions assume the check has run.
    modifier onlyRole(bytes32 role) {
        _requireRole(role);
        _;
    }

    /// @dev Gates a function on `msg.sender` holding the admin role
    ///      that governs `role` (per `getRoleAdmin`). Same factory
    ///      bypass as `onlyRole`. Used by `grantRole` / `revokeRole`
    ///      / `setRoleAdmin`, where the gate is over the meta-role,
    ///      not the role itself.
    modifier onlyRoleAdmin(bytes32 role) {
        if (!_isPrivileged()) _requireRoleAdmin(role);
        _;
    }

    // ============================================================
    //                          ERC-20: VIEWS
    // ============================================================

    function name() external view returns (string memory) {
        return MockB20Storage.layout().name;
    }

    function symbol() external view returns (string memory) {
        return MockB20Storage.layout().symbol;
    }

    /// @notice Default-variant decimals are fixed at 18.
    function decimals() external pure virtual returns (uint8) {
        return 18;
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
            // Read the executor policy ID out of the transfer-side packed
            // slot. Cold here; warm by the time _transfer reads the same
            // slot for sender + receiver.
            uint64 executorPolicyId = uint64(MockB20Storage.layout().transferPolicyIds >> 128);
            if (!IPolicyRegistry(POLICY_REGISTRY).isAuthorized(executorPolicyId, msg.sender)) {
                revert PolicyForbids(TRANSFER_EXECUTOR_POLICY, executorPolicyId);
            }
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
        emit Memo(msg.sender, memo);
        return true;
    }

    function transferFromWithMemo(address from, address to, uint256 amount, bytes32 memo) external returns (bool) {
        if (!_isPrivileged() && msg.sender != from) {
            _consumeAllowance(from, msg.sender, amount);
            uint64 executorPolicyId = uint64(MockB20Storage.layout().transferPolicyIds >> 128);
            if (!IPolicyRegistry(POLICY_REGISTRY).isAuthorized(executorPolicyId, msg.sender)) {
                revert PolicyForbids(TRANSFER_EXECUTOR_POLICY, executorPolicyId);
            }
        }
        _transfer(from, to, amount);
        emit Memo(msg.sender, memo);
        return true;
    }

    // ============================================================
    //                         METADATA UPDATES
    // ============================================================

    function updateName(string calldata newName) public virtual onlyRole(METADATA_ROLE) {
        MockB20Storage.layout().name = newName;
        emit NameUpdated(msg.sender, newName);
    }

    function updateSymbol(string calldata newSymbol) external onlyRole(METADATA_ROLE) {
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
        emit Memo(msg.sender, memo);
    }

    function burn(uint256 amount) external {
        _burnSelf(msg.sender, amount);
    }

    function burnWithMemo(uint256 amount, bytes32 memo) external {
        _burnSelf(msg.sender, amount);
        emit Memo(msg.sender, memo);
    }

    function burnBlocked(address from, uint256 amount) external onlyRole(BURN_BLOCKED_ROLE) {
        if (!_isPrivileged()) {
            if (_isPaused(PausableFeature.BURN)) revert ContractPaused(PausableFeature.BURN);
            // The point of burnBlocked is to seize from policy-blocked
            // accounts. Read the transfer-sender policy ID out of the
            // transfer-side packed slot and reject if the target is
            // currently authorized.
            uint64 senderPolicyId = uint64(MockB20Storage.layout().transferPolicyIds);
            if (IPolicyRegistry(POLICY_REGISTRY).isAuthorized(senderPolicyId, from)) {
                revert AccountNotBlocked(from);
            }
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
        // Raw read. An unconfigured admin reads as `bytes32(0)`, which
        // IS `DEFAULT_ADMIN_ROLE`, so the OZ "unset roles default to
        // DEFAULT_ADMIN_ROLE" semantics fall out for free — no
        // fall-through ternary required. See the DEFAULT_ADMIN_ROLE
        // constant's natspec for why this identity is load-bearing.
        return MockB20Storage.layout().roleAdmins[role];
    }

    function grantRole(bytes32 role, address account) external onlyRoleAdmin(role) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRoleAdmin(role) {
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address callerConfirmation) external {
        if (callerConfirmation != msg.sender) revert AccessControlBadConfirmation();
        // The last-admin guard fires only when the caller IS the sole remaining admin,
        // per IB20.renounceRole NatSpec. A non-admin caller is not the sole remaining
        // admin and must fall through to _revokeRole, which silently no-ops for callers
        // that don't hold the role — matching OZ AccessControl's renounceRole semantics
        // and preventing defensive batches from reverting unexpectedly.
        MockB20Storage.Layout storage $ = MockB20Storage.layout();
        if (role == DEFAULT_ADMIN_ROLE && $.roles[DEFAULT_ADMIN_ROLE][msg.sender] && $.adminCount == 1) {
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

    function setRoleAdmin(bytes32 role, bytes32 newAdminRole) external onlyRoleAdmin(role) {
        // Raw read for the event payload. An unconfigured admin reads
        // as `bytes32(0)` which IS `DEFAULT_ADMIN_ROLE`, so the
        // `RoleAdminChanged.previousAdminRole` field carries the
        // correct identifier with no fall-through code. See the
        // DEFAULT_ADMIN_ROLE constant's natspec.
        bytes32 previousAdminRole = MockB20Storage.layout().roleAdmins[role];
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

    function pause(PausableFeature[] calldata features) external onlyRole(PAUSE_ROLE) {
        if (features.length == 0) revert EmptyFeatureSet();
        MockB20Storage.Layout storage $ = MockB20Storage.layout();
        for (uint256 i = 0; i < features.length; i++) {
            $.pausedVectors |= uint256(1) << uint8(features[i]);
        }
        emit Paused(msg.sender, features);
    }

    function unpause(PausableFeature[] calldata features) external onlyRole(UNPAUSE_ROLE) {
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
        return _readPolicyId(policyType);
    }

    function updatePolicy(bytes32 policyType, uint64 newPolicyId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Read the old ID for the event payload. Reverts
        // `UnsupportedPolicyType` here if the type has no slot on this token.
        uint64 oldPolicyId = _readPolicyId(policyType);
        // Existence check at write time is what lets `isAuthorized` skip
        // its own existence SLOAD on the hot path. `policyExists` rejects
        // both unknown and malformed IDs.
        if (!IPolicyRegistry(POLICY_REGISTRY).policyExists(newPolicyId)) {
            revert PolicyNotFound(newPolicyId);
        }
        _writePolicyId(policyType, newPolicyId);
        emit PolicyUpdated(policyType, oldPolicyId, newPolicyId);
    }

    /// @dev Reads a policy ID from storage. Each supported policy type
    ///      is routed to its per-operation packed slot (one SLOAD per op,
    ///      four uint64s per slot). Unsupported types REVERT
    ///      `UnsupportedPolicyType` — there is no fallback storage, and
    ///      silently returning 0 (ALWAYS_ALLOW) would let a typo'd query
    ///      masquerade as "no restriction". Variants that add their own
    ///      policy types override this to check their own slots before
    ///      falling through to `super`.
    function _readPolicyId(bytes32 policyType) internal view virtual returns (uint64) {
        MockB20Storage.Layout storage $ = MockB20Storage.layout();
        if (policyType == TRANSFER_SENDER_POLICY) return uint64($.transferPolicyIds);
        if (policyType == TRANSFER_RECEIVER_POLICY) return uint64($.transferPolicyIds >> 64);
        if (policyType == TRANSFER_EXECUTOR_POLICY) return uint64($.transferPolicyIds >> 128);
        if (policyType == MINT_RECEIVER_POLICY) return uint64($.mintPolicyIds);
        revert UnsupportedPolicyType(policyType);
    }

    /// @dev Writes a policy ID to storage. Hot-path types update their
    ///      per-operation packed slot in-place (preserving the other
    ///      three packed lanes); anything else reverts
    ///      `UnsupportedPolicyType` — the token has no slot for it.
    ///      Variants override to handle their own policy types before
    ///      falling through to `super`. Mask + shift are explicit so
    ///      the Rust impl can replicate the exact bit layout.
    function _writePolicyId(bytes32 policyType, uint64 newPolicyId) internal virtual {
        MockB20Storage.Layout storage $ = MockB20Storage.layout();
        uint256 mask = uint256(type(uint64).max);
        if (policyType == TRANSFER_SENDER_POLICY) {
            $.transferPolicyIds = ($.transferPolicyIds & ~mask) | uint256(newPolicyId);
        } else if (policyType == TRANSFER_RECEIVER_POLICY) {
            $.transferPolicyIds = ($.transferPolicyIds & ~(mask << 64)) | (uint256(newPolicyId) << 64);
        } else if (policyType == TRANSFER_EXECUTOR_POLICY) {
            $.transferPolicyIds = ($.transferPolicyIds & ~(mask << 128)) | (uint256(newPolicyId) << 128);
        } else if (policyType == MINT_RECEIVER_POLICY) {
            $.mintPolicyIds = ($.mintPolicyIds & ~mask) | uint256(newPolicyId);
        } else {
            revert UnsupportedPolicyType(policyType);
        }
    }

    // ============================================================
    //                          SUPPLY CAP
    // ============================================================

    function supplyCap() external view returns (uint256) {
        return MockB20Storage.layout().supplyCap;
    }

    function updateSupplyCap(uint256 newSupplyCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
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

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
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
        virtual
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

    function updateContractURI(string calldata newURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
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

    /// @dev Body for the `onlyRole` modifier. Honors the factory bootstrap
    ///      bypass; otherwise reverts `AccessControlUnauthorizedAccount`.
    function _requireRole(bytes32 role) internal view {
        if (_isPrivileged()) return;
        if (!hasRole(role, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, role);
        }
    }

    /// @dev Body for the `onlyRoleAdmin` modifier (the privileged bypass
    ///      lives in the modifier, not here, so this helper is reusable
    ///      from any context that has already cleared the bypass).
    ///      Resolves the admin-of-`role` per `getRoleAdmin` semantics
    ///      via a raw storage read: an unset entry reads as
    ///      `bytes32(0)`, which IS `DEFAULT_ADMIN_ROLE`, so unconfigured
    ///      roles correctly require the default admin to authorize
    ///      without any fall-through code. The revert payload's
    ///      `adminRole` field carries the same identifier — for
    ///      unconfigured roles it's `bytes32(0) == DEFAULT_ADMIN_ROLE`,
    ///      which is the role the caller actually needs to hold.
    function _requireRoleAdmin(bytes32 role) internal view {
        bytes32 adminRole = MockB20Storage.layout().roleAdmins[role];
        if (!hasRole(adminRole, msg.sender)) revert AccessControlUnauthorizedAccount(msg.sender, adminRole);
    }

    function _isPaused(PausableFeature feature) internal view returns (bool) {
        return ((MockB20Storage.layout().pausedVectors >> uint8(feature)) & uint256(1)) == 1;
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
            // One SLOAD pulls both policy IDs we need for the transfer
            // check (and was already warmed if we came in via transferFrom,
            // which reads the executor lane of the same slot first).
            uint256 packed = MockB20Storage.layout().transferPolicyIds;
            uint64 senderPolicyId = uint64(packed);
            uint64 receiverPolicyId = uint64(packed >> 64);
            if (!IPolicyRegistry(POLICY_REGISTRY).isAuthorized(senderPolicyId, from)) {
                revert PolicyForbids(TRANSFER_SENDER_POLICY, senderPolicyId);
            }
            if (!IPolicyRegistry(POLICY_REGISTRY).isAuthorized(receiverPolicyId, to)) {
                revert PolicyForbids(TRANSFER_RECEIVER_POLICY, receiverPolicyId);
            }
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

    function _mint(address to, uint256 amount) internal onlyRole(MINT_ROLE) {
        if (to == address(0)) revert InvalidReceiver(to);

        if (!_isPrivileged()) {
            if (_isPaused(PausableFeature.MINT)) revert ContractPaused(PausableFeature.MINT);
            uint64 mintReceiverPolicyId = uint64(MockB20Storage.layout().mintPolicyIds);
            if (!IPolicyRegistry(POLICY_REGISTRY).isAuthorized(mintReceiverPolicyId, to)) {
                revert PolicyForbids(MINT_RECEIVER_POLICY, mintReceiverPolicyId);
            }
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

    function _burnSelf(address from, uint256 amount) internal onlyRole(BURN_ROLE) {
        if (!_isPrivileged()) {
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
