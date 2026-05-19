// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITokenFactory} from "src/interfaces/ITokenFactory.sol";

/// @notice Placeholder mock for the `ITokenFactory` precompile.
///
/// Implements the address-derivation schema in `createToken` /
/// `getTokenAddress` (so the addresses produced by setUp helpers match
/// the documented `[0:10]` prefix / `[10]` variant / `[11]` decimals /
/// `[12:20]` `keccak256(sender, salt)` layout). Every other method
/// reverts pending the full mock implementation in a follow-up PR.
///
/// `createToken` does NOT deploy any code at the returned address — it
/// only computes and returns the deterministic address. The follow-up
/// PR will plant the token bytecode there.
contract MockTokenFactory is ITokenFactory {
    function createToken(TokenVariant variant, bytes32 salt, bytes calldata params, bytes[] calldata /*initCalls*/ )
        external
        returns (address token)
    {
        uint8 decimals;
        if (variant == TokenVariant.DEFAULT) {
            B20CreateParams memory p = abi.decode(params, (B20CreateParams));
            decimals = p.decimals;
        } else if (variant == TokenVariant.STABLECOIN || variant == TokenVariant.SECURITY) {
            decimals = 6;
        } else {
            revert InvalidVariant();
        }

        return _computeAddress(variant, decimals, msg.sender, salt);
    }

    function getTokenAddress(TokenVariant variant, uint8 decimals, address sender, bytes32 salt)
        external
        pure
        returns (address)
    {
        return _computeAddress(variant, decimals, sender, salt);
    }

    function isB20(address token) external pure returns (bool) {
        return _isB20Prefix(token);
    }

    function getTokenVariant(address token) external pure returns (TokenVariant) {
        if (!_isB20Prefix(token)) return TokenVariant.NONE;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 variantByte = uint8(uint160(token) >> 72); // byte [10]; truncation is the read
        if (variantByte > uint8(TokenVariant.SECURITY)) return TokenVariant.NONE;
        return TokenVariant(variantByte);
    }

    // -- Address schema helpers --

    /// @dev Encodes (variant, decimals, sender, salt) into the canonical
    ///      B-20 address layout:
    ///        byte [0]    = 0xB2
    ///        bytes [1:10] = 0x00 (9 zero bytes)
    ///        byte [10]   = variant
    ///        byte [11]   = decimals
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
