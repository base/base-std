// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITokenFactory} from "src/interfaces/ITokenFactory.sol";

import {TokenFactoryTest} from "test/lib/TokenFactoryTest.sol";

contract TokenFactoryGetTokenVariantTest is TokenFactoryTest {
    /// @notice Verifies getTokenVariant returns DEFAULT for a default-variant token
    /// @dev Variant byte at position [10] decodes back to the creation variant
    function test_getTokenVariant_success_defaultRecovered(bytes32 salt) public {
        address token = _createDefault(alice, salt, _b20Params(), new bytes[](0));
        assertEq(
            uint256(factory.getTokenVariant(token)),
            uint256(ITokenFactory.TokenVariant.DEFAULT),
            "must recover DEFAULT"
        );
    }

    /// @notice Verifies getTokenVariant returns STABLECOIN for a stablecoin-variant token
    /// @dev Variant byte at position [10] decodes back to the creation variant
    function test_getTokenVariant_success_stablecoinRecovered(bytes32 salt) public {
        address token = _createStablecoin(alice, salt, _stablecoinParams(), new bytes[](0));
        assertEq(
            uint256(factory.getTokenVariant(token)),
            uint256(ITokenFactory.TokenVariant.STABLECOIN),
            "must recover STABLECOIN"
        );
    }

    /// @notice Verifies getTokenVariant returns NONE for any address lacking the B-20 prefix
    /// @dev Non-factory addresses are not categorized as any variant
    function test_getTokenVariant_success_noneForNonB20(address addr) public view {
        // Filter out anything that happens to match the B-20 prefix.
        vm.assume((uint160(addr) >> 80) != (uint160(0xB2) << 72));
        assertEq(
            uint256(factory.getTokenVariant(addr)),
            uint256(ITokenFactory.TokenVariant.NONE),
            "non-B20 address must return NONE"
        );
    }

    /// @notice Verifies getTokenVariant returns NONE for B-20-prefixed addresses with an invalid variant byte
    /// @dev Bytes >= 4 in position [10] are not valid TokenVariant ordinals; impl returns NONE rather than
    ///      reverting on out-of-range enum cast.
    function test_getTokenVariant_success_noneForInvalidVariantByte(uint8 invalidByte, bytes9 tail)
        public
        view
    {
        invalidByte = uint8(bound(uint256(invalidByte), 4, 255));
        uint160 addr = (uint160(0xB2) << 152) | (uint160(invalidByte) << 72) | uint160(uint72(tail));
        assertEq(
            uint256(factory.getTokenVariant(address(addr))),
            uint256(ITokenFactory.TokenVariant.NONE),
            "invalid variant byte must return NONE"
        );
    }
}
