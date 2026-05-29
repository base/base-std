// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20Factory} from "src/interfaces/IB20Factory.sol";

import {B20FactoryTest} from "test/lib/B20FactoryTest.sol";

contract B20FactoryGetTokenAddressTest is B20FactoryTest {
    /// @notice Wraps an arbitrary uint8 into a valid B20Variant ordinal (as `uint8`).
    /// @dev Bounds to the enum range (DEFAULT=0, STABLECOIN=1, ASSET=2). The factory
    ///      takes `uint8` on the wire (matching the Rust precompile); this helper hands
    ///      back a byte that is guaranteed to pass the entry-point range check.
    function _boundVariant(uint8 variantInt) internal pure returns (uint8) {
        return uint8(bound(uint256(variantInt), 0, uint256(type(IB20Factory.B20Variant).max)));
    }

    /// @notice Verifies getTokenAddress is deterministic for the same inputs
    /// @dev Pure view: repeated calls with identical args must return identical addresses
    function test_getB20Address_success_deterministic(uint8 variantInt, address sender, bytes32 salt) public view {
        uint8 variant = _boundVariant(variantInt);
        address a = factory.getB20Address(variant, sender, salt);
        address b = factory.getB20Address(variant, sender, salt);
        assertEq(a, b, "address derivation must be deterministic");
    }

    /// @notice Verifies different variants produce different addresses for the same (sender, salt)
    /// @dev Variant byte at position [10] is part of the address derivation
    function test_getB20Address_success_differentVariantDiffers(address sender, bytes32 salt) public view {
        address asDefault = factory.getB20Address(uint8(IB20Factory.B20Variant.DEFAULT), sender, salt);
        address asStablecoin = factory.getB20Address(uint8(IB20Factory.B20Variant.STABLECOIN), sender, salt);
        address asSecurity = factory.getB20Address(uint8(IB20Factory.B20Variant.ASSET), sender, salt);
        assertTrue(asDefault != asStablecoin, "DEFAULT vs STABLECOIN must differ");
        assertTrue(asDefault != asSecurity, "DEFAULT vs ASSET must differ");
        assertTrue(asStablecoin != asSecurity, "STABLECOIN vs ASSET must differ");
    }

    /// @notice Verifies different senders produce different addresses for the same (variant, salt)
    /// @dev Sender is mixed into the trailing 9-byte hash at address bytes [11:20]
    function test_getB20Address_success_differentSenderDiffers(uint8 variantInt, address s1, address s2, bytes32 salt)
        public
        view
    {
        vm.assume(s1 != s2);
        uint8 variant = _boundVariant(variantInt);
        address a = factory.getB20Address(variant, s1, salt);
        address b = factory.getB20Address(variant, s2, salt);
        assertTrue(a != b, "different senders must yield different addresses");
    }

    /// @notice Verifies different salts produce different addresses for the same (variant, sender)
    /// @dev Salt is mixed into the trailing 9-byte hash at address bytes [11:20]
    function test_getB20Address_success_differentSaltDiffers(uint8 variantInt, address sender, bytes32 s1, bytes32 s2)
        public
        view
    {
        vm.assume(s1 != s2);
        uint8 variant = _boundVariant(variantInt);
        address a = factory.getB20Address(variant, sender, s1);
        address b = factory.getB20Address(variant, sender, s2);
        assertTrue(a != b, "different salts must yield different addresses");
    }

    /// @notice Verifies the first 10 bytes of the returned address match the B-20 prefix
    /// @dev Address schema: bytes [0:10] are the shared 0xB200...000 prefix
    ///      (byte [0] = 0xB2, bytes [1:9] = 0x00)
    function test_getB20Address_success_prefixIsB20(uint8 variantInt, address sender, bytes32 salt) public view {
        uint8 variant = _boundVariant(variantInt);
        address a = factory.getB20Address(variant, sender, salt);

        // Drop the bottom 10 bytes; what remains should be 0xB2 followed by 9 zero bytes.
        uint160 topTenBytes = uint160(a) >> 80;
        uint160 expected = uint160(0xB2) << 72;
        assertEq(topTenBytes, expected, "top 10 bytes must be 0xB2 followed by 9 zero bytes");
    }

    /// @notice Verifies byte [10] of the returned address equals the variant ordinal
    /// @dev Address schema: variant byte is readable statelessly off the address
    function test_getB20Address_success_variantByteAtPosition10(uint8 variantInt, address sender, bytes32 salt)
        public
        view
    {
        uint8 variant = _boundVariant(variantInt);
        address a = factory.getB20Address(variant, sender, salt);

        // Byte [10] = bits [72..79]. Mask after shift.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 byteAt10 = uint8(uint160(a) >> 72);
        assertEq(byteAt10, variant, "address byte [10] must equal variant ordinal");
    }

    /// @notice Pins the absolute numeric ordinals of B20Variant
    /// @dev The variant byte at address[10] equals the enum ordinal (see
    ///      test_getB20Address_success_variantByteAtPosition10), so the
    ///      ordinals are part of the on-chain address contract. Any
    ///      deliberate reorder must update these constants; this test
    ///      exists so an accidental reorder (e.g. inserting a new
    ///      variant between existing ones) fails loudly instead of
    ///      silently shifting every deployed address.
    function test_tokenVariant_success_ordinalsPinned() public pure {
        assertEq(uint8(IB20Factory.B20Variant.DEFAULT), 0, "DEFAULT ordinal must be 0");
        assertEq(uint8(IB20Factory.B20Variant.STABLECOIN), 1, "STABLECOIN ordinal must be 1");
        assertEq(uint8(IB20Factory.B20Variant.ASSET), 2, "ASSET ordinal must be 2");
    }

    /// @notice Verifies byte [11] comes from the hash tail entropy
    function test_getB20Address_success_byte11DerivedFromTailEntropy(uint8 variantInt, address sender, bytes32 salt)
        public
        view
    {
        uint8 variant = _boundVariant(variantInt);
        address a = factory.getB20Address(variant, sender, salt);

        bytes9 tail = bytes9(keccak256(abi.encode(sender, salt)));
        uint8 expectedByte11 = uint8(uint72(tail) >> 64);
        // Byte [11] = bits [64..71] of the 72-bit tail.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 byteAt11 = uint8(uint160(a) >> 64);
        assertEq(byteAt11, expectedByte11, "address byte [11] must come from tail entropy");
    }

    /// @notice Verifies getB20Address rejects raw variant bytes outside the B20Variant enum range
    ///         with the typed `InvalidVariant()` selector.
    /// @dev The `variant` parameter is typed as `uint8` (not the enum), so any out-of-range
    ///      byte reaches the factory body and is rejected with `InvalidVariant()`, matching
    ///      the Rust precompile's selector exactly. Pinned via `vm.expectRevert(selector)` so
    ///      a silent regression to a decode-time `Panic(0x21)` fails the test instead of
    ///      passing under the bare-`vm.expectRevert()` "any revert" semantics.
    function test_getB20Address_revert_outOfRangeVariant(address sender, bytes32 salt, uint8 badVariant) public {
        badVariant = uint8(bound(uint256(badVariant), uint256(type(IB20Factory.B20Variant).max) + 1, 255));
        vm.expectRevert(IB20Factory.InvalidVariant.selector);
        (bool ok,) =
            address(factory).call(abi.encodeWithSelector(IB20Factory.getB20Address.selector, badVariant, sender, salt));
        ok; // silence unused warning; the revert is asserted via vm.expectRevert.
    }
}
