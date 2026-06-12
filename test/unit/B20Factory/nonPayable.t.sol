// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";

import {ActivationRegistryFeatureList} from "base-std-test/lib/mocks/ActivationRegistryFeatureList.sol";
import {B20FactoryTest} from "base-std-test/lib/B20FactoryTest.sol";

/// @title Nonpayable guard tests for the B20 factory.
///
/// @notice The factory precompile rejects any call that attaches ETH with `NonPayable`.
///         The guard fires at the very top of dispatch, before activation checks, variant
///         decoding, or any other validation — so value-bearing calls never advance past
///         the pre-flight check regardless of the calldata they carry.
///
/// @dev Tests in this file are skipped in live precompile mode until base/base#3362 (the nonpayable
///      guard implementation) is merged and deployed: before that PR the live precompile
///      silently accepts ETH-bearing calls.
contract B20FactoryNonPayableTest is B20FactoryTest {
    function _deactivate(bytes32 feature) internal {
        vm.prank(StdPrecompiles.ACTIVATION_REGISTRY.admin());
        StdPrecompiles.ACTIVATION_REGISTRY.deactivate(feature);
    }

    /// @notice Verifies `createB20` reverts with `NonPayable` when ETH is attached.
    /// @dev Arbitrary value, variant, and calldata: the guard fires before decoding.
    function test_createB20_revert_nonPayable(address caller, uint256 value, bytes32 salt) public {
        vm.skip(livePrecompiles);
        _assumeValidCaller(caller);
        vm.assume(value != 0);
        vm.deal(caller, value);

        IB20Factory.B20AssetCreateParams memory p = _assetParams();

        vm.prank(caller);
        vm.expectRevert(IB20Factory.NonPayable.selector);
        factory.createB20{value: value}(IB20Factory.B20Variant.ASSET, salt, abi.encode(p), new bytes[](0));
    }

    /// @notice Verifies `NonPayable` fires before activation checks.
    /// @dev Both conditions broken: ETH attached AND the ASSET feature deactivated.
    ///      The nonpayable guard comes first in dispatch — activation is checked second.
    function test_createB20_revertOrder_nonPayable_beats_activation(address caller, uint256 value, bytes32 salt)
        public
    {
        vm.skip(livePrecompiles);
        _assumeValidCaller(caller);
        vm.assume(value != 0);
        vm.deal(caller, value);

        _deactivate(ActivationRegistryFeatureList.B20_ASSET);

        IB20Factory.B20AssetCreateParams memory p = _assetParams();

        vm.prank(caller);
        vm.expectRevert(IB20Factory.NonPayable.selector);
        factory.createB20{value: value}(IB20Factory.B20Variant.ASSET, salt, abi.encode(p), new bytes[](0));
    }
}
