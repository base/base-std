// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryTest} from "base-std-test/lib/B20FactoryTest.sol";

contract B20FactoryIsB20Test is B20FactoryTest {
    /// @notice Verifies isB20 returns true for a freshly-created token
    /// @dev Recognition via address-prefix match; no storage read
    function test_isB20_success_trueForCreatedToken(bytes32 salt) public {
        address token = _createStablecoin(alice, salt, _stablecoinParams(), new bytes[](0));
        assertTrue(factory.isB20(token), "freshly created token must be recognized");
    }

    /// @notice Verifies isB20 returns false for any address lacking the B-20 prefix
    /// @dev Fuzz across arbitrary addresses; only the B-20 prefix should pass
    function test_isB20_success_falseForNonB20Address(address addr) public view {
        // Filter out anything that happens to match the B-20 prefix (the factory address
        // itself, and any other 0xB200...000 prefix in the fuzz domain).
        vm.assume((uint160(addr) >> 80) != (uint160(0xB2) << 72));
        assertFalse(factory.isB20(addr), "non-B20 address must not be recognized");
    }

    /// @notice Verifies isB20 returns false for the zero address
    /// @dev Edge case: zero address has no prefix bytes
    function test_isB20_success_falseForZeroAddress() public view {
        assertFalse(factory.isB20(address(0)), "zero address must not be recognized");
    }

    /// @notice Verifies isB20 returns true for any address bearing the B-20 prefix
    /// @dev Recognition is purely prefix-based; the trailing bytes are unconstrained.
    ///      This is intentional: isB20 is a pure prefix check, so synthetic addresses
    ///      that share the prefix but were never created by the factory also pass.
    function test_isB20_success_trueForAnyB20PrefixAddress(uint8 variantByte, bytes9 tail) public view {
        uint160 addr = (uint160(0xB2) << 152) | (uint160(variantByte) << 72) | uint160(uint72(tail));
        assertTrue(factory.isB20(address(addr)), "B-20-prefixed address must be recognized");
    }
}
