// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {ITokenFactory} from "src/interfaces/ITokenFactory.sol";

import {ISO4217} from "test/lib/ISO4217.sol";

import {MockB20} from "test/lib/mocks/MockB20.sol";
import {MockB20Stablecoin} from "test/lib/mocks/MockB20Stablecoin.sol";
import {MockB20Security} from "test/lib/mocks/MockB20Security.sol";
import {
    MockB20Storage,
    MockB20StablecoinStorage,
    MockB20SecurityStorage,
    MockB20RedeemStorage
} from "test/lib/mocks/MockB20Storage.sol";

/// @title MockTokenFactory
/// @notice Reference implementation of the `ITokenFactory` precompile
///         surface. Etched at `StdPrecompiles.TOKEN_FACTORY_ADDRESS`
///         in `BaseTest.setUp` so local tests dispatch through this
///         mock; fork tests against a chain with the live precompile
///         hit the real factory at the same address with no test-code
///         changes.
///
/// @dev    `createToken` mirrors what the production Rust precompile
///         factory does, step-for-step:
///         1. Decode variant-specific params (validating the version
///            byte and required-field invariants).
///         2. Compute the deterministic token address per the
///            documented schema (`[0:10]` shared prefix, `[10]` variant
///            byte, `[11:20]` derived from
///            `(msg.sender, salt)`).
///         3. Refuse to overwrite an existing token (revert
///            `TokenAlreadyExists`).
///         4. Etch the variant-appropriate mock token bytecode at
///            the computed address.
///         5. **Write the token's initial identity / supply-cap state
///            directly** via `vm.store` at the slot offsets declared in
///            `MockB20Storage`. The token has NO factory-only
///            entrypoints; its surface is exactly `IB20`.
///         6. Emit `TokenCreated` (now WITHOUT an `admin` field —
///            see step 7).
///         7. Grant the initial admin role via a single low-level
///            `token.grantRole(DEFAULT_ADMIN_ROLE, admin)` call during
///            the bootstrap-privileged window (`!initialized`). This is
///            the canonical role-grant path: the storage write happens
///            inside `_grantRole` exactly as it would for any later
///            `grantRole` call, and it emits the standard
///            `RoleGranted(DEFAULT_ADMIN_ROLE, admin, factory)` from
///            the token's own context. There is no separate "bootstrap
///            admin write" or "TokenCreated.admin" field; the canonical
///            event for role changes is always `RoleGranted` regardless
///            of when it fires. Skipped when `admin == address(0)`
///            (the "demonstrate no owner" path).
///         8. Dispatch each `initCalls[i]` via low-level `.call()`
///            so `msg.sender` arrives at the token as `address(this)`
///            (the factory). During the bootstrap window the token
///            bypasses all authorization gates for factory-originated
///            calls per the "fully privileged" semantics on
///            `ITokenFactory`.
///         9. Flip the `initialized` flag (via `vm.store`), closing the
///            privileged window. After this point the factory has no
///            special access; all subsequent operations on the token
///            go through standard role / policy / pause checks.
///
///         Token invariants (supply-cap math, balance accounting) are
///         NOT bypassed during the privileged window: `initCalls` that
///         would violate an invariant still revert.
///
///         **Why a `grantRole` call for the initial admin instead of a
///         direct `vm.store`?** The chain Rust impl will write the role
///         slot directly AND push the corresponding `RoleGranted` log
///         atomically — it's one operation from the precompile's
///         perspective. In Solidity we can't push an LOG with a foreign
///         emitter address; the LOG opcode uses the executing contract's
///         address. To get the log to appear emitted from the token,
///         code must execute at the token's address. The factory's
///         single `token.grantRole(...)` call is the smallest possible
///         such call: it goes through the privileged-window bypass (no
///         extra surface on the token), it writes the same storage slot
///         the Rust impl would, and it emits the same event. The Rust
///         impl's behavior matches the *observable result* even though
///         the path differs (atomic slot-write + log-push vs. a single
///         self-call frame).
contract MockTokenFactory is ITokenFactory {
    /// @dev Hardcoded forge-std VM address. The factory uses `vm.etch`
    ///      to plant token bytecode at the deterministic address and
    ///      `vm.store` to write the token's initial state directly.
    ///      The cheatcode dependencies are the structural reason the
    ///      reference impls live under `test/` rather than `src/`.
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @inheritdoc ITokenFactory
    function createToken(TokenVariant variant, bytes32 salt, bytes calldata params, bytes[] calldata initCalls)
        external
        returns (address token)
    {
        // -- 1. Decode + validate, get the common params --
        string memory name_;
        string memory symbol_;
        address admin;
        uint8 decimals;
        string memory currency_;
        string memory isin_;
        uint256 minimumRedeemable_;

        if (variant == TokenVariant.DEFAULT) {
            B20CreateParams memory p = abi.decode(params, (B20CreateParams));
            if (p.version != 1) revert UnsupportedVersion(p.version);
            name_ = p.name;
            symbol_ = p.symbol;
            admin = p.initialAdmin;
            decimals = 18;
        } else if (variant == TokenVariant.STABLECOIN) {
            B20StablecoinCreateParams memory p = abi.decode(params, (B20StablecoinCreateParams));
            if (p.version != 1) revert UnsupportedVersion(p.version);
            // ISO 4217 fiat allowlist; see docs/b20/stablecoin/currency-validation.md.
            if (!ISO4217.isValidFiatCode(p.currency)) revert InvalidCurrency(p.currency);
            name_ = p.name;
            symbol_ = p.symbol;
            admin = p.initialAdmin;
            decimals = 6;
            currency_ = p.currency;
        } else if (variant == TokenVariant.SECURITY) {
            B20SecurityCreateParams memory p = abi.decode(params, (B20SecurityCreateParams));
            if (p.version != 1) revert UnsupportedVersion(p.version);
            if (bytes(p.isin).length == 0) revert MissingRequiredField();
            name_ = p.name;
            symbol_ = p.symbol;
            admin = p.initialAdmin;
            decimals = 6;
            isin_ = p.isin;
            minimumRedeemable_ = p.minimumRedeemable;
        } else {
            revert InvalidVariant();
        }

        // -- 2-3. Compute address; refuse to overwrite --
        token = _computeAddress(variant, msg.sender, salt);
        if (token.code.length != 0) revert TokenAlreadyExists(token);

        // -- 4. Etch the variant-appropriate runtime bytecode --
        if (variant == TokenVariant.DEFAULT) {
            vm.etch(token, type(MockB20).runtimeCode);
        } else if (variant == TokenVariant.STABLECOIN) {
            vm.etch(token, type(MockB20Stablecoin).runtimeCode);
        } else {
            // SECURITY (NONE / unknown variants already reverted above).
            vm.etch(token, type(MockB20Security).runtimeCode);
        }

        // -- 5. Write initial identity / supply-cap state via vm.store.
        //       The admin role is NOT written here; it goes through the
        //       canonical grantRole path in step 7 so RoleGranted fires
        //       from the token.
        _writeBaseStorage(token, name_, symbol_);
        if (variant == TokenVariant.STABLECOIN) {
            _writeStablecoinStorage(token, currency_);
        } else if (variant == TokenVariant.SECURITY) {
            _writeSecurityStorage(token, isin_, minimumRedeemable_);
        }

        // -- 6. Emit TokenCreated. Identity-only signal; admin role
        //       assignment is announced via the standard RoleGranted
        //       event from step 7.
        emit TokenCreated(token, variant, name_, symbol_, decimals);

        // -- 7. Grant the initial admin role via the canonical path.
        //       msg.sender at the token is address(this) == factory,
        //       and `initialized` is still false (default zero from
        //       fresh storage), so _isPrivileged() returns true and the
        //       role-admin check is bypassed. The grantRole call writes
        //       the role slot AND emits RoleGranted from the token.
        //       Skipped on the zero-admin path.
        if (admin != address(0)) {
            MockB20(token).grantRole(DEFAULT_ADMIN_ROLE, admin);
        }

        // -- 8. Dispatch initCalls. Same privileged-window bypass as
        //       step 7; init-call reverts roll up to abort the whole
        //       creation. Per ITokenFactory.InitCallFailed NatSpec, we
        //       bubble the underlying revert data when present so
        //       developers see the actual cause (e.g. InvalidReceiver,
        //       SupplyCapExceeded) rather than an opaque wrapper. Only
        //       empty reverts get wrapped with InitCallFailed(i), which
        //       preserves the "which index failed" signal that the
        //       bubbled-error case provides implicitly via the error
        //       itself.
        for (uint256 i = 0; i < initCalls.length; i++) {
            (bool ok, bytes memory reason) = token.call(initCalls[i]);
            if (!ok) {
                if (reason.length > 0) {
                    assembly {
                        revert(add(reason, 32), mload(reason))
                    }
                }
                revert InitCallFailed(i);
            }
        }

        // -- 9. Close the bootstrap window by setting initialized=true.
        //       After this, the factory's privilege is gone; only
        //       role / policy / pause holders can mutate state.
        _writePackedBool(
            token,
            MockB20Storage.slotOf(MockB20Storage.INITIALIZED_OFFSET),
            MockB20Storage.INITIALIZED_BYTE_OFFSET,
            true
        );
    }

    /// @dev `DEFAULT_ADMIN_ROLE` per OZ AccessControl convention.
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);

    /// @inheritdoc ITokenFactory
    function getTokenAddress(TokenVariant variant, address sender, bytes32 salt) external pure returns (address) {
        return _computeAddress(variant, sender, salt);
    }

    /// @inheritdoc ITokenFactory
    function isB20(address token) external pure returns (bool) {
        return _isB20Prefix(token);
    }

    /// @inheritdoc ITokenFactory
    function isB20Initialized(address token) external view returns (bool) {
        if (!_isB20Prefix(token)) return false;
        // Same packed-bool slot the factory flips at the end of
        // createToken (MockB20Storage.INITIALIZED_OFFSET +
        // INITIALIZED_BYTE_OFFSET).
        bytes32 slot = MockB20Storage.slotOf(MockB20Storage.INITIALIZED_OFFSET);
        uint256 word = uint256(vm.load(token, slot));
        uint256 shift = uint256(MockB20Storage.INITIALIZED_BYTE_OFFSET) * 8;
        return ((word >> shift) & 0xff) != 0;
    }

    // ============================================================
    //                     ADDRESS SCHEMA HELPERS
    // ============================================================

    /// @dev Encodes (variant, sender, salt) into the canonical
    ///      B-20 address layout:
    ///        byte [0]      = 0xB2
    ///        bytes [1:10]  = 0x00 (9 zero bytes)
    ///        byte [10]     = variant
    ///        bytes [11:20] = keccak256(sender, salt)[0:9]
    function _computeAddress(TokenVariant variant, address sender, bytes32 salt) internal pure returns (address) {
        bytes9 tail = bytes9(keccak256(abi.encode(sender, salt)));
        uint160 addr = (uint160(0xB2) << 152) | (uint160(uint8(variant)) << 72) | uint160(uint72(tail));
        return address(addr);
    }

    /// @dev Returns true iff `token`'s first 10 bytes match the B-20 prefix.
    function _isB20Prefix(address token) internal pure returns (bool) {
        return (uint160(token) >> 80) == (uint160(0xB2) << 72);
    }

    // ============================================================
    //                     INITIAL-STATE WRITERS
    // ============================================================
    // These write the token's initial storage directly via vm.store
    // at the slot offsets declared in MockB20Storage. The Rust impl
    // writes the same slots with the same values; the offsets +
    // ERC-7201 namespace are the storage-layout contract between the
    // two implementations.

    /// @dev Writes the identity + supply-cap state every B-20 starts
    ///      with. The admin role is NOT written here — see the
    ///      `grantRole` call in `createToken` step 7 for why.
    function _writeBaseStorage(address token, string memory name_, string memory symbol_) internal {
        _writeString(token, MockB20Storage.slotOf(MockB20Storage.NAME_OFFSET), name_);
        _writeString(token, MockB20Storage.slotOf(MockB20Storage.SYMBOL_OFFSET), symbol_);
        _writeUint(token, MockB20Storage.slotOf(MockB20Storage.SUPPLY_CAP_OFFSET), type(uint256).max);
        // Everything else (totalSupply, allowances, roles, roleAdmins,
        // adminCount, transferPolicyIds, mintPolicyIds, pausedVectors,
        // nonces, contractURI, initialized) defaults to the EVM's zero
        // state, which is correct for a fresh token.
    }

    /// @dev Writes the stablecoin variant's `currency` field at its
    ///      disjoint ERC-7201 namespace (`base.b20.stablecoin`).
    function _writeStablecoinStorage(address token, string memory currency_) internal {
        _writeString(token, MockB20StablecoinStorage.slotOf(MockB20StablecoinStorage.CURRENCY_OFFSET), currency_);
    }

    /// @dev Writes the security variant's initial `identifiers["ISIN"]`
    ///      entry at the `base.b20.security` namespace and the initial
    ///      `minimumRedeemable` at the `base.b20.redeem` namespace.
    ///      Mirrors stablecoin's `currency` pattern: variant-specific
    ///      initial state is written directly without an event,
    ///      paralleling how base identity (name, symbol, supply cap) is
    ///      seeded. Post-creation identifier mutations go through
    ///      `updateSecurityIdentifier` and emit `SecurityIdentifierUpdated`.
    function _writeSecurityStorage(address token, string memory isin_, uint256 minimumRedeemable_) internal {
        _writeString(token, MockB20SecurityStorage.identifierSlot("ISIN"), isin_);
        _writeUint(token, MockB20RedeemStorage.minimumRedeemableSlot(), minimumRedeemable_);
    }

    // ============================================================
    //                     STORAGE WRITE PRIMITIVES
    // ============================================================

    function _writeUint(address target, bytes32 slot, uint256 value) internal {
        vm.store(target, slot, bytes32(value));
    }

    function _writePackedBool(address target, bytes32 slot, uint8 byteOffset, bool value) internal {
        uint256 shift = uint256(byteOffset) * 8;
        uint256 mask = uint256(0xff) << shift;
        uint256 current = uint256(vm.load(target, slot));
        uint256 bit = value ? (uint256(1) << shift) : 0;
        vm.store(target, slot, bytes32((current & ~mask) | bit));
    }

    /// @dev Solidity string storage encoding:
    ///        - length < 32:  one slot, `(data << 0) | (length * 2)` with
    ///                         the bytes in the high portion and `length*2`
    ///                         in the low byte (low bit clear -> short).
    ///        - length >= 32: slot stores `(length * 2) | 1` (low bit set
    ///                         -> long), data starts at `keccak256(slot)`
    ///                         and runs sequentially.
    function _writeString(address target, bytes32 slot, string memory value) internal {
        bytes memory data = bytes(value);
        if (data.length == 0) {
            // Solidity's short-string encoding for "" is a zeroed slot: high portion
            // empty, low byte = data.length * 2 = 0. Writing this explicitly avoids
            // reading adjacent memory at `data + 32`, which would otherwise pick up
            // whatever the next allocation placed there (e.g. another string's length
            // word) and produce a corrupted slot. EVM zero-initialization means an
            // unwritten slot is already 0x00...00, so we can no-op; we still call
            // vm.store to remain explicit and idempotent for re-creation paths.
            vm.store(target, slot, bytes32(0));
        } else if (data.length < 32) {
            bytes32 packed;
            assembly {
                // High portion: first 32 bytes of memory at data+32 (the string body).
                // Safe because data.length > 0 guarantees at least one body byte is
                // allocated; trailing bytes are implicit-zero-padded within the same
                // 32-byte word that Solidity allocates for short bytes/string types.
                // Low byte: data.length * 2 (low bit clear marks "short string").
                packed := or(mload(add(data, 32)), mul(mload(data), 2))
            }
            vm.store(target, slot, packed);
        } else {
            // Long string: marker slot, then data chunks at keccak256(slot)+i.
            vm.store(target, slot, bytes32(data.length * 2 + 1));
            bytes32 dataStart = keccak256(abi.encode(slot));
            uint256 chunks = (data.length + 31) / 32;
            for (uint256 i = 0; i < chunks; i++) {
                bytes32 chunk;
                assembly {
                    chunk := mload(add(add(data, 32), mul(i, 32)))
                }
                vm.store(target, bytes32(uint256(dataStart) + i), chunk);
            }
        }
    }
}
