// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";

/// @title Differential check-order tests for `updateName`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(METADATA_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///
///         C(1, 2) = 0 pairs. `updateName` has only a single revert condition
///         so there is no pair-wise ordering to pin. This file exists for coverage
///         bookkeeping only; the individual revert is tested in `updateName.t.sol`.
// solhint-disable-next-line no-empty-blocks
contract B20UpdateNameRevertOrderTest is B20Test {}
