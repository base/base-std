// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITokenFactory} from "src/interfaces/ITokenFactory.sol";

import {TokenFactoryTest} from "test/lib/TokenFactoryTest.sol";

contract TokenFactoryGetTokenAddressTest is TokenFactoryTest {
    /// @notice Wraps an arbitrary uint8 into a valid TokenVariant ordinal.
    /// @dev Bounds to [0, 3] (NONE, DEFAULT, STABLECOIN, SECURITY). The address derivation
    ///      is happy with the raw byte but Solidity reverts at function entry on an
    ///      out-of-range enum input from a fuzzer.
    function _boundVariant(uint8 variantInt) internal pure returns (ITokenFactory.TokenVariant) {
        return ITokenFactory.TokenVariant(uint8(bound(uint256(variantInt), 0, 3)));
    }

    /// @notice Verifies getTokenAddress is deterministic for the same inputs
    /// @dev Pure view: repeated calls with identical args must return identical addresses
    function test_getTokenAddress_success_deterministic(uint8 variantInt, uint8 decimals, address sender, bytes32 salt)
        public
        view
    {
        ITokenFactory.TokenVariant variant = _boundVariant(variantInt);
        address a = factory.getTokenAddress(variant, decimals, sender, salt);
        address b = factory.getTokenAddress(variant, decimals, sender, salt);
        assertEq(a, b, "address derivation must be deterministic");
    }

    /// @notice Verifies different variants produce different addresses for the same (decimals, sender, salt)
    /// @dev Variant byte at position [10] is part of the address derivation
    function test_getTokenAddress_success_differentVariantDiffers(uint8 decimals, address sender, bytes32 salt)
        public
        view
    {
        address asDefault = factory.getTokenAddress(ITokenFactory.TokenVariant.DEFAULT, decimals, sender, salt);
        address asStablecoin = factory.getTokenAddress(ITokenFactory.TokenVariant.STABLECOIN, decimals, sender, salt);
        address asSecurity = factory.getTokenAddress(ITokenFactory.TokenVariant.SECURITY, decimals, sender, salt);
        assertTrue(asDefault != asStablecoin, "DEFAULT vs STABLECOIN must differ");
        assertTrue(asDefault != asSecurity, "DEFAULT vs SECURITY must differ");
        assertTrue(asStablecoin != asSecurity, "STABLECOIN vs SECURITY must differ");
    }

    /// @notice Verifies different decimals produce different addresses for the same (variant, sender, salt)
    /// @dev Decimals byte at position [11] is part of the address derivation
    function test_getTokenAddress_success_differentDecimalsDiffers(
        uint8 variantInt,
        address sender,
        bytes32 salt,
        uint8 d1,
        uint8 d2
    ) public view {
        vm.assume(d1 != d2);
        ITokenFactory.TokenVariant variant = _boundVariant(variantInt);
        address a = factory.getTokenAddress(variant, d1, sender, salt);
        address b = factory.getTokenAddress(variant, d2, sender, salt);
        assertTrue(a != b, "different decimals must yield different addresses");
    }

    /// @notice Verifies different senders produce different addresses for the same (variant, decimals, salt)
    /// @dev Sender is mixed into the trailing 8-byte hash at address bytes [12:20]
    function test_getTokenAddress_success_differentSenderDiffers(
        uint8 variantInt,
        uint8 decimals,
        address s1,
        address s2,
        bytes32 salt
    ) public view {
        vm.assume(s1 != s2);
        ITokenFactory.TokenVariant variant = _boundVariant(variantInt);
        address a = factory.getTokenAddress(variant, decimals, s1, salt);
        address b = factory.getTokenAddress(variant, decimals, s2, salt);
        assertTrue(a != b, "different senders must yield different addresses");
    }

    /// @notice Verifies different salts produce different addresses for the same (variant, decimals, sender)
    /// @dev Salt is mixed into the trailing 8-byte hash at address bytes [12:20]
    function test_getTokenAddress_success_differentSaltDiffers(
        uint8 variantInt,
        uint8 decimals,
        address sender,
        bytes32 s1,
        bytes32 s2
    ) public view {
        vm.assume(s1 != s2);
        ITokenFactory.TokenVariant variant = _boundVariant(variantInt);
        address a = factory.getTokenAddress(variant, decimals, sender, s1);
        address b = factory.getTokenAddress(variant, decimals, sender, s2);
        assertTrue(a != b, "different salts must yield different addresses");
    }

    /// @notice Verifies the first 10 bytes of the returned address match the B-20 prefix
    /// @dev Address schema: bytes [0:10] are the shared 0xB200...000 prefix
    ///      (byte [0] = 0xB2, bytes [1:9] = 0x00)
    function test_getTokenAddress_success_prefixIsB20(uint8 variantInt, uint8 decimals, address sender, bytes32 salt)
        public
        view
    {
        ITokenFactory.TokenVariant variant = _boundVariant(variantInt);
        address a = factory.getTokenAddress(variant, decimals, sender, salt);

        // Drop the bottom 10 bytes; what remains should be 0xB2 followed by 9 zero bytes.
        uint160 topTenBytes = uint160(a) >> 80;
        uint160 expected = uint160(0xB2) << 72;
        assertEq(topTenBytes, expected, "top 10 bytes must be 0xB2 followed by 9 zero bytes");
    }

    /// @notice Verifies byte [10] of the returned address equals the variant ordinal
    /// @dev Address schema: variant byte enables stateless getTokenVariant lookup
    function test_getTokenAddress_success_variantByteAtPosition10(
        uint8 variantInt,
        uint8 decimals,
        address sender,
        bytes32 salt
    ) public view {
        ITokenFactory.TokenVariant variant = _boundVariant(variantInt);
        address a = factory.getTokenAddress(variant, decimals, sender, salt);

        // Byte [10] = bits [72..79]. Mask after shift.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 byteAt10 = uint8(uint160(a) >> 72);
        assertEq(byteAt10, uint8(variant), "address byte [10] must equal variant ordinal");
    }

    /// @notice Verifies byte [11] of the returned address equals the decimals value
    /// @dev Address schema: decimals byte enables stateless decimals() lookup
    function test_getTokenAddress_success_decimalsByteAtPosition11(
        uint8 variantInt,
        uint8 decimals,
        address sender,
        bytes32 salt
    ) public view {
        ITokenFactory.TokenVariant variant = _boundVariant(variantInt);
        address a = factory.getTokenAddress(variant, decimals, sender, salt);

        // Byte [11] = bits [64..71]. Mask after shift.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 byteAt11 = uint8(uint160(a) >> 64);
        assertEq(byteAt11, decimals, "address byte [11] must equal decimals");
    }
}
