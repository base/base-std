// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20Factory} from "src/interfaces/IB20Factory.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";

import {B20FactoryTest} from "test/lib/B20FactoryTest.sol";

contract B20FactoryIsB20InitializedTest is B20FactoryTest {
    /// @notice Verifies isB20Initialized returns false for any address lacking the B-20 prefix
    /// @dev Non-B20-prefixed addresses are rejected before any storage read; covers zero address.
    function test_isB20Initialized_success_falseForNonB20Address(address addr) public view {
        vm.assume(!StdPrecompiles.B20_FACTORY.isB20(addr));
        assertFalse(factory.isB20Initialized(addr), "non-B20 address must not be initialized");
    }

    /// @notice Verifies isB20Initialized returns false for the zero address
    /// @dev Edge case: zero address has no prefix bytes and is never a valid B-20.
    function test_isB20Initialized_success_falseForZeroAddress() public view {
        assertFalse(factory.isB20Initialized(address(0)), "zero address must not be initialized");
    }

    /// @notice Verifies isB20Initialized returns false for a B-20-prefixed address never created
    /// @dev isB20 returns true for the same address (prefix check only); isB20Initialized is
    ///      strictly stronger: the address must have been brought to life by createB20.
    function test_isB20Initialized_success_falseForUncreatedB20PrefixedAddress(address sender, bytes32 salt)
        public
        view
    {
        address predicted = factory.getB20Address(IB20Factory.B20Variant.DEFAULT, sender, salt);
        vm.assume(predicted.code.length == 0);
        assertFalse(factory.isB20Initialized(predicted), "B-20-prefixed but uncreated address must not be initialized");
    }

    /// @notice Verifies isB20Initialized returns true for a freshly-created DEFAULT-variant token
    function test_isB20Initialized_success_trueForDefaultToken(bytes32 salt) public {
        address token = _createDefault(alice, salt, _b20Params(), new bytes[](0));
        assertTrue(factory.isB20Initialized(token), "DEFAULT token must be recognized as initialized");
    }

    /// @notice Verifies isB20Initialized returns true for a freshly-created STABLECOIN-variant token
    function test_isB20Initialized_success_trueForStablecoinToken(bytes32 salt) public {
        address token = _createStablecoin(alice, salt, _stablecoinParams(), new bytes[](0));
        assertTrue(factory.isB20Initialized(token), "STABLECOIN token must be recognized as initialized");
    }

    /// @notice Verifies isB20Initialized returns true for a freshly-created SECURITY-variant token
    function test_isB20Initialized_success_trueForSecurityToken(bytes32 salt) public {
        address token = _createSecurity(alice, salt, _securityParams(), new bytes[](0));
        assertTrue(factory.isB20Initialized(token), "SECURITY token must be recognized as initialized");
    }
}
