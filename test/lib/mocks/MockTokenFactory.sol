// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {ITokenFactory} from "src/interfaces/ITokenFactory.sol";

import {MockB20} from "test/lib/mocks/MockB20.sol";
import {MockB20Stablecoin} from "test/lib/mocks/MockB20Stablecoin.sol";

/// @title MockTokenFactory
/// @notice Reference implementation of the `ITokenFactory` precompile
///         surface. Etched at `StdPrecompiles.TOKEN_FACTORY_ADDRESS`
///         in `BaseTest.setUp` so local tests dispatch through this
///         mock; fork tests against a chain with the live precompile
///         hit the real factory at the same address with no test-code
///         changes.
///
/// @dev    `createToken` does what the production precompile does in
///         spirit:
///         1. Decodes variant-specific params (validating the version
///            byte and required-field invariants).
///         2. Computes the deterministic token address per the
///            documented schema (`[0:10]` shared prefix, `[10]` variant
///            byte, `[11]` decimals byte, `[12:20]` derived from
///            `(msg.sender, salt)`).
///         3. Refuses to overwrite an existing token (revert
///            `TokenAlreadyExists`).
///         4. Etches the variant-appropriate mock token bytecode at
///            the computed address.
///         5. Calls `bootstrap(name, symbol, admin, variantData)` on
///            the new token to write identity state and grant the
///            initial admin role.
///         6. Dispatches each `initCalls[i]` via low-level `.call()`
///            so `msg.sender` arrives at the token as `address(this)`
///            (the factory). During the bootstrap window
///            (`!initialized`), the token bypasses all authorization
///            gates for factory-originated calls — see the
///            "fully privileged" semantics documented on
///            `ITokenFactory`.
///         7. Calls `closeBootstrap()` on the token to flip the
///            initialized flag, closing the privileged window. After
///            this point the factory has no special access; all
///            subsequent operations on the token go through standard
///            role / policy / pause checks.
///         8. Emits `TokenCreated`.
///
///         Token invariants (supply-cap math, balance accounting) are
///         NOT bypassed during the privileged window — `initCalls` that
///         would violate an invariant still revert. This matches the
///         spec documented on `ITokenFactory`.
contract MockTokenFactory is ITokenFactory {
    /// @dev Hardcoded forge-std VM address. The factory uses `vm.etch`
    ///      to plant token bytecode at the deterministic address; this
    ///      cheatcode dependency is the structural reason the
    ///      reference impls live under `test/` rather than `src/`.
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @inheritdoc ITokenFactory
    function createToken(TokenVariant variant, bytes32 salt, bytes calldata params, bytes[] calldata initCalls)
        external
        returns (address token)
    {
        // -- 1. Decode + validate, get the four params every variant needs --
        string memory name_;
        string memory symbol_;
        address admin;
        uint8 decimals;
        bytes memory variantData;

        if (variant == TokenVariant.DEFAULT) {
            B20CreateParams memory p = abi.decode(params, (B20CreateParams));
            if (p.version != 1) revert UnsupportedVersion(p.version);
            if (p.decimals < 2 || p.decimals > 18) revert InvalidDecimals(p.decimals);
            name_ = p.name;
            symbol_ = p.symbol;
            admin = p.initialAdmin;
            decimals = p.decimals;
            // No variant data on Default.
            variantData = bytes("");
        } else if (variant == TokenVariant.STABLECOIN) {
            B20StablecoinCreateParams memory p = abi.decode(params, (B20StablecoinCreateParams));
            if (p.version != 1) revert UnsupportedVersion(p.version);
            if (bytes(p.currency).length == 0) revert MissingRequiredField();
            name_ = p.name;
            symbol_ = p.symbol;
            admin = p.initialAdmin;
            decimals = 6;
            variantData = abi.encode(p.currency);
        } else if (variant == TokenVariant.SECURITY) {
            // IB20Security interface is in flux; the reference impl is
            // deferred until it stabilizes. The factory should not
            // silently succeed for an unsupported variant; revert with
            // an unambiguous version-style signal.
            revert UnsupportedVersion(0);
        } else {
            revert InvalidVariant();
        }

        // -- 2-3. Compute address; refuse to overwrite --
        token = _computeAddress(variant, decimals, msg.sender, salt);
        if (token.code.length != 0) revert TokenAlreadyExists(token);

        // -- 4. Etch the variant-appropriate runtime bytecode --
        if (variant == TokenVariant.DEFAULT) {
            vm.etch(token, type(MockB20).runtimeCode);
        } else {
            // STABLECOIN; SECURITY already reverted above.
            vm.etch(token, type(MockB20Stablecoin).runtimeCode);
        }

        // -- 5. Bootstrap: writes identity + grants initial admin --
        MockB20(token).bootstrap(name_, symbol_, admin, variantData);

        // -- 6. Dispatch initCalls. msg.sender at the token is
        //       address(this) == factory, triggering the bootstrap-
        //       window auth bypass. Init-call reverts roll up to abort
        //       the whole creation.
        for (uint256 i = 0; i < initCalls.length; i++) {
            (bool ok,) = token.call(initCalls[i]);
            if (!ok) revert InitCallFailed(i);
        }

        // -- 7. Close the bootstrap window. After this, the factory's
        //       privilege is gone; only role / policy / pause holders
        //       can mutate state.
        MockB20(token).closeBootstrap();

        // -- 8. Emit creation event AFTER identity is sealed and
        //       initCalls have been applied. (initCalls have already
        //       emitted their own state-change events.)
        emit TokenCreated(token, variant, name_, symbol_, decimals);
    }

    /// @inheritdoc ITokenFactory
    function getTokenAddress(TokenVariant variant, uint8 decimals, address sender, bytes32 salt)
        external
        pure
        returns (address)
    {
        return _computeAddress(variant, decimals, sender, salt);
    }

    /// @inheritdoc ITokenFactory
    function isB20(address token) external pure returns (bool) {
        return _isB20Prefix(token);
    }

    /// @inheritdoc ITokenFactory
    function getTokenVariant(address token) external pure returns (TokenVariant) {
        if (!_isB20Prefix(token)) return TokenVariant.NONE;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 variantByte = uint8(uint160(token) >> 72); // byte [10]
        if (variantByte > uint8(TokenVariant.SECURITY)) return TokenVariant.NONE;
        return TokenVariant(variantByte);
    }

    // ============================================================
    //                     ADDRESS SCHEMA HELPERS
    // ============================================================

    /// @dev Encodes (variant, decimals, sender, salt) into the canonical
    ///      B-20 address layout:
    ///        byte [0]      = 0xB2
    ///        bytes [1:10]  = 0x00 (9 zero bytes)
    ///        byte [10]     = variant
    ///        byte [11]     = decimals
    ///        bytes [12:20] = keccak256(sender, salt)[0:8]
    function _computeAddress(TokenVariant variant, uint8 decimals, address sender, bytes32 salt)
        internal
        pure
        returns (address)
    {
        bytes8 tail = bytes8(keccak256(abi.encode(sender, salt)));
        uint160 addr = (uint160(0xB2) << 152) | (uint160(uint8(variant)) << 72) | (uint160(decimals) << 64)
            | uint160(uint64(tail));
        return address(addr);
    }

    /// @dev Returns true iff `token`'s first 10 bytes match the B-20 prefix.
    function _isB20Prefix(address token) internal pure returns (bool) {
        return (uint160(token) >> 80) == (uint160(0xB2) << 72);
    }
}
