// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "base-std-test/lib/BaseTest.sol";

/// @notice Base test contract for `B20FactoryLib` unit tests.
///
/// `B20FactoryLib` is a pure encoder library — no storage, no
/// precompile dispatch, no state. The library tests are correspondingly
/// stateless: each test asserts that an encoder's output matches the
/// hand-encoded `abi.encode` / `abi.encodeCall` form, or that a builder
/// produces the expected `bytes[]` shape from typed inputs.
///
/// The base extends `BaseTest` purely for the shared actor pool
/// (`admin`, `alice`, `bob`, `attacker`) and the `_assumeValidCaller`
/// helper, even though the library itself does not consult `msg.sender`.
/// Re-using those gives the test contracts a uniform vocabulary with
/// the rest of the suite. No `setUp` extension is needed.
/// @dev No additional state; `BaseTest`'s actor labels and helpers are sufficient.
contract B20FactoryLibTest is BaseTest {}
