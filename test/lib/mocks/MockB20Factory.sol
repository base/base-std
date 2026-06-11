// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {B20Constants} from "base-std/lib/B20Constants.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";

import {ActivationRegistryFeatureList} from "base-std-test/lib/mocks/ActivationRegistryFeatureList.sol";

import {MockB20Stablecoin} from "base-std-test/lib/mocks/MockB20Stablecoin.sol";
import {MockB20Asset} from "base-std-test/lib/mocks/MockB20Asset.sol";
import {MockB20} from "base-std-test/lib/mocks/MockB20.sol";
import {
    MockB20Storage,
    MockB20AssetStorage,
    MockB20StablecoinStorage
} from "base-std-test/lib/mocks/MockB20Storage.sol";

/// @title MockB20Factory
/// @notice Reference implementation of the `IB20Factory` precompile
///         surface. Etched at `StdPrecompiles.B20_FACTORY_ADDRESS`
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
///         6. Emit `B20Created` (now WITHOUT an `admin` field —
///            see step 7).
///         7. Grant the initial admin role via a single low-level
///            `token.grantRole(DEFAULT_ADMIN_ROLE, admin)` call during
///            the bootstrap-privileged window (`!initialized`). This is
///            the canonical role-grant path: the storage write happens
///            inside `_grantRole` exactly as it would for any later
///            `grantRole` call, and it emits the standard
///            `RoleGranted(DEFAULT_ADMIN_ROLE, admin, factory)` from
///            the token's own context. There is no separate "bootstrap
///            admin write" or "B20Created.admin" field; the canonical
///            event for role changes is always `RoleGranted` regardless
///            of when it fires. Skipped when `admin == address(0)`
///            (the "demonstrate no owner" path).
///         8. Dispatch each `initCalls[i]` via low-level `.call()`
///            so `msg.sender` arrives at the token as `address(this)`
///            (the factory). During the bootstrap window the token
///            bypasses all authorization gates for factory-originated
///            calls per the "fully privileged" semantics on
///            `IB20Factory`.
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
contract MockB20Factory is IB20Factory {
    /// @dev Hardcoded forge-std VM address. The factory uses `vm.etch`
    ///      to plant token bytecode at the deterministic address and
    ///      `vm.store` to write the token's initial state directly.
    ///      The cheatcode dependencies are the structural reason the
    ///      reference impls live under `test/` rather than `src/`.
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @inheritdoc IB20Factory
    function createB20(B20Variant variant, bytes32 salt, bytes calldata params, bytes[] calldata initCalls)
        external
        payable
        returns (address token)
    {
        // -- Pre-flight: reject any call that attaches ETH. Mirrors the Rust precompile's
        //    nonpayable guard which fires before calldata-cost deduction — matched here so
        //    mock and live-precompile surfaces behave identically.
        if (msg.value != 0) revert NonPayable();

        // -- 0. Activation gates.
        //       Per-variant features gate which variants can be created at
        //       any moment. Variant-feature mapping:
        //         STABLECOIN → B20_STABLECOIN
        //         ASSET      → B20_ASSET
        _enforceActivationGates(variant);

        // -- 1. Decode + validate, get the common params --
        string memory name_;
        string memory symbol_;
        address admin;
        uint8 decimals;
        string memory currency_;

        if (variant == B20Variant.ASSET) {
            B20AssetCreateParams memory p = abi.decode(params, (B20AssetCreateParams));
            if (p.version != B20FactoryLib.B20_ASSET_CREATE_PARAMS_VERSION) {
                revert UnsupportedVersion(p.version, variant);
            }
            // Configurable per-token decimals; bounded so wallets, indexers, and
            // downstream integrations stay in the well-supported ERC-20 range.
            if (p.decimals < B20Constants.MIN_ASSET_DECIMALS || p.decimals > B20Constants.MAX_ASSET_DECIMALS) {
                revert InvalidDecimals(p.decimals);
            }
            name_ = p.name;
            symbol_ = p.symbol;
            admin = p.initialAdmin;
            decimals = p.decimals;
        } else if (variant == B20Variant.STABLECOIN) {
            B20StablecoinCreateParams memory p = abi.decode(params, (B20StablecoinCreateParams));
            if (p.version != B20FactoryLib.B20_STABLECOIN_CREATE_PARAMS_VERSION) {
                revert UnsupportedVersion(p.version, variant);
            }
            // Empty currency must be rejected explicitly: the format-check loop below has
            // no bytes to inspect on empty input and would vacuously succeed otherwise.
            // Reverts MissingRequiredField("currency") to match the Rust precompile's selector.
            bytes memory cb = bytes(p.currency);
            if (cb.length == 0) revert MissingRequiredField("currency");
            // Format check: every byte must be an uppercase ASCII letter (A-Z).
            for (uint256 i = 0; i < cb.length; ++i) {
                if (cb[i] < 0x41 || cb[i] > 0x5A) revert InvalidCurrency(p.currency);
            }
            name_ = p.name;
            symbol_ = p.symbol;
            admin = p.initialAdmin;
            decimals = 6;
            currency_ = p.currency;
        } else {
            // Unreachable in Solidity, and intentionally so: an out-of-range `B20Variant` is
            // rejected by ABI enum-decoding (Panic 0x21) before this body runs, so no test can
            // reach it — this is the single line the coverage report shows uncovered, by design.
            // It is retained to mirror the Rust precompile, which decodes the raw discriminator
            // and surfaces this typed `InvalidVariant` revert.
            revert InvalidVariant();
        }

        // -- 2-3. Compute address; refuse to overwrite --
        token = _computeAddress(variant, msg.sender, salt);
        if (token.code.length != 0) revert TokenAlreadyExists(token);

        // -- 4. Etch the variant-appropriate runtime bytecode --
        if (variant == B20Variant.ASSET) {
            vm.etch(token, type(MockB20Asset).runtimeCode);
        } else {
            // STABLECOIN (unknown variants already reverted above).
            vm.etch(token, type(MockB20Stablecoin).runtimeCode);
        }

        // -- 5. Write initial identity / supply-cap state via vm.store.
        //       The admin role is NOT written here; it goes through the
        //       canonical grantRole path in step 7 so RoleGranted fires
        //       from the token.
        _writeBaseStorage(token, name_, symbol_);
        if (variant == B20Variant.ASSET) {
            _writeAssetStorage(token, decimals);
        } else if (variant == B20Variant.STABLECOIN) {
            _writeStablecoinStorage(token, currency_);
        }

        // -- 6. Emit B20Created. Identity-only signal; admin role
        //       assignment is announced via the standard RoleGranted
        //       event from step 7.
        //
        //       The `variantEventParams` field carries variant-specific
        //       immutable identity that isn't already covered by the
        //       fixed event fields. STABLECOIN emits an ABI-encoded
        //       `B20StablecoinEventParams` so stream-based indexers
        //       can recover the immutable `currency`
        //       (ASSET has no variant-specific immutable identity
        //       fields beyond the base set; extra-metadata entries are
        //       mutable and surfaced via their own update events).
        bytes memory variantEventParams;
        if (variant == B20Variant.STABLECOIN) {
            variantEventParams = B20FactoryLib.encodeStablecoinEventParams(currency_);
        }
        emit B20Created(token, variant, name_, symbol_, decimals, variantEventParams);

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
        //       creation. Per IB20Factory.InitCallFailed NatSpec, we
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
        //       `initialized` lives alone in its own slot at the end
        //       of the base layout, so writing the slot is a plain
        //       1-store with no masking against neighbouring fields.
        _writeUint(token, MockB20Storage.initializedSlot(), 1);
    }

    /// @dev `DEFAULT_ADMIN_ROLE` per OZ AccessControl convention.
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);

    /// @inheritdoc IB20Factory
    function getB20Address(B20Variant variant, address sender, bytes32 salt) external pure returns (address) {
        return _computeAddress(variant, sender, salt);
    }

    /// @inheritdoc IB20Factory
    function isB20(address token) external pure returns (bool) {
        return _isB20Prefix(token);
    }

    /// @inheritdoc IB20Factory
    function isB20Initialized(address token) external view returns (bool) {
        if (!_isB20Prefix(token)) return false;
        // Same dedicated slot the factory flips at the end of createToken
        // (MockB20Storage.INITIALIZED_OFFSET). The slot holds nothing
        // else, so any non-zero word means initialized=true.
        return uint256(vm.load(token, MockB20Storage.initializedSlot())) != 0;
    }

    // ============================================================
    //                     ACTIVATION GATING
    // ============================================================

    /// @dev Reverts with `IActivationRegistry.FeatureNotActivated(feature)` if
    ///      the variant-specific gate (`B20_ASSET` for ASSET,
    ///      `B20_STABLECOIN` for STABLECOIN) is not currently activated in
    ///      the registry. Factored out of `createB20` to keep the dispatcher
    ///      body under the EVM stack-depth limit.
    function _enforceActivationGates(B20Variant variant) internal view {
        bytes32 variantFeature = variant == B20Variant.STABLECOIN
            ? ActivationRegistryFeatureList.B20_STABLECOIN
            : ActivationRegistryFeatureList.B20_ASSET;
        StdPrecompiles.ACTIVATION_REGISTRY.checkActivated(variantFeature);
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
    function _computeAddress(B20Variant variant, address sender, bytes32 salt) internal pure returns (address) {
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
        _writeUint(token, MockB20Storage.slotOf(MockB20Storage.SUPPLY_CAP_OFFSET), B20Constants.MAX_SUPPLY_CAP);
        // Everything else (totalSupply, balances, allowances, roles,
        // roleAdmins, adminCount, transferPolicyIds, mintPolicyIds,
        // pausedVectors, nonces, contractURI, initialized) defaults to
        // the EVM's zero state, which is correct for a fresh token.
        // The factory flips `initialized` to true in createToken step 9
        // after initCalls have run.
    }

    /// @dev Writes the asset variant's per-token immutable state at its
    ///      disjoint ERC-7201 namespace (`base.b20.asset`). Today that
    ///      is just `decimals`; `multiplier` defaults to zero
    ///      (interpreted by the read surface as WAD), and announcement /
    ///      identifier maps are empty by default.
    function _writeAssetStorage(address token, uint8 decimals) internal {
        // `decimals` is a `uint8` packed in the low byte of its own slot.
        // Writing the whole slot is safe because the slot is otherwise
        // unused today (future small variant-immutable fields packed into
        // this slot would need this writer to mask instead).
        _writeUint(token, MockB20AssetStorage.decimalsSlot(), uint256(decimals));
    }

    /// @dev Writes the stablecoin variant's `currency` field at its
    ///      disjoint ERC-7201 namespace (`base.b20.stablecoin`).
    function _writeStablecoinStorage(address token, string memory currency_) internal {
        _writeString(token, MockB20StablecoinStorage.slotOf(MockB20StablecoinStorage.CURRENCY_OFFSET), currency_);
    }

    // ============================================================
    //                     STORAGE WRITE PRIMITIVES
    // ============================================================

    function _writeUint(address target, bytes32 slot, uint256 value) internal {
        vm.store(target, slot, bytes32(value));
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
