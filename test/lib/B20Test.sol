// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryTest} from "base-std-test/lib/B20FactoryTest.sol";

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

/// @notice Base test contract for `IB20` unit tests.
///
/// Extends `B20FactoryTest` because an IB20 token cannot exist
/// without the factory: `setUp` calls `super.setUp()` to etch every
/// precompile mock (via `BaseTest`) and pick up the factory create
/// helpers, then deploys a asset-variant token here so the token's
/// identity byte (variant at address `[10]`) matches the real address
/// schema. In live mode under
/// `--fork-url`, the same flow hits the real precompile factory.
///
/// On top of the inherited factory actors, this contract adds the
/// token-specific role-holders (`minter`, `burner`, `pauser`,
/// `unpauser`, `burnBlocker`) so role-gated tests have explicit named
/// accounts to grant roles to in setUp's initCalls.
contract B20Test is B20FactoryTest {
    // Role constants (DEFAULT_ADMIN_ROLE, MINT_ROLE, BURN_ROLE,
    // BURN_BLOCKED_ROLE, PAUSE_ROLE, UNPAUSE_ROLE, METADATA_ROLE) and
    // policy-type constants (TRANSFER_SENDER_POLICY, TRANSFER_RECEIVER_POLICY,
    // TRANSFER_EXECUTOR_POLICY, MINT_RECEIVER_POLICY) are NOT redeclared here.
    // Tests reference them directly from MockB20 as `MINT_ROLE`
    // etc. — single source of truth, no drift risk.
    //
    // Built-in policy sentinel IDs likewise live on MockPolicyRegistry as
    // `ALWAYS_ALLOW_ID` / `ALWAYS_BLOCK_ID`.

    // -- Token-specific role-holder actors --
    address internal minter = makeAddr("minter");
    address internal burner = makeAddr("burner");
    address internal pauser = makeAddr("pauser");
    address internal unpauser = makeAddr("unpauser");
    address internal burnBlocker = makeAddr("burnBlocker");

    // -- Token under test --
    /// @notice Asset-variant `IB20` token deployed in `setUp`.
    IB20 internal token;

    // -- Setup --
    function setUp() public virtual override {
        super.setUp();

        vm.label(minter, "minter");
        vm.label(burner, "burner");
        vm.label(pauser, "pauser");
        vm.label(unpauser, "unpauser");
        vm.label(burnBlocker, "burnBlocker");

        token = _deployToken();
        vm.label(address(token), "token");
    }

    /// @notice Token-deployment hook. Default impl deploys a asset-variant
    ///         token via the factory mock; variant-specific bases (e.g.
    ///         `B20StablecoinTest`) override to deploy their variant while
    ///         reusing every other piece of `B20Test`.
    /// @dev    `MockB20Factory.createToken` etches `MockB20Asset` runtime
    ///         bytecode at the computed address, writes initial state
    ///         directly via vm.store (no init function on the token),
    ///         runs initCalls, then closes the bootstrap window. Calls
    ///         against the returned `token` (transfer, mint, ...) execute
    ///         against a live mock token with the initial admin granted.
    function _deployToken() internal virtual returns (IB20) {
        return IB20(_createAsset());
    }

    /// @notice Wraps a single `PausableFeature` in a length-1 array for
    ///         `pause` / `unpause` calls. Saves the 3 lines of array
    ///         construction Solidity requires for memory arrays.
    function _singleFeature(IB20.PausableFeature feature)
        internal
        pure
        returns (IB20.PausableFeature[] memory features)
    {
        features = new IB20.PausableFeature[](1);
        features[0] = feature;
    }

    /// @notice Filters out addresses that are unsafe to use as a fuzzed
    ///         token-state actor (balance holder, allowance party, transfer
    ///         counterparty).
    ///
    /// Extends `BaseTest._assumeValidCaller`'s precompile / VM / zero
    /// filtering with the token's own address. Using the token as a
    /// transfer recipient or balance holder is meaningless: the token
    /// has no business holding its own balance, and the underlying
    /// _transfer would still succeed (the policy slots default to
    /// ALWAYS_ALLOW), producing confusing test state.
    function _assumeValidActor(address account) internal view {
        _assumeValidCaller(account);
        vm.assume(account != address(token));
    }

    /// @notice Grants `role` to `account` as the admin actor.
    /// @dev Pranks `admin` (initial holder of `DEFAULT_ADMIN_ROLE` from
    ///      factory bootstrap), so this works even when the role has no
    ///      explicit role-admin configured (defaults to `DEFAULT_ADMIN_ROLE`).
    function _grantRole(bytes32 role, address account) internal {
        vm.prank(admin);
        token.grantRole(role, account);
    }

    /// @notice Mints `amount` to `to`, lazily granting `MINT_ROLE` to the
    ///         `minter` actor on first call.
    /// @dev Most balance-setup needs in tests reduce to "give this account some
    ///      tokens"; this helper avoids re-asserting the role-grant boilerplate.
    function _mint(address to, uint256 amount) internal {
        if (!token.hasRole(B20Constants.MINT_ROLE, minter)) _grantRole(B20Constants.MINT_ROLE, minter);
        vm.prank(minter);
        token.mint(to, amount);
    }

    /// @notice Sets a policy slot on the token as the admin actor.
    /// @dev Use `ALWAYS_ALLOW` (0) or `ALWAYS_REJECT` (type(uint64).max);
    ///      these are the only two policy IDs `MockPolicyRegistry`
    ///      supports today.
    function _setPolicy(bytes32 policyType, uint64 policyId) internal {
        vm.prank(admin);
        token.updatePolicy(policyType, policyId);
    }

    /// @notice Maps a fuzzed `uint8` to one of the four base-token policy
    ///         types. Tests that exercise `policyId` / `updatePolicy`
    ///         must fuzz over the supported set; reads and writes to an
    ///         unsupported `bytes32` revert `UnsupportedPolicyType`.
    /// @dev    Variant tests can wrap this with their own indexer that
    ///         extends the codomain when they add variant-specific
    ///         policy slots.
    function _knownPolicyType(uint8 idx) internal pure returns (bytes32) {
        uint8 i = idx % 4;
        if (i == 0) return B20Constants.TRANSFER_SENDER_POLICY;
        if (i == 1) return B20Constants.TRANSFER_RECEIVER_POLICY;
        if (i == 2) return B20Constants.TRANSFER_EXECUTOR_POLICY;
        return B20Constants.MINT_RECEIVER_POLICY;
    }

    /// @notice True iff `policyType` is supported by the deployed token.
    ///         Used by tests that fuzz arbitrary `bytes32` and need to filter
    ///         to the supported / unsupported partition over the four
    ///         base-token policy types.
    function _isKnownPolicyType(bytes32 policyType) internal pure returns (bool) {
        return policyType == B20Constants.TRANSFER_SENDER_POLICY || policyType == B20Constants.TRANSFER_RECEIVER_POLICY
            || policyType == B20Constants.TRANSFER_EXECUTOR_POLICY || policyType == B20Constants.MINT_RECEIVER_POLICY;
    }

    /// @notice Pauses a single `PausableFeature`, lazily granting `PAUSE_ROLE`
    ///         to the `pauser` actor on first call.
    function _pause(IB20.PausableFeature feature) internal {
        if (!token.hasRole(B20Constants.PAUSE_ROLE, pauser)) _grantRole(B20Constants.PAUSE_ROLE, pauser);
        vm.prank(pauser);
        token.pause(_singleFeature(feature));
    }

    // -- Permit helpers --
    /// @dev EIP-2612 permit type hash; matches MockB20's constant.
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @notice Constructs and signs an EIP-2612 permit digest under the token's
    ///         current DOMAIN_SEPARATOR, with `owner = vm.addr(privateKey)`.
    /// @dev    Reads the current nonce for `owner` so the caller doesn't have to.
    ///         Use `boundPrivateKey(uint256)` to derive a valid secp256k1 key
    ///         from a fuzz seed.
    function _signPermit(uint256 privateKey, address spender, uint256 value, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        return _signPermitAs(privateKey, vm.addr(privateKey), spender, value, deadline);
    }

    /// @notice Constructs and signs an EIP-2612 permit digest where the struct's
    ///         `owner` field is `claimedOwner`, separate from the signing key.
    /// @dev    Used by "wrong-owner" revert tests: the resulting signature is
    ///         well-formed for the digest the contract recomputes (which is
    ///         keyed on `claimedOwner`), so ecrecover deterministically returns
    ///         `vm.addr(privateKey)` rather than garbage.
    function _signPermitAs(uint256 privateKey, address claimedOwner, address spender, uint256 value, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        uint256 nonce = token.nonces(claimedOwner);
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, claimedOwner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(privateKey, digest);
    }
}
