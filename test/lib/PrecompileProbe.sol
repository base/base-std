// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PrecompileProbe
///
/// @notice Smoke-test helper that issues low-level CALL / STATICCALL / DELEGATECALL into the b20
///         precompiles from a real contract frame, capturing success, returndata, and gas consumed.
///         It lets the `precompile_invariants` Python journey assert EVM-context invariants that an
///         EOA + `eth_call` cannot synthesize: STATICCALL read-only enforcement, value forwarding,
///         returndata fidelity (RETURNDATASIZE/RETURNDATACOPY), gas forwarding, and revert atomicity.
///
/// @dev Test-only. Deployed fresh per smoke run; never part of any production deployment. Every probe
///      that expects a failing sub-call captures the outcome instead of bubbling it, so the journey can
///      assert on `ok` rather than relying on the harness's revert plumbing.
contract PrecompileProbe {
    /// @notice Outcome of a probed sub-call.
    ///
    /// @param ok       Whether the sub-call returned successfully (false on revert / OOG).
    /// @param ret      Returndata (return value on success, revert payload on failure).
    /// @param gasUsed  Gas consumed by the sub-call frame as measured by the probe.
    struct Result {
        bool ok;
        bytes ret;
        uint256 gasUsed;
    }

    /// @notice CALL `target` with `data`, forwarding any attached value. Never reverts.
    ///
    /// @dev Used for the value-forwarding invariant: send value to a non-payable precompile method and
    ///      assert `ok == false`.
    function probeCall(address target, bytes calldata data) external payable returns (Result memory r) {
        uint256 g0 = gasleft();
        (bool ok, bytes memory ret) = target.call{value: msg.value}(data);
        r = Result(ok, ret, g0 - gasleft());
    }

    /// @notice STATICCALL `target` with `data`. `ok == false` proves the callee attempted a state write.
    ///
    /// @dev Marked `view` so the journey reaches it with a plain `eth_call`. STATICCALL itself cannot write,
    ///      so a mutating precompile method must revert here.
    function probeStaticcall(address target, bytes calldata data) external view returns (bool ok, bytes memory ret) {
        (ok, ret) = target.staticcall(data);
    }

    /// @notice CALL `target` forwarding at most `gasAmount`; capture whether it fit and gas consumed.
    ///
    /// @dev Used to assert OOG is contained to the sub-frame (outer frame survives, `ok == false`) rather
    ///      than killing the whole transaction.
    function probeCallWithGas(address target, bytes calldata data, uint256 gasAmount)
        external
        returns (Result memory r)
    {
        uint256 g0 = gasleft();
        (bool ok, bytes memory ret) = target.call{gas: gasAmount}(data);
        r = Result(ok, ret, g0 - gasleft());
    }

    /// @notice CALL `target` (expected to revert), then surface the raw returndata via
    ///         RETURNDATASIZE / RETURNDATACOPY.
    ///
    /// @dev Validates that a precompile's revert payload is faithfully exposed in the returndata buffer.
    function probeReturndata(address target, bytes calldata data) external returns (bool ok, bytes memory raw) {
        (ok,) = target.call(data);
        assembly {
            let size := returndatasize()
            raw := mload(0x40)
            mstore(raw, size)
            returndatacopy(add(raw, 0x20), 0, size)
            mstore(0x40, add(add(raw, 0x20), size))
        }
    }

    /// @notice Perform `data` on `target` (which must succeed), then revert the whole frame.
    ///
    /// @dev Used for the atomicity invariant: a committed-then-rolled-back precompile mutation must leave no
    ///      persisted state. The outer journey sends this as a real tx, asserts it reverts, then checks the
    ///      precompile state is unchanged.
    function callThenRevert(address target, bytes calldata data) external {
        (bool ok,) = target.call(data);
        require(ok, "PrecompileProbe: inner call failed");
        revert("PrecompileProbe: intentional rollback");
    }

    receive() external payable {}
}
