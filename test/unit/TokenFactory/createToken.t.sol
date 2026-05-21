// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Stablecoin} from "src/interfaces/IB20Stablecoin.sol";
import {ITokenFactory} from "src/interfaces/ITokenFactory.sol";

import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";
import {MockB20Storage, MockB20StablecoinStorage} from "test/lib/mocks/MockB20Storage.sol";
import {TokenFactoryTest} from "test/lib/TokenFactoryTest.sol";

contract TokenFactoryCreateTokenTest is TokenFactoryTest {
    // Role identifiers are accessed as `MINT_ROLE` etc. — these are
    // compile-time constants on the contract type, so they don't require an
    // instantiated token (relevant during createToken setup where the token
    // doesn't yet exist).

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies createToken rejects raw variant bytes outside the TokenVariant enum range
    /// @dev TokenVariant has no "NONE" sentinel; typed callers cannot construct an out-of-range
    ///      value. The ABI decoder rejects out-of-range enum bytes with a Panic(0x21) before the
    ///      factory body's `else { revert InvalidVariant(); }` branch is ever reached, so the
    ///      observable behavior from a raw-bytes caller is a decode-time panic rather than a
    ///      typed factory revert.
    function test_createToken_revert_outOfRangeVariant(address caller, bytes32 salt, uint8 badVariant) public {
        _assumeValidCaller(caller);
        badVariant = uint8(bound(uint256(badVariant), uint256(type(ITokenFactory.TokenVariant).max) + 1, 255));
        vm.prank(caller);
        // ABI decoder panic for out-of-range enum value.
        vm.expectRevert();
        (bool ok,) = address(factory)
            .call(
                abi.encodeWithSelector(
                    ITokenFactory.createToken.selector, badVariant, salt, abi.encode(_b20Params()), new bytes[](0)
                )
            );
        ok; // silence unused warning; the revert is asserted via vm.expectRevert.
    }

    /// @notice Verifies createToken reverts for any unsupported params version byte (DEFAULT variant)
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

    /// @notice Verifies createToken reverts for any unsupported version byte on the STABLECOIN variant
    /// @dev Each variant arm has its own version check; this exercises the stablecoin arm's check
    ///      (the default-variant arm has a parallel test above).
    function test_createToken_revert_unsupportedVersion_stablecoin(address caller, uint8 badVersion, bytes32 salt)
        public
    {
        _assumeValidCaller(caller);
        vm.assume(badVersion != 1);
        ITokenFactory.B20StablecoinCreateParams memory p = _stablecoinParams();
        p.version = badVersion;
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ITokenFactory.UnsupportedVersion.selector, badVersion));
        factory.createToken(ITokenFactory.TokenVariant.STABLECOIN, salt, abi.encode(p), new bytes[](0));
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

    /// @notice Verifies the SECURITY variant currently reverts UnsupportedVersion(0)
    /// @dev Pins down the current "Security variant deferred to Katzman" behavior so it
    ///      can't silently start succeeding before the variant impl actually lands. Delete
    ///      this test when MockTokenFactory.createToken grows a real SECURITY arm.
    function test_createToken_revert_securityVariantDeferred(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);

        // Use a stablecoin params struct as a stand-in (the security struct doesn't matter:
        // the factory reverts before decoding because the variant arm short-circuits).
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ITokenFactory.UnsupportedVersion.selector, uint8(0)));
        factory.createToken(ITokenFactory.TokenVariant.SECURITY, salt, abi.encode(_stablecoinParams()), new bytes[](0));
    }

    /// @notice Verifies createToken reverts when (variant, sender, salt) collides
    /// @dev Deterministic-address uniqueness; checks TokenAlreadyExists(token) error
    function test_createToken_revert_tokenAlreadyExists(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        address first = _createDefault(caller, salt, _b20Params(), new bytes[](0));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ITokenFactory.TokenAlreadyExists.selector, first));
        factory.createToken(ITokenFactory.TokenVariant.DEFAULT, salt, abi.encode(_b20Params()), new bytes[](0));
    }

    /// @notice Verifies a failing initCall bubbles the underlying revert reason (regression test for L-01)
    /// @dev ITokenFactory.InitCallFailed NatSpec (L194-197) specifies two-tier error behavior:
    ///      bubble the underlying revert reason when the call returns one; wrap empty reverts
    ///      with InitCallFailed(index). `mint(address(0), 1)` reverts with `InvalidReceiver(0)`
    ///      inside the token, and the factory MUST surface that error verbatim, not swallow
    ///      it into `InitCallFailed(0)`. A buggy impl that discards revert data via `(bool ok,)`
    ///      surfaces the opaque wrapper instead.
    function test_createToken_revert_initCallFailed_bubblesRevertReason(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        bytes[] memory initCalls = new bytes[](1);
        initCalls[0] = abi.encodeWithSelector(IB20.mint.selector, address(0), uint256(1));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        factory.createToken(ITokenFactory.TokenVariant.DEFAULT, salt, abi.encode(_b20Params()), initCalls);
    }

    /// @notice Verifies an empty-revert initCall is wrapped as InitCallFailed(index) (L-01 complement)
    /// @dev The InitCallFailed wrapper is reserved for empty reverts where the underlying call
    ///      returned no data. We trigger this by calling a non-existent selector on the etched
    ///      token; MockB20 has no fallback, so Solidity's dispatcher reverts with empty data.
    ///      Without this carve-out the caller would receive a generic "" revert with no signal
    ///      about which init index failed.
    function test_createToken_revert_initCallFailed_wrapsEmptyRevert(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        bytes[] memory initCalls = new bytes[](1);
        // Non-existent selector "0xdeadbeef" -> MockB20 dispatcher rejects with empty data.
        initCalls[0] = abi.encodeWithSelector(bytes4(0xdeadbeef));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ITokenFactory.InitCallFailed.selector, uint256(0)));
        factory.createToken(ITokenFactory.TokenVariant.DEFAULT, salt, abi.encode(_b20Params()), initCalls);
    }

    /// @notice Verifies bubble + index for the SECOND init call (L-01 index correctness)
    /// @dev When the failing call is not at index 0, the bubble must still surface the
    ///      underlying error. A buggy impl that swallows revert data would mask not just
    ///      the error but also the implicit "which index" signal a developer needs to
    ///      debug a multi-call setup.
    function test_createToken_revert_initCallFailed_bubblesFromLaterIndex(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        bytes[] memory initCalls = new bytes[](2);
        // Index 0 is benign — set the supply cap to 100. Index 1 attempts to mint to
        // address(0) and reverts InvalidReceiver(0); we expect that error to bubble.
        initCalls[0] = abi.encodeWithSelector(IB20.updateSupplyCap.selector, uint256(100));
        initCalls[1] = abi.encodeWithSelector(IB20.mint.selector, address(0), uint256(1));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        factory.createToken(ITokenFactory.TokenVariant.DEFAULT, salt, abi.encode(_b20Params()), initCalls);
    }

    /// @notice Verifies a failing initCall leaves the deterministic address empty
    /// @dev Atomicity at the storage level: a revert in initCalls means no bytecode was
    ///      committed at the predicted address, so a subsequent createToken with the same
    ///      (variant, sender, salt) succeeds. After L-01 the revert reason is
    ///      bubbled (InvalidReceiver) rather than wrapped (InitCallFailed), but atomicity
    ///      is unchanged.
    function test_createToken_revert_initCallFailed_revertsWholeCreation(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        ITokenFactory.B20CreateParams memory p = _b20Params();
        address predicted = factory.getTokenAddress(ITokenFactory.TokenVariant.DEFAULT, caller, salt);

        bytes[] memory initCalls = new bytes[](1);
        initCalls[0] = abi.encodeWithSelector(IB20.mint.selector, address(0), uint256(1));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
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
    /// @dev Address determinism: returned address must equal getTokenAddress(DEFAULT, sender, salt)
    function test_createToken_success_defaultMatchesPrediction(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        ITokenFactory.B20CreateParams memory p = _b20Params("Test", "TST", admin);
        address predicted = factory.getTokenAddress(ITokenFactory.TokenVariant.DEFAULT, caller, salt);
        address actual = _createDefault(caller, salt, p, new bytes[](0));
        assertEq(actual, predicted, "createToken address must match prediction");
    }

    /// @notice Verifies createToken returns the predicted address for the stablecoin variant
    /// @dev Address determinism: returned address must equal getTokenAddress(STABLECOIN, sender, salt)
    function test_createToken_success_stablecoinMatchesPrediction(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        address predicted = factory.getTokenAddress(ITokenFactory.TokenVariant.STABLECOIN, caller, salt);
        address actual = _createStablecoin(caller, salt, _stablecoinParams(), new bytes[](0));
        assertEq(actual, predicted, "createToken address must match prediction");
    }

    /// @notice Verifies createToken emits TokenCreated with the correct identity fields
    /// @dev Event integrity: token, variant, name, symbol, decimals must match derived variant defaults.
    ///      Admin role assignment is announced via RoleGranted, not as a field on this event;
    ///      see test_createToken_success_emitsRoleGrantedForInitialAdmin for that.
    function test_createToken_success_emitsTokenCreated(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        ITokenFactory.B20CreateParams memory p = _b20Params("MyToken", "MYT", admin);
        address predicted = factory.getTokenAddress(ITokenFactory.TokenVariant.DEFAULT, caller, salt);

        vm.expectEmit(true, true, false, true, address(factory));
        emit ITokenFactory.TokenCreated(predicted, ITokenFactory.TokenVariant.DEFAULT, "MyToken", "MYT", 18);
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
        initCalls[0] = abi.encodeWithSelector(IB20.grantRole.selector, B20Constants.MINT_ROLE, bob);

        address token = _createDefault(caller, salt, _b20Params(), initCalls);
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
        uint256 packed = uint256(vm.load(token, MockB20Storage.adminCountAndInitializedSlot()));
        assertEq(uint256(MockB20Storage.adminCountFromPacked(packed)), 1, "adminCount must be 1 after bootstrap grant");
        assertTrue(MockB20Storage.initializedFromPacked(packed), "initialized bit must be set after bootstrap closes");
    }

    /// @notice Verifies TokenCreated fires before any state-change events from initCalls
    /// @dev Log ordering invariant per ITokenFactory natspec: "Emits TokenCreated once the token's identity
    ///      is sealed and BEFORE any initCalls are dispatched, so init-call effects appear strictly after
    ///      the creation event in the log order." Sanity check using vm.recordLogs.
    function test_createToken_success_emitsTokenCreatedBeforeInitCallEvents(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        // Use an init call that emits a single, distinctive event we can find: grantRole emits RoleGranted.
        bytes[] memory initCalls = new bytes[](1);
        initCalls[0] = abi.encodeWithSelector(IB20.grantRole.selector, B20Constants.MINT_ROLE, bob);

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

        // Paired slot assertion: the bootstrap window's gate is the
        // `initialized` byte in the packed slot. Confirming it's set
        // proves the factory's privileged path is closed at the storage
        // level (the surface-level role revert below is the consequence).
        assertTrue(
            MockB20Storage.initializedFromPacked(
                uint256(vm.load(token, MockB20Storage.adminCountAndInitializedSlot()))
            ),
            "initialized bit must be set after createToken returns"
        );

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

    /// @notice Verifies createToken executes with admin == address(0) and grants no admin role
    /// @dev "Demonstrate no owner" path: factory accepts zero admin, token has no admin afterward
    ///      (no role grants, policy changes, or pauses ever possible). Replaces the prior
    ///      _revert_zeroAdmin_default stub now that the design explicitly allows this.
    function test_createToken_success_zeroAdminGrantsNoRole_default(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        ITokenFactory.B20CreateParams memory p = _b20Params("NoOwner", "NOWN", address(0));
        address token = _createDefault(caller, salt, p, new bytes[](0));

        // No admin was granted. Any admin-gated call from any account reverts.
        assertFalse(MockB20(token).hasRole(B20Constants.DEFAULT_ADMIN_ROLE, address(0)), "zero must not hold admin");
        assertFalse(MockB20(token).hasRole(B20Constants.DEFAULT_ADMIN_ROLE, caller), "caller must not hold admin");
        assertFalse(MockB20(token).hasRole(B20Constants.DEFAULT_ADMIN_ROLE, admin), "admin actor must not hold admin");

        // Paired slot assertion: packed adminCount lane is 0 (no
        // bootstrap grant happened) but the initialized bit is still
        // set (the factory closed the bootstrap window after returning).
        uint256 packed = uint256(vm.load(token, MockB20Storage.adminCountAndInitializedSlot()));
        assertEq(uint256(MockB20Storage.adminCountFromPacked(packed)), 0, "adminCount must be 0 on zero-admin path");
        assertTrue(MockB20Storage.initializedFromPacked(packed), "initialized must still be set on zero-admin path");
    }

    /// @notice Verifies stablecoin createToken executes with admin == address(0)
    /// @dev Same zero-admin success behavior on the stablecoin variant.
    ///      Paired slot assertions cross-check both the base namespace
    ///      (adminCount=0, initialized=true) and the variant namespace
    ///      (currency slot holds the short-string encoding of "USD").
    function test_createToken_success_zeroAdminGrantsNoRole_stablecoin(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        ITokenFactory.B20StablecoinCreateParams memory p = _stablecoinParams("NoOwner USD", "NOUSD", address(0), "USD");
        address token = _createStablecoin(caller, salt, p, new bytes[](0));

        assertFalse(MockB20(token).hasRole(B20Constants.DEFAULT_ADMIN_ROLE, address(0)), "zero must not hold admin");
        assertFalse(MockB20(token).hasRole(B20Constants.DEFAULT_ADMIN_ROLE, caller), "caller must not hold admin");
        // The stablecoin still got its variant data: currency is set.
        assertEq(IB20Stablecoin(token).currency(), "USD", "stablecoin currency must still be set");

        uint256 packed = uint256(vm.load(token, MockB20Storage.adminCountAndInitializedSlot()));
        assertEq(uint256(MockB20Storage.adminCountFromPacked(packed)), 0, "adminCount must be 0 on zero-admin path");
        assertTrue(MockB20Storage.initializedFromPacked(packed), "initialized must still be set on zero-admin path");
        assertEq(
            vm.load(token, MockB20StablecoinStorage.currencySlot()),
            _expectedStringFieldSlot("USD"),
            "stablecoin currency slot must hold the short-string encoding of \"USD\""
        );
    }

    /// @notice Verifies the variant byte at address position [10] matches the created variant
    /// @dev Address schema: byte [10] of the token address IS the variant; readable
    ///      statelessly off the address with no factory lookup.
    function test_createToken_success_encodesVariantByte(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);

        address defaultToken = _createDefault(caller, salt, _b20Params(), new bytes[](0));
        assertEq(
            uint256(uint8(uint160(defaultToken) >> 72)),
            uint256(ITokenFactory.TokenVariant.DEFAULT),
            "default variant byte mismatch"
        );

        address stablecoinToken = _createStablecoin(caller, salt, _stablecoinParams(), new bytes[](0));
        assertEq(
            uint256(uint8(uint160(stablecoinToken) >> 72)),
            uint256(ITokenFactory.TokenVariant.STABLECOIN),
            "stablecoin variant byte mismatch"
        );
    }

    /// @notice Verifies createToken correctly stores name and symbol strings >= 32 bytes
    /// @dev Solidity's storage layout switches encoding at length 32 (short vs long string).
    ///      The factory's _writeString handles both paths via vm.store; this test exercises
    ///      the long-string path explicitly. Short-string path is covered by every other
    ///      success test (default name "Test", symbol "TST" are both < 32 bytes).
    function test_createToken_success_writesLongStrings(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        // Both strings are 40 bytes -> exercises the long-string storage encoding.
        string memory longName = "A token name that is forty bytes long!!!";
        string memory longSymbol = "ASYMBOLALSODELIBERATELYFORTYBYTES.....!!";
        assertEq(bytes(longName).length, 40, "test setup: longName must be 40 bytes");
        assertEq(bytes(longSymbol).length, 40, "test setup: longSymbol must be 40 bytes");

        ITokenFactory.B20CreateParams memory p = _b20Params(longName, longSymbol, admin);
        address tokenAddr = _createDefault(caller, salt, p, new bytes[](0));

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
    function test_createToken_success_writesStringsAtEncodingBoundary(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        string memory name32 = "abcdefghijklmnopqrstuvwxyzABCDEF";
        string memory symbol33 = "abcdefghijklmnopqrstuvwxyzABCDEFG";
        assertEq(bytes(name32).length, 32, "test setup: name must be exactly 32 bytes");
        assertEq(bytes(symbol33).length, 33, "test setup: symbol must be exactly 33 bytes");

        ITokenFactory.B20CreateParams memory p = _b20Params(name32, symbol33, admin);
        address tokenAddr = _createDefault(caller, salt, p, new bytes[](0));

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
    function test_getTokenAddress_pinsDownAbiEncoding(address sender, bytes32 salt) public view {
        bytes9 expectedTail = bytes9(keccak256(abi.encode(sender, salt)));
        uint160 expectedAddr = (uint160(0xB2) << 152) | (uint160(uint8(ITokenFactory.TokenVariant.DEFAULT)) << 72)
            | uint160(uint72(expectedTail));

        address actual = factory.getTokenAddress(ITokenFactory.TokenVariant.DEFAULT, sender, salt);
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
    function test_createToken_success_emptyName_roundTripsAsEmpty(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        ITokenFactory.B20CreateParams memory p = _b20Params("", "ETH", admin);
        address tokenAddr = _createDefault(caller, salt, p, new bytes[](0));

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
    function test_createToken_success_emptySymbol_roundTripsAsEmpty(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        ITokenFactory.B20CreateParams memory p = _b20Params("Token", "", admin);
        address tokenAddr = _createDefault(caller, salt, p, new bytes[](0));

        assertEq(MockB20(tokenAddr).symbol(), "", "empty symbol must round-trip as empty");
        assertEq(
            vm.load(tokenAddr, MockB20Storage.symbolSlot()), bytes32(0), "empty symbol field slot must be all-zero"
        );
    }

    /// @notice Verifies both empty name and empty symbol round-trip correctly (regression test for L-04)
    /// @dev Belt-and-suspenders: both strings empty is the most degenerate case and would be
    ///      most likely to surface memory-layout assumptions in the writer.
    function test_createToken_success_bothEmpty_roundTripAsEmpty(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        ITokenFactory.B20CreateParams memory p = _b20Params("", "", admin);
        address tokenAddr = _createDefault(caller, salt, p, new bytes[](0));

        assertEq(MockB20(tokenAddr).name(), "", "empty name must round-trip as empty");
        assertEq(MockB20(tokenAddr).symbol(), "", "empty symbol must round-trip as empty");
        assertEq(vm.load(tokenAddr, MockB20Storage.nameSlot()), bytes32(0), "empty name field slot must be all-zero");
        assertEq(
            vm.load(tokenAddr, MockB20Storage.symbolSlot()), bytes32(0), "empty symbol field slot must be all-zero"
        );
    }

    /// @notice Verifies decimals are fixed by variant and not encoded in address bytes
    /// @dev Default tokens return 18, stablecoin tokens return 6.
    function test_createToken_success_decimalsFixedByVariant(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        address defaultToken = _createDefault(caller, salt, _b20Params("Test", "TST", admin), new bytes[](0));
        address stablecoinToken = _createStablecoin(caller, salt, _stablecoinParams(), new bytes[](0));

        assertEq(MockB20(defaultToken).decimals(), 18, "default decimals must be fixed at 18");
        assertEq(MockB20(stablecoinToken).decimals(), 6, "stablecoin decimals must be fixed at 6");
    }
}
