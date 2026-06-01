// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

/// @title Differential check-order tests for `createPolicy`.
///
/// @notice **Canonical order (Solidity reference `_create`):**
///         1. ZERO-ADMIN (`admin == address(0)`) → `ZeroAddress`
///
///         C(1, 2) = 0 pairs. `createPolicy` has only a single revert
///         condition so there is no pair-wise ordering to pin. This file
///         exists for coverage bookkeeping only; the individual revert is
///         tested in `createPolicy.t.sol`.
// solhint-disable-next-line no-empty-blocks
contract PolicyRegistryCreatePolicyRevertOrderTest is PolicyRegistryTest {}
