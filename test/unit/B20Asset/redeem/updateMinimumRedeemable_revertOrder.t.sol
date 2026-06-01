// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20AssetTest} from "test/lib/B20AssetTest.sol";

import {B20Constants} from "src/lib/B20Constants.sol";

/// @title Differential check-order tests for `updateMinimumRedeemable`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(DEFAULT_ADMIN_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///
///         C(1, 2) = 0 pairs. `updateMinimumRedeemable` has a single revert condition
///         (role check via modifier) and accepts any `uint256` without further
///         validation, so there are no ordering pairs to pin. This file is present
///         for completeness and to document that the single guard is the only revert path.
contract B20AssetUpdateMinimumRedeemableRevertOrderTest is B20AssetTest {}
