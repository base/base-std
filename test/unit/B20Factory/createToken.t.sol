// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Stablecoin} from "base-std/interfaces/IB20Stablecoin.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";

import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";
import {MockB20Storage, MockB20StablecoinStorage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {B20FactoryTest} from "base-std-test/lib/B20FactoryTest.sol";

contract B20FactoryCreateB20Test is B20FactoryTest {
    // Role constants are accessed as `MINT_ROLE` etc. — these are
    // compile-time constants on the contract type, so they don't require an
    // instantiated token (relevant during createToken setup where the token
    // doesn't yet exist).

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies createToken rejects raw variant bytes outside the B20Variant enum range
    /// @dev B20Variant has no "NONE" sentinel; typed callers cannot construct an out-of-range
    ///      value. The ABI decoder rejects out-of-range enum bytes with a Panic(0x21) before the
    ///      factory body's `else { revert InvalidVariant(); }` branch is ever reached, so the
    ///      observable behavior from a raw-bytes caller is a decode-time panic rather than a
    ///      typed factory revert.
    function test_createB20_revert_outOfRangeVariant(address caller, bytes32 salt, uint8 badVariant) public {
        _assumeValidCaller(caller);
        badVariant = uint8(bound(uint256(badVariant), uint256(type(IB20Factory.B20Variant).max) + 1, 255));
        vm.prank(caller);
        // ABI decoder panic for out-of-range enum value.
        vm.expectRevert();
        (bool ok,) = address(factory)
            .call(
                abi.encodeWithSelector(
                    IB20Factory.createB20.selector, badVariant, salt, abi.encode(_stablecoinParams()), new bytes[](0)
                )
            );
        ok; // silence unused warning; the revert is asserted via vm.expectRevert.
    }

    /// @notice Verifies createB20 reverts when the params bytes are not valid ABI-encoded create params
    /// @dev The factory ABI-decodes `params` into the variant's create-params struct after the
    ///      activation gate; a malformed blob fails to decode. The Rust precompile surfaces this as
    ///      AbiDecodeFailed; the Solidity reference reverts at the decoder. A generic expectRevert
    ///      keeps the assertion robust across both. Activation is active by default in setUp, so the
    ///      decode step is reached before any variant-body validation.
    function test_createB20_revert_invalidParamsEncoding(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        // Four bytes is far too short to decode as B20AssetCreateParams (which begins with
        // string-field offset words), so abi.decode reverts.
        bytes memory badParams = hex"deadbeef";

        vm.prank(caller);
        vm.expectRevert();
        factory.createB20(IB20Factory.B20Variant.ASSET, salt, badParams, new bytes[](0));
    }

    /// @notice Verifies createToken reverts for any unsupported version byte on the STABLECOIN variant
    /// @dev Each variant arm has its own version check; this exercises the stablecoin arm's check.
    function test_createB20_revert_unsupportedVersion_stablecoin(address caller, uint8 badVersion, bytes32 salt)
        public
    {
        _assumeValidCaller(caller);
        vm.assume(badVersion != 1);
        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams();
        p.version = badVersion;
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20Factory.UnsupportedVersion.selector, badVersion, IB20Factory.B20Variant.STABLECOIN
            )
        );
        factory.createB20(IB20Factory.B20Variant.STABLECOIN, salt, abi.encode(p), new bytes[](0));
    }

    // STABLECOIN currency validation: every byte must be an uppercase ASCII letter (A-Z).

    /// @notice Any non-empty string containing a non-`A`–`Z` byte reverts with `InvalidCurrency(code)`.
    /// @dev Subsumes every point case (lowercase, digits, symbols, multi-byte UTF-8) via
    ///      `vm.assume(!_isValidFiatCode)`. Empty input is covered by
    ///      `test_createB20_revert_emptyCurrency` (rejected with `MissingRequiredField("currency")`).
    function test_createB20_revert_currency_rejectsInvalidFormat(string memory code, address caller, bytes32 salt)
        public
    {
        _assumeValidCaller(caller);
        vm.assume(bytes(code).length > 0);
        vm.assume(!_isValidFiatCode(code));
        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams("Test", "TST", admin, code);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20Factory.InvalidCurrency.selector, code));
        factory.createB20(IB20Factory.B20Variant.STABLECOIN, salt, abi.encode(p), new bytes[](0));
    }

    function _isValidFiatCode(string memory code) private pure returns (bool) {
        bytes memory b = bytes(code);
        // Empty is not a valid format. Returning true here would make every fuzz test
        // that filters with `vm.assume(!_isValidFiatCode(code))` silently discard empty,
        // hiding the missing-currency case from the suite.
        if (b.length == 0) return false;
        for (uint256 i = 0; i < b.length; ++i) {
            if (b[i] < 0x41 || b[i] > 0x5A) return false;
        }
        return true;
    }

    /// @dev Deterministic seed → 3-letter uppercase ASCII fiat code, guaranteed
    ///      to pass `_isValidFiatCode`. Use in success-path fuzz tests instead of
    ///      `vm.assume(_isValidFiatCode(...))` over a raw `string` input, which
    ///      would hit foundry's rejection-rate ceiling.
    function _make3LetterUppercase(uint256 seed) private pure returns (string memory) {
        bytes memory b = new bytes(3);
        b[0] = bytes1(uint8(0x41 + (seed % 26)));
        b[1] = bytes1(uint8(0x41 + ((seed >> 8) % 26)));
        b[2] = bytes1(uint8(0x41 + ((seed >> 16) % 26)));
        return string(b);
    }

    /// @notice Verifies createToken reverts for any unsupported version byte on the ASSET variant
    /// @dev Each variant arm has its own version check; this exercises the asset arm's check.
    ///      The current supported version is `B20_ASSET_CREATE_PARAMS_VERSION` — fuzzing
    ///      assumes the version byte is anything else.
    function test_createB20_revert_unsupportedVersion_asset(address caller, uint8 badVersion, bytes32 salt) public {
        _assumeValidCaller(caller);
        vm.assume(badVersion != B20FactoryLib.B20_ASSET_CREATE_PARAMS_VERSION);
        IB20Factory.B20AssetCreateParams memory p = _assetParams();
        p.version = badVersion;
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20Factory.UnsupportedVersion.selector, badVersion, IB20Factory.B20Variant.ASSET)
        );
        factory.createB20(IB20Factory.B20Variant.ASSET, salt, abi.encode(p), new bytes[](0));
    }

    /// @notice Verifies stablecoin createToken reverts when currency is the empty string
    /// @dev The format-check loop on `currency` is vacuously safe on empty input (no bytes
    ///      to inspect), so an explicit length check is required to reject empty up front.
    ///      Checks MissingRequiredField("currency") error, matching the Rust precompile's selector.
    function test_createB20_revert_emptyCurrency(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams("Stablecoin Test", "USD", admin, "");
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20Factory.MissingRequiredField.selector, "currency"));
        factory.createB20(IB20Factory.B20Variant.STABLECOIN, salt, abi.encode(p), new bytes[](0));
    }

    /// @notice Verifies createToken reverts when (variant, sender, salt) collides
    /// @dev Deterministic-address uniqueness; checks TokenAlreadyExists(token) error
    function test_createB20_revert_tokenAlreadyExists(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        address first = _createStablecoin(caller, salt, _stablecoinParams(), new bytes[](0));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20Factory.TokenAlreadyExists.selector, first));
        factory.createB20(IB20Factory.B20Variant.STABLECOIN, salt, abi.encode(_stablecoinParams()), new bytes[](0));
    }

    /// @notice Verifies a failing initCall bubbles the underlying revert reason (regression test for L-01)
    /// @dev IB20Factory.InitCallFailed NatSpec (L194-197) specifies two-tier error behavior:
    ///      bubble the underlying revert reason when the call returns one; wrap empty reverts
    ///      with InitCallFailed(index). `mint(address(0), 1)` reverts with `InvalidReceiver(0)`
    ///      inside the token, and the factory MUST surface that error verbatim, not swallow
    ///      it into `InitCallFailed(0)`. A buggy impl that discards revert data via `(bool ok,)`
    ///      surfaces the opaque wrapper instead.
    function test_createB20_revert_initCallFailed_bubblesRevertReason(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        bytes[] memory initCalls = new bytes[](1);
        initCalls[0] = abi.encodeWithSelector(IB20.mint.selector, address(0), uint256(1));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        factory.createB20(IB20Factory.B20Variant.STABLECOIN, salt, abi.encode(_stablecoinParams()), initCalls);
    }

    /// @notice Verifies an empty-revert initCall is wrapped as InitCallFailed(index) (L-01 complement)
    /// @dev The InitCallFailed wrapper is reserved for empty reverts where the underlying call
    ///      returned no data. We trigger this by calling a non-existent selector on the etched
    ///      token; MockB20 has no fallback, so Solidity's dispatcher reverts with empty data.
    ///      Without this carve-out the caller would receive a generic "" revert with no signal
    ///      about which init index failed.
    function test_createB20_revert_initCallFailed_wrapsEmptyRevert(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        bytes[] memory initCalls = new bytes[](1);
        // Non-existent selector "0xdeadbeef" -> MockB20 dispatcher rejects with empty data.
        initCalls[0] = abi.encodeWithSelector(bytes4(0xdeadbeef));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20Factory.InitCallFailed.selector, uint256(0)));
        factory.createB20(IB20Factory.B20Variant.STABLECOIN, salt, abi.encode(_stablecoinParams()), initCalls);
    }

    /// @notice Verifies bubble + index for the SECOND init call (L-01 index correctness)
    /// @dev When the failing call is not at index 0, the bubble must still surface the
    ///      underlying error. A buggy impl that swallows revert data would mask not just
    ///      the error but also the implicit "which index" signal a developer needs to
    ///      debug a multi-call setup.
    function test_createB20_revert_initCallFailed_bubblesFromLaterIndex(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        bytes[] memory initCalls = new bytes[](2);
        // Index 0 is benign — set the supply cap to 100. Index 1 attempts to mint to
        // address(0) and reverts InvalidReceiver(0); we expect that error to bubble.
        initCalls[0] = abi.encodeWithSelector(IB20.updateSupplyCap.selector, uint256(100));
        initCalls[1] = abi.encodeWithSelector(IB20.mint.selector, address(0), uint256(1));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        factory.createB20(IB20Factory.B20Variant.STABLECOIN, salt, abi.encode(_stablecoinParams()), initCalls);
    }

    /// @notice Verifies a failing initCall leaves the deterministic address empty
    /// @dev Atomicity at the storage level: a revert in initCalls means no bytecode was
    ///      committed at the predicted address, so a subsequent createToken with the same
    ///      (variant, sender, salt) succeeds. After L-01 the revert reason is
    ///      bubbled (InvalidReceiver) rather than wrapped (InitCallFailed), but atomicity
    ///      is unchanged.
    function test_createB20_revert_initCallFailed_revertsWholeCreation(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams();
        address predicted = factory.getB20Address(IB20Factory.B20Variant.STABLECOIN, caller, salt);

        bytes[] memory initCalls = new bytes[](1);
        initCalls[0] = abi.encodeWithSelector(IB20.mint.selector, address(0), uint256(1));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        factory.createB20(IB20Factory.B20Variant.STABLECOIN, salt, abi.encode(p), initCalls);

        // After the failed creation, the predicted address has no code,
        // and a fresh creation with the same args succeeds.
        assertEq(predicted.code.length, 0, "predicted address should be empty after revert");
        address retried = _createStablecoin(caller, salt, p, new bytes[](0));
        assertEq(retried, predicted, "retry returns same deterministic address");
    }

    /*//////////////////////////////////////////////////////////////
                               SUCCESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies createToken returns the predicted address for the stablecoin variant
    /// @dev Address determinism: returned address must equal getTokenAddress(STABLECOIN, sender, salt)
    function test_createB20_success_stablecoinMatchesPrediction(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        address predicted = factory.getB20Address(IB20Factory.B20Variant.STABLECOIN, caller, salt);
        address actual = _createStablecoin(caller, salt, _stablecoinParams(), new bytes[](0));
        assertEq(actual, predicted, "createToken address must match prediction");
    }

    /// @notice Verifies createToken returns the predicted address for the asset variant
    /// @dev Address determinism: returned address must equal getTokenAddress(ASSET, sender, salt)
    function test_createB20_success_assetMatchesPrediction(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        address predicted = factory.getB20Address(IB20Factory.B20Variant.ASSET, caller, salt);
        address actual = _createAsset(caller, salt, _assetParams(), new bytes[](0));
        assertEq(actual, predicted, "createToken address must match prediction");
    }

    /// @notice Verifies asset createToken leaves all base policy slots at their
    ///         EVM zero defaults (ALWAYS_ALLOW_ID).
    /// @dev The asset variant adds no extra policy slot of its own, and the factory does not
    ///      override any of the base defaults at creation. Paired surface + slot assertions pin
    ///      both the public read path and the underlying packed slot bytes.
    function test_createB20_success_assetOtherPolicySlotsDefaultToAllow(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        address token = _createAsset(caller, salt, _assetParams(), new bytes[](0));

        assertEq(
            IB20Asset(token).policyId(B20Constants.TRANSFER_SENDER_POLICY),
            PolicyRegistryConstants.ALWAYS_ALLOW_ID,
            "TRANSFER_SENDER_POLICY must still default to ALWAYS_ALLOW_ID"
        );
        assertEq(
            IB20Asset(token).policyId(B20Constants.TRANSFER_RECEIVER_POLICY),
            PolicyRegistryConstants.ALWAYS_ALLOW_ID,
            "TRANSFER_RECEIVER_POLICY must still default to ALWAYS_ALLOW_ID"
        );
        assertEq(
            IB20Asset(token).policyId(B20Constants.TRANSFER_EXECUTOR_POLICY),
            PolicyRegistryConstants.ALWAYS_ALLOW_ID,
            "TRANSFER_EXECUTOR_POLICY must still default to ALWAYS_ALLOW_ID"
        );
        assertEq(
            IB20Asset(token).policyId(B20Constants.MINT_RECEIVER_POLICY),
            PolicyRegistryConstants.ALWAYS_ALLOW_ID,
            "MINT_RECEIVER_POLICY must still default to ALWAYS_ALLOW_ID"
        );
        // Paired slot assertions: the base packed policy slots are at the EVM zero default.
        assertEq(
            vm.load(token, MockB20Storage.transferPolicyIdsSlot()),
            bytes32(0),
            "transferPolicyIds slot must be zero (default state)"
        );
        assertEq(
            vm.load(token, MockB20Storage.mintPolicyIdsSlot()),
            bytes32(0),
            "mintPolicyIds slot must be zero (default state)"
        );
    }

    /// @notice Verifies asset createToken initializes the supply cap to the maximum (uint128.max).
    /// @dev The factory writes `B20Constants.MAX_SUPPLY_CAP` at bootstrap — the unbounded
    ///      ("no cap") sentinel and the highest value the cap may ever hold. Pinning this on the
    ///      factory-creation path (fuzzed caller/salt) means live precompile mode catches a precompile that
    ///      fails to seed the cap at creation. Paired surface + slot assertions.
    function test_createB20_success_assetSupplyCapDefaultsToMax(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        address token = _createAsset(caller, salt, _assetParams(), new bytes[](0));

        assertEq(IB20(token).supplyCap(), B20Constants.MAX_SUPPLY_CAP, "fresh token supply cap must be MAX_SUPPLY_CAP");
        assertEq(
            uint256(vm.load(token, MockB20Storage.supplyCapSlot())),
            B20Constants.MAX_SUPPLY_CAP,
            "supplyCap slot must hold MAX_SUPPLY_CAP at creation"
        );
    }

    /// @notice Verifies asset createToken executes with admin == address(0)
    /// @dev Same zero-admin success behavior on the asset variant. Paired slot assertions
    ///      cross-check the base namespace (adminCount=0, initialized=true).
    function test_createB20_success_zeroAdminGrantsNoRole_asset(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20AssetCreateParams memory p = _assetParams("NoOwner Asset", "NOSEC", address(0));
        address token = _createAsset(caller, salt, p, new bytes[](0));

        assertFalse(MockB20(token).hasRole(B20Constants.DEFAULT_ADMIN_ROLE, address(0)), "zero must not hold admin");
        assertFalse(MockB20(token).hasRole(B20Constants.DEFAULT_ADMIN_ROLE, caller), "caller must not hold admin");

        assertEq(uint256(vm.load(token, MockB20Storage.adminCountSlot())), 0, "adminCount must be 0 on zero-admin path");
        _assertInitialized(token, "initialized must still be set on zero-admin path");
    }

    /// @notice Major reserve currencies (USD, EUR, JPY, GBP, CHF, CNY, CAD, AUD) are accepted.
    /// @dev Round-trip through `currency()` proves the string is stored verbatim.
    function test_createB20_success_currency_acceptsMajorFiatCodes(address caller) public {
        _assumeValidCaller(caller);
        string[8] memory majors = ["USD", "EUR", "JPY", "GBP", "CHF", "CNY", "CAD", "AUD"];
        for (uint256 i = 0; i < majors.length; i++) {
            address token = _createStablecoin(
                caller,
                keccak256(abi.encode("major-fiat", i)),
                _stablecoinParams("Test", "TST", admin, majors[i]),
                new bytes[](0)
            );
            assertEq(
                IB20Stablecoin(token).currency(),
                majors[i],
                "currency() must round-trip the accepted code byte-for-byte"
            );
        }
    }

    /// @notice Multi-country X-prefix fiat (XOF, XAF, XCD, XPF) is accepted.
    /// @dev Pins the deliberate carve-out: X-prefix is not a categorical exclusion.
    function test_createB20_success_currency_acceptsMultiCountryXPrefix(address caller) public {
        _assumeValidCaller(caller);
        string[4] memory xFiat = ["XOF", "XAF", "XCD", "XPF"];
        for (uint256 i = 0; i < xFiat.length; i++) {
            address token = _createStablecoin(
                caller,
                keccak256(abi.encode("xprefix-fiat", i)),
                _stablecoinParams("Test", "TST", admin, xFiat[i]),
                new bytes[](0)
            );
            assertEq(IB20Stablecoin(token).currency(), xFiat[i], "multi-country X-prefix fiat code must round-trip");
        }
    }

    /// @notice Verifies createToken emits B20Created with decimals=6 for the asset variant
    /// @dev Variant-specific dedicated event test: the asset arm pins decimals=6 and asserts
    ///      empty `variantEventParams` (ASSET has no variant-specific immutable identity
    ///      fields beyond the base set; extra-metadata entries are mutable and surfaced via
    ///      their own update events).
    function test_createB20_success_emitsB20Created_asset(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20AssetCreateParams memory p = _assetParams("Asset Test", "AST", admin);
        address predicted = factory.getB20Address(IB20Factory.B20Variant.ASSET, caller, salt);

        vm.expectEmit(true, true, false, true, address(factory));
        emit IB20Factory.B20Created(predicted, IB20Factory.B20Variant.ASSET, "Asset Test", "AST", 6, bytes(""));
        _createAsset(caller, salt, p, new bytes[](0));
    }

    /// @notice Verifies createToken emits B20Created with decimals=6 and a non-empty
    ///         `variantEventParams` payload for the stablecoin variant
    /// @dev    STABLECOIN-only behavior: the `variantEventParams` field carries
    ///         `abi.encode(B20StablecoinEventParams { version, currency })` so stream-based
    ///         indexers can recover the immutable `currency` without an RPC
    ///         call to `currency()`.
    function test_createB20_success_emitsB20Created_stablecoin(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        string memory currency = "USD";
        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams("USD Stable", "USDS", admin, currency);
        address predicted = factory.getB20Address(IB20Factory.B20Variant.STABLECOIN, caller, salt);

        bytes memory expectedVariantParams = abi.encode(
            IB20Factory.B20StablecoinEventParams({
                version: B20FactoryLib.B20_STABLECOIN_EVENT_PARAMS_VERSION, currency: currency
            })
        );

        vm.expectEmit(true, true, false, true, address(factory));
        emit IB20Factory.B20Created(
            predicted, IB20Factory.B20Variant.STABLECOIN, "USD Stable", "USDS", 6, expectedVariantParams
        );
        _createStablecoin(caller, salt, p, new bytes[](0));
    }

    /// @notice Verifies the `variantEventParams` payload of `B20Created` for STABLECOIN decodes
    ///         back to a `B20StablecoinEventParams` whose `currency` round-trips the value
    ///         passed at creation and whose `version` matches the canonical event-encoding
    ///         version constant.
    /// @dev    Decode-level pin (complementary to `_emitsB20Created_stablecoin`'s
    ///         expectEmit-level pin). Catches a future regression that emits a payload with
    ///         the right SHAPE but wrong VERSION or CONTENT — for example, accidentally
    ///         re-using `B20_STABLECOIN_CREATE_PARAMS_VERSION` instead of
    ///         `B20_STABLECOIN_EVENT_PARAMS_VERSION`, or echoing the `name` field instead of
    ///         the `currency` field. Recorded-logs replay so the assertion runs against the
    ///         exact bytes the factory actually emitted, not a re-computed expectation.
    function test_createB20_success_b20CreatedVariantParams_stablecoin_decodes(
        address caller,
        bytes32 salt,
        uint256 currencySeed
    ) public {
        _assumeValidCaller(caller);
        // Generate a guaranteed-valid 3-letter uppercase fiat code from the fuzz seed.
        // Avoids vm.assume rejection-rate exhaustion that filtering random strings would hit.
        string memory currency = _make3LetterUppercase(currencySeed);
        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams("Stable", "STB", admin, currency);

        vm.recordLogs();
        _createStablecoin(caller, salt, p, new bytes[](0));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 selector = IB20Factory.B20Created.selector;
        bytes memory variantEventParams;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == selector) {
                // B20Created data payload: (name, symbol, decimals, variantEventParams).
                (,,, variantEventParams) = abi.decode(logs[i].data, (string, string, uint8, bytes));
                break;
            }
        }
        assertGt(variantEventParams.length, 0, "STABLECOIN variantEventParams must be non-empty");

        IB20Factory.B20StablecoinEventParams memory decoded =
            abi.decode(variantEventParams, (IB20Factory.B20StablecoinEventParams));
        assertEq(
            decoded.version,
            B20FactoryLib.B20_STABLECOIN_EVENT_PARAMS_VERSION,
            "decoded version must equal B20_STABLECOIN_EVENT_PARAMS_VERSION"
        );
        assertEq(decoded.currency, currency, "decoded currency must round-trip the value passed at creation");
    }

    /// @notice Verifies createToken executes each entry in initCalls during the bootstrap window
    /// @dev The bootstrap-window auth bypass is bound to the call site (msg.sender == factory && !initialized),
    ///      not to RBAC. The factory is never granted any role on the token. We verify the bypass by passing
    ///      an initCall (grantRole) that would normally require DEFAULT_ADMIN_ROLE on the caller, and asserting
    ///      it took effect even though the factory has no role.
    function test_createB20_success_executesInitCalls(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        bytes[] memory initCalls = new bytes[](1);
        // Grant MINT_ROLE to bob during the bootstrap window. This would normally
        // require msg.sender to hold DEFAULT_ADMIN_ROLE, but the factory holds no
        // role; the bypass lets the call through.
        initCalls[0] = abi.encodeWithSelector(IB20.grantRole.selector, B20Constants.MINT_ROLE, bob);

        address token = _createStablecoin(caller, salt, _stablecoinParams(), initCalls);
        assertTrue(MockB20(token).hasRole(B20Constants.MINT_ROLE, bob), "init call must have granted role");
        // Factory itself was never granted anything.
        assertFalse(
            MockB20(token).hasRole(B20Constants.DEFAULT_ADMIN_ROLE, address(factory)),
            "factory must not hold admin role"
        );
        // Paired slot assertions confirm the init-call's storage write
        // landed at the canonical role-membership slot AND the bootstrap
        // window closed (initialized bit set, adminCount incremented to 1
        // for the bootstrap admin grant).
        assertEq(
            uint256(vm.load(token, MockB20Storage.roleMembershipSlot(B20Constants.MINT_ROLE, bob))),
            uint256(1),
            "roles[MINT_ROLE][bob] slot must be set by init-call grantRole"
        );
        assertEq(
            uint256(
                vm.load(token, MockB20Storage.roleMembershipSlot(B20Constants.DEFAULT_ADMIN_ROLE, address(factory)))
            ),
            uint256(0),
            "factory must NOT appear in roles[ADMIN] slot"
        );
        assertEq(
            uint256(vm.load(token, MockB20Storage.adminCountSlot())), 1, "adminCount must be 1 after bootstrap grant"
        );
        _assertInitialized(token, "initialized marker must be set after bootstrap closes");
    }

    /// @notice Verifies B20Created fires before any state-change events from initCalls
    /// @dev Log ordering invariant per IB20Factory natspec: "Emits B20Created once the token's identity
    ///      is sealed and BEFORE any initCalls are dispatched, so init-call effects appear strictly after
    ///      the creation event in the log order." Sanity check using vm.recordLogs.
    function test_createB20_success_emitsB20CreatedBeforeInitCallEvents(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        // Use an init call that emits a single, distinctive event we can find: grantRole emits RoleGranted.
        bytes[] memory initCalls = new bytes[](1);
        initCalls[0] = abi.encodeWithSelector(IB20.grantRole.selector, B20Constants.MINT_ROLE, bob);

        vm.recordLogs();
        _createStablecoin(caller, salt, _stablecoinParams(), initCalls);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find indices of B20Created and RoleGranted. Since the storage-direct-write
        // factory emits no RoleGranted at bootstrap, the only RoleGranted in the log
        // is the one from the init call.
        int256 tokenCreatedAt = _firstLogIndex(logs, IB20Factory.B20Created.selector);
        int256 roleGrantedAt = _firstLogIndex(logs, IB20.RoleGranted.selector);
        assertGt(tokenCreatedAt, -1, "B20Created must be present in the log");
        assertGt(roleGrantedAt, -1, "RoleGranted must be present in the log (from initCall)");
        assertLt(tokenCreatedAt, roleGrantedAt, "B20Created must precede initCall-emitted events");
    }

    /// @notice Verifies the factory has no persistent privilege after createToken returns
    /// @dev The bootstrap-window bypass closes when closeBootstrap flips initialized = true. A direct
    ///      call from the factory address after creation must hit the standard auth path and revert.
    function test_createB20_success_factoryHasNoPersistentPrivilege(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        address token = _createStablecoin(caller, salt, _stablecoinParams(), new bytes[](0));

        // Paired assertion: the bootstrap window's gate is the
        // `initialized` marker (mock: dedicated storage slot; live: 0xef
        // bytecode stub at the token address). Confirming it's set
        // proves the factory's privileged path is closed (the
        // surface-level role revert below is the consequence).
        _assertInitialized(token, "initialized marker must be set after createToken returns");

        // Pranking the factory address into a direct mint should now revert with the standard
        // role check, because the bootstrap window is closed.
        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, address(factory), B20Constants.MINT_ROLE
            )
        );
        IB20(token).mint(bob, 1);
    }

    /// @notice Verifies stablecoin createToken executes with admin == address(0)
    /// @dev Same zero-admin success behavior on the stablecoin variant.
    ///      Paired slot assertions cross-check both the base namespace
    ///      (adminCount=0, initialized=true) and the variant namespace
    ///      (currency slot holds the short-string encoding of "USD").
    function test_createB20_success_zeroAdminGrantsNoRole_stablecoin(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams("NoOwner USD", "NOUSD", address(0), "USD");
        address token = _createStablecoin(caller, salt, p, new bytes[](0));

        assertFalse(MockB20(token).hasRole(B20Constants.DEFAULT_ADMIN_ROLE, address(0)), "zero must not hold admin");
        assertFalse(MockB20(token).hasRole(B20Constants.DEFAULT_ADMIN_ROLE, caller), "caller must not hold admin");
        // The stablecoin still got its variant data: currency is set.
        assertEq(IB20Stablecoin(token).currency(), "USD", "stablecoin currency must still be set");

        assertEq(uint256(vm.load(token, MockB20Storage.adminCountSlot())), 0, "adminCount must be 0 on zero-admin path");
        _assertInitialized(token, "initialized must still be set on zero-admin path");
        assertEq(
            vm.load(token, MockB20StablecoinStorage.currencySlot()),
            _expectedStringFieldSlot("USD"),
            "stablecoin currency slot must hold the short-string encoding of \"USD\""
        );
    }

    /// @notice Verifies the variant byte at address position [10] matches the created variant
    /// @dev Address schema: byte [10] of the token address IS the variant; readable
    ///      statelessly off the address with no factory lookup.
    function test_createB20_success_encodesVariantByte(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);

        address stablecoinToken = _createStablecoin(caller, salt, _stablecoinParams(), new bytes[](0));
        assertEq(
            uint256(uint8(uint160(stablecoinToken) >> 72)),
            uint256(IB20Factory.B20Variant.STABLECOIN),
            "stablecoin variant byte mismatch"
        );

        address assetToken = _createAsset(caller, salt, _assetParams(), new bytes[](0));
        assertEq(
            uint256(uint8(uint160(assetToken) >> 72)),
            uint256(IB20Factory.B20Variant.ASSET),
            "asset variant byte mismatch"
        );
    }

    /// @notice Verifies createToken correctly stores name and symbol strings >= 32 bytes
    /// @dev Solidity's storage layout switches encoding at length 32 (short vs long string).
    ///      The factory's _writeString handles both paths via vm.store; this test exercises
    ///      the long-string path explicitly. Short-string path is covered by every other
    ///      success test (default name "USD Test", symbol "USDT" are both < 32 bytes).
    function test_createB20_success_writesLongStrings(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        // Both strings are 40 bytes -> exercises the long-string storage encoding.
        string memory longName = "A token name that is forty bytes long!!!";
        string memory longSymbol = "ASYMBOLALSODELIBERATELYFORTYBYTES.....!!";
        assertEq(bytes(longName).length, 40, "test setup: longName must be 40 bytes");
        assertEq(bytes(longSymbol).length, 40, "test setup: longSymbol must be 40 bytes");

        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams(longName, longSymbol, admin, "USD");
        address tokenAddr = _createStablecoin(caller, salt, p, new bytes[](0));

        assertEq(MockB20(tokenAddr).name(), longName, "long name must round-trip via storage");
        assertEq(MockB20(tokenAddr).symbol(), longSymbol, "long symbol must round-trip via storage");
        // Paired slot assertion: the field slot holds the long-string
        // marker `length * 2 + 1`. Data chunks live at `keccak256(slot)+i`
        // and are exercised implicitly by the surface round-trip above.
        assertEq(
            vm.load(tokenAddr, MockB20Storage.nameSlot()),
            _expectedStringFieldSlot(longName),
            "name field slot must hold the long-string marker"
        );
        assertEq(
            vm.load(tokenAddr, MockB20Storage.symbolSlot()),
            _expectedStringFieldSlot(longSymbol),
            "symbol field slot must hold the long-string marker"
        );
    }

    /// @notice Verifies _writeString pivots into long-string encoding at exactly 32 bytes
    /// @dev Solidity's storage spec: length < 32 -> short (single slot with bytes packed in
    ///      high bytes, 2*length in low byte). length >= 32 -> long (marker slot stores
    ///      2*length+1, data starts at keccak256(slot)). A buggy `<= 32` boundary would
    ///      try to pack 32 bytes into a 31-byte short-string slot, silently losing data.
    ///      Paired slot assertions confirm both 32-byte and 33-byte slots hold
    ///      the long-string marker (low bit set).
    function test_createB20_success_writesStringsAtEncodingBoundary(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        string memory name32 = "abcdefghijklmnopqrstuvwxyzABCDEF";
        string memory symbol33 = "abcdefghijklmnopqrstuvwxyzABCDEFG";
        assertEq(bytes(name32).length, 32, "test setup: name must be exactly 32 bytes");
        assertEq(bytes(symbol33).length, 33, "test setup: symbol must be exactly 33 bytes");

        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams(name32, symbol33, admin, "USD");
        address tokenAddr = _createStablecoin(caller, salt, p, new bytes[](0));

        assertEq(MockB20(tokenAddr).name(), name32, "32-byte name must round-trip (long path)");
        assertEq(MockB20(tokenAddr).symbol(), symbol33, "33-byte symbol must round-trip (chunk-count boundary)");
        assertEq(
            vm.load(tokenAddr, MockB20Storage.nameSlot()),
            _expectedStringFieldSlot(name32),
            "32-byte name field slot must hold the long-string marker (32*2+1 = 65)"
        );
        assertEq(
            vm.load(tokenAddr, MockB20Storage.symbolSlot()),
            _expectedStringFieldSlot(symbol33),
            "33-byte symbol field slot must hold the long-string marker (33*2+1 = 67)"
        );
    }

    /// @notice Pins down that _computeAddress uses abi.encode (not abi.encodePacked)
    /// @dev Internal-determinism tests pass either way because both the predicted and
    ///      actual paths share the same encoding choice. The Rust impl must agree on
    ///      abi.encode specifically; this test recomputes the address externally using
    ///      abi.encode and asserts the factory returns the same value.
    function test_getB20Address_pinsDownAbiEncoding(address sender, bytes32 salt) public view {
        bytes9 expectedTail = bytes9(keccak256(abi.encode(sender, salt)));
        uint160 expectedAddr = (uint160(0xB2) << 152) | (uint160(uint8(IB20Factory.B20Variant.STABLECOIN)) << 72)
            | uint160(uint72(expectedTail));

        address actual = factory.getB20Address(IB20Factory.B20Variant.STABLECOIN, sender, salt);
        assertEq(actual, address(expectedAddr), "factory must derive address via abi.encode of (sender, salt)");
    }

    /// @notice Verifies an empty `name` round-trips as the empty string (regression test for L-04)
    /// @dev The factory's `_writeString` short-string path uses `mload(add(data, 32))` even when
    ///      `data.length == 0`, which reads adjacent memory rather than zero bytes. With name=""
    ///      and symbol="ETH", the ABI decoder places symbol's length word at name's data+32, so
    ///      the slot ends up packed with `or(3, 0) = 0x03`. Solidity's short/long discriminator
    ///      reads the low bit (1 -> long string), then computes length as (3-1)/2 = 1, and reads
    ///      keccak256(slot) for content, returning garbage. The assertion below catches both the
    ///      length-1 long-string interpretation AND any future regressions of the same shape.
    function test_createB20_success_emptyName_roundTripsAsEmpty(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams("", "ETH", admin, "USD");
        address tokenAddr = _createStablecoin(caller, salt, p, new bytes[](0));

        assertEq(MockB20(tokenAddr).name(), "", "empty name must round-trip as empty");
        // Paired slot assertion: the empty-string encoding zeroes the
        // entire field slot. A regression of the OOB-read bug would
        // leave non-zero garbage in the low bits and we'd catch it here.
        assertEq(vm.load(tokenAddr, MockB20Storage.nameSlot()), bytes32(0), "empty name field slot must be all-zero");
    }

    /// @notice Verifies an empty `symbol` round-trips as the empty string (regression test for L-04)
    /// @dev Symmetric to the empty-name test. Symbol is the second string written so the OOB read
    ///      reads past it, into whatever the next memory allocation placed there. Whether it's
    ///      garbage from the free-memory pointer or padded zeros depends on calling context; we
    ///      assert the result is the empty string regardless.
    function test_createB20_success_emptySymbol_roundTripsAsEmpty(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams("Token", "", admin, "USD");
        address tokenAddr = _createStablecoin(caller, salt, p, new bytes[](0));

        assertEq(MockB20(tokenAddr).symbol(), "", "empty symbol must round-trip as empty");
        assertEq(
            vm.load(tokenAddr, MockB20Storage.symbolSlot()), bytes32(0), "empty symbol field slot must be all-zero"
        );
    }

    /// @notice Verifies both empty name and empty symbol round-trip correctly (regression test for L-04)
    /// @dev Belt-and-suspenders: both strings empty is the most degenerate case and would be
    ///      most likely to surface memory-layout assumptions in the writer.
    function test_createB20_success_bothEmpty_roundTripAsEmpty(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams("", "", admin, "USD");
        address tokenAddr = _createStablecoin(caller, salt, p, new bytes[](0));

        assertEq(MockB20(tokenAddr).name(), "", "empty name must round-trip as empty");
        assertEq(MockB20(tokenAddr).symbol(), "", "empty symbol must round-trip as empty");
        assertEq(vm.load(tokenAddr, MockB20Storage.nameSlot()), bytes32(0), "empty name field slot must be all-zero");
        assertEq(
            vm.load(tokenAddr, MockB20Storage.symbolSlot()), bytes32(0), "empty symbol field slot must be all-zero"
        );
    }
}
