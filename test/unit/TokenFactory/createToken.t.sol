// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Stablecoin} from "src/interfaces/IB20Stablecoin.sol";
import {ITokenFactory} from "src/interfaces/ITokenFactory.sol";

import {MockB20} from "test/lib/mocks/MockB20.sol";
import {TokenFactoryTest} from "test/lib/TokenFactoryTest.sol";

contract TokenFactoryCreateTokenTest is TokenFactoryTest {
    // Role identifiers, matching MockB20's keccak256 derivations. Inlined here
    // because Solidity contract constants are runtime getters, so MockB20(addr).MINT_ROLE()
    // requires `addr` to have code -- and during createToken setup, the token doesn't exist yet.
    bytes32 internal constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies createToken reverts for the NONE variant
    /// @dev Variant guard fires before any param decoding; checks InvalidVariant() error
    function test_createToken_revert_invalidVariant(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        vm.prank(caller);
        vm.expectRevert(ITokenFactory.InvalidVariant.selector);
        factory.createToken(ITokenFactory.TokenVariant.NONE, salt, abi.encode(_b20Params()), new bytes[](0));
    }

    /// @notice Verifies createToken reverts for any unsupported params version byte
    /// @dev Fuzz confirms only the known version (1) decodes; checks UnsupportedVersion(version) error
    function test_createToken_revert_unsupportedVersion(address caller, uint8 badVersion, bytes32 salt) public {
        _assumeValidCaller(caller);
        vm.assume(badVersion != 1);
        ITokenFactory.B20CreateParams memory p = _b20Params();
        p.version = badVersion;
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ITokenFactory.UnsupportedVersion.selector, badVersion));
        factory.createToken(ITokenFactory.TokenVariant.DEFAULT, salt, abi.encode(p), new bytes[](0));
    }

    /// @notice Verifies createToken reverts for default-variant decimals outside [2, 18]
    /// @dev Fuzz confirms the per-variant decimals range is enforced; checks InvalidDecimals(decimals) error
    function test_createToken_revert_invalidDecimals(address caller, uint8 decimals, bytes32 salt) public {
        _assumeValidCaller(caller);
        vm.assume(decimals < 2 || decimals > 18);
        ITokenFactory.B20CreateParams memory p = _b20Params("Test", "TST", admin, decimals);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ITokenFactory.InvalidDecimals.selector, decimals));
        factory.createToken(ITokenFactory.TokenVariant.DEFAULT, salt, abi.encode(p), new bytes[](0));
    }

    /// @notice Verifies stablecoin createToken reverts when currency is the empty string
    /// @dev Per-variant required-field check; checks MissingRequiredField() error
    function test_createToken_revert_missingCurrency(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        ITokenFactory.B20StablecoinCreateParams memory p = _stablecoinParams("USD Test", "USDT", admin, "");
        vm.prank(caller);
        vm.expectRevert(ITokenFactory.MissingRequiredField.selector);
        factory.createToken(ITokenFactory.TokenVariant.STABLECOIN, salt, abi.encode(p), new bytes[](0));
    }

    /// @notice Verifies createToken reverts when (variant, decimals, sender, salt) collides
    /// @dev Deterministic-address uniqueness; checks TokenAlreadyExists(token) error
    function test_createToken_revert_tokenAlreadyExists(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        address first = _createDefault(caller, salt, _b20Params(), new bytes[](0));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ITokenFactory.TokenAlreadyExists.selector, first));
        factory.createToken(
            ITokenFactory.TokenVariant.DEFAULT, salt, abi.encode(_b20Params()), new bytes[](0)
        );
    }

    /// @notice Verifies createToken reverts when any entry in initCalls reverts
    /// @dev Init-call atomicity: a single failing init call reverts the entire creation
    function test_createToken_revert_initCallFailed(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        // mint to address(0) reverts InvalidReceiver inside the token,
        // which bubbles up as InitCallFailed(0) at the factory.
        bytes[] memory initCalls = new bytes[](1);
        initCalls[0] = abi.encodeWithSelector(IB20.mint.selector, address(0), uint256(1));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ITokenFactory.InitCallFailed.selector, uint256(0)));
        factory.createToken(ITokenFactory.TokenVariant.DEFAULT, salt, abi.encode(_b20Params()), initCalls);
    }

    /// @notice Verifies a failing initCall leaves the deterministic address empty
    /// @dev Atomicity at the storage level: a revert in initCalls means no bytecode was
    ///      committed at the predicted address, so a subsequent createToken with the same
    ///      (variant, decimals, sender, salt) succeeds.
    function test_createToken_revert_initCallFailed_revertsWholeCreation(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        ITokenFactory.B20CreateParams memory p = _b20Params();
        address predicted =
            factory.getTokenAddress(ITokenFactory.TokenVariant.DEFAULT, p.decimals, caller, salt);

        bytes[] memory initCalls = new bytes[](1);
        initCalls[0] = abi.encodeWithSelector(IB20.mint.selector, address(0), uint256(1));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ITokenFactory.InitCallFailed.selector, uint256(0)));
        factory.createToken(ITokenFactory.TokenVariant.DEFAULT, salt, abi.encode(p), initCalls);

        // After the failed creation, the predicted address has no code,
        // and a fresh creation with the same args succeeds.
        assertEq(predicted.code.length, 0, "predicted address should be empty after revert");
        address retried = _createDefault(caller, salt, p, new bytes[](0));
        assertEq(retried, predicted, "retry returns same deterministic address");
    }

    /*//////////////////////////////////////////////////////////////
                               SUCCESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies createToken returns the predicted address for the default variant
    /// @dev Address determinism: returned address must equal getTokenAddress(DEFAULT, decimals, sender, salt)
    function test_createToken_success_defaultMatchesPrediction(address caller, bytes32 salt, uint8 decimals) public {
        _assumeValidCaller(caller);
        decimals = uint8(bound(decimals, 2, 18));
        ITokenFactory.B20CreateParams memory p = _b20Params("Test", "TST", admin, decimals);
        address predicted = factory.getTokenAddress(ITokenFactory.TokenVariant.DEFAULT, decimals, caller, salt);
        address actual = _createDefault(caller, salt, p, new bytes[](0));
        assertEq(actual, predicted, "createToken address must match prediction");
    }

    /// @notice Verifies createToken returns the predicted address for the stablecoin variant
    /// @dev Address determinism: returned address must equal getTokenAddress(STABLECOIN, 6, sender, salt)
    function test_createToken_success_stablecoinMatchesPrediction(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        address predicted = factory.getTokenAddress(ITokenFactory.TokenVariant.STABLECOIN, 6, caller, salt);
        address actual = _createStablecoin(caller, salt, _stablecoinParams(), new bytes[](0));
        assertEq(actual, predicted, "createToken address must match prediction");
    }

    /// @notice Verifies createToken emits TokenCreated with the correct identity fields
    /// @dev Event integrity: token, variant, name, symbol, decimals must match the inputs
    function test_createToken_success_emitsTokenCreated(address caller, bytes32 salt, uint8 decimals) public {
        _assumeValidCaller(caller);
        decimals = uint8(bound(decimals, 2, 18));
        ITokenFactory.B20CreateParams memory p = _b20Params("MyToken", "MYT", admin, decimals);
        address predicted = factory.getTokenAddress(ITokenFactory.TokenVariant.DEFAULT, decimals, caller, salt);

        vm.expectEmit(true, true, false, true, address(factory));
        emit ITokenFactory.TokenCreated(predicted, ITokenFactory.TokenVariant.DEFAULT, "MyToken", "MYT", decimals, admin);
        _createDefault(caller, salt, p, new bytes[](0));
    }

    /// @notice Verifies createToken executes each entry in initCalls during the bootstrap window
    /// @dev The bootstrap-window auth bypass is bound to the call site (msg.sender == factory && !initialized),
    ///      not to RBAC. The factory is never granted any role on the token. We verify the bypass by passing
    ///      an initCall (grantRole) that would normally require DEFAULT_ADMIN_ROLE on the caller, and asserting
    ///      it took effect even though the factory has no role.
    function test_createToken_success_executesInitCalls(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        bytes[] memory initCalls = new bytes[](1);
        // Grant MINT_ROLE to bob during the bootstrap window. This would normally
        // require msg.sender to hold DEFAULT_ADMIN_ROLE, but the factory holds no
        // role; the bypass lets the call through.
        initCalls[0] = abi.encodeWithSelector(IB20.grantRole.selector, MINT_ROLE, bob);

        address token = _createDefault(caller, salt, _b20Params(), initCalls);
        assertTrue(MockB20(token).hasRole(MINT_ROLE, bob), "init call must have granted role");
        // Factory itself was never granted anything.
        assertFalse(
            MockB20(token).hasRole(DEFAULT_ADMIN_ROLE, address(factory)),
            "factory must not hold admin role"
        );
    }

    /// @notice Verifies TokenCreated fires before any state-change events from initCalls
    /// @dev Log ordering invariant per ITokenFactory natspec: "Emits TokenCreated once the token's identity
    ///      is sealed and BEFORE any initCalls are dispatched, so init-call effects appear strictly after
    ///      the creation event in the log order." Sanity check using vm.recordLogs.
    function test_createToken_success_emitsTokenCreatedBeforeInitCallEvents(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        // Use an init call that emits a single, distinctive event we can find: grantRole emits RoleGranted.
        bytes[] memory initCalls = new bytes[](1);
        initCalls[0] = abi.encodeWithSelector(IB20.grantRole.selector, MINT_ROLE, bob);

        vm.recordLogs();
        _createDefault(caller, salt, _b20Params(), initCalls);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find indices of TokenCreated and RoleGranted. Since the storage-direct-write
        // factory emits no RoleGranted at bootstrap, the only RoleGranted in the log
        // is the one from the init call.
        bytes32 tokenCreatedSig = ITokenFactory.TokenCreated.selector;
        bytes32 roleGrantedSig = IB20.RoleGranted.selector;
        int256 tokenCreatedAt = -1;
        int256 roleGrantedAt = -1;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == tokenCreatedSig && tokenCreatedAt < 0) tokenCreatedAt = int256(i);
            if (logs[i].topics[0] == roleGrantedSig && roleGrantedAt < 0) roleGrantedAt = int256(i);
        }
        assertGt(tokenCreatedAt, -1, "TokenCreated must be present in the log");
        assertGt(roleGrantedAt, -1, "RoleGranted must be present in the log (from initCall)");
        assertLt(tokenCreatedAt, roleGrantedAt, "TokenCreated must precede initCall-emitted events");
    }

    /// @notice Verifies the factory has no persistent privilege after createToken returns
    /// @dev The bootstrap-window bypass closes when closeBootstrap flips initialized = true. A direct
    ///      call from the factory address after creation must hit the standard auth path and revert.
    function test_createToken_success_factoryHasNoPersistentPrivilege(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        address token = _createDefault(caller, salt, _b20Params(), new bytes[](0));

        // Pranking the factory address into a direct mint should now revert with the standard
        // role check, because the bootstrap window is closed.
        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, address(factory), MINT_ROLE)
        );
        IB20(token).mint(bob, 1);
    }

    /// @notice Verifies createToken executes with admin == address(0) and grants no admin role
    /// @dev "Demonstrate no owner" path: factory accepts zero admin, token has no admin afterward
    ///      (no role grants, policy changes, or pauses ever possible). Replaces the prior
    ///      _revert_zeroAdmin_default stub now that the design explicitly allows this.
    function test_createToken_success_zeroAdminGrantsNoRole_default(address caller, bytes32 salt, uint8 decimals)
        public
    {
        _assumeValidCaller(caller);
        decimals = uint8(bound(decimals, 2, 18));
        ITokenFactory.B20CreateParams memory p = _b20Params("NoOwner", "NOWN", address(0), decimals);
        address token = _createDefault(caller, salt, p, new bytes[](0));

        // No admin was granted. Any admin-gated call from any account reverts.
        assertFalse(MockB20(token).hasRole(DEFAULT_ADMIN_ROLE, address(0)), "zero must not hold admin");
        assertFalse(MockB20(token).hasRole(DEFAULT_ADMIN_ROLE, caller), "caller must not hold admin");
        assertFalse(MockB20(token).hasRole(DEFAULT_ADMIN_ROLE, admin), "admin actor must not hold admin");
    }

    /// @notice Verifies stablecoin createToken executes with admin == address(0)
    /// @dev Same zero-admin success behavior on the stablecoin variant.
    function test_createToken_success_zeroAdminGrantsNoRole_stablecoin(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        ITokenFactory.B20StablecoinCreateParams memory p = _stablecoinParams("NoOwner USD", "NOUSD", address(0), "USD");
        address token = _createStablecoin(caller, salt, p, new bytes[](0));

        assertFalse(MockB20(token).hasRole(DEFAULT_ADMIN_ROLE, address(0)), "zero must not hold admin");
        assertFalse(MockB20(token).hasRole(DEFAULT_ADMIN_ROLE, caller), "caller must not hold admin");
        // The stablecoin still got its variant data: currency is set.
        assertEq(IB20Stablecoin(token).currency(), "USD", "stablecoin currency must still be set");
    }

    /// @notice Verifies the variant byte at address position [10] matches the created variant
    /// @dev Address schema: getTokenVariant(token) recovers the variant statelessly
    function test_createToken_success_encodesVariantByte(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);

        address defaultToken = _createDefault(caller, salt, _b20Params(), new bytes[](0));
        assertEq(
            uint256(factory.getTokenVariant(defaultToken)),
            uint256(ITokenFactory.TokenVariant.DEFAULT),
            "default variant byte mismatch"
        );

        address stablecoinToken = _createStablecoin(caller, salt, _stablecoinParams(), new bytes[](0));
        assertEq(
            uint256(factory.getTokenVariant(stablecoinToken)),
            uint256(ITokenFactory.TokenVariant.STABLECOIN),
            "stablecoin variant byte mismatch"
        );
    }

    /// @notice Verifies the decimals byte at address position [11] matches the created decimals
    /// @dev Address schema: decimals are encoded in the address for stateless decimals() lookup
    function test_createToken_success_encodesDecimalsByte(address caller, bytes32 salt, uint8 decimals) public {
        _assumeValidCaller(caller);
        decimals = uint8(bound(decimals, 2, 18));
        ITokenFactory.B20CreateParams memory p = _b20Params("Test", "TST", admin, decimals);
        address token = _createDefault(caller, salt, p, new bytes[](0));

        // Byte [11] of the address.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 byteAt11 = uint8(uint160(token) >> 64);
        assertEq(byteAt11, decimals, "address byte [11] must equal decimals");
        // And decimals() (which reads the byte) returns the same.
        assertEq(MockB20(token).decimals(), decimals, "decimals() must return encoded value");
    }
}
