// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @notice Self-tests for `MockB20Storage`'s slot-derivation and
///         packed-slot codec helpers. Each test sets a known value via
///         the IB20 surface, reads the helper-computed slot via
///         `vm.load`, and asserts the slot reflects the same value the
///         surface returns. Both single-field slots (`adminCount`,
///         `initialized`) and packed-lane slots (`transferPolicyIds`,
///         `mintPolicyIds`) get coverage here.
///
/// @dev These tests are the canonical reference for what slot each
///      logical field lives at and how packed slots are decoded. The
///      Rust precompile impl uses the same helper outputs as its
///      ground truth.
contract MockB20SlotHelpersTest is B20Test {
    using MockB20Storage for uint256;

    /// @notice Verifies `balanceSlot(account)` locates the slot the
    ///         token's accounting writes to in `_mint` / `_transfer`.
    /// @dev Single-account read-after-write: mint a known amount, then
    ///      assert `vm.load(token, balanceSlot(account)) == amount`.
    function test_balanceSlot_success_locatesBalance(address account, uint256 amount) public {
        _assumeValidActor(account);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(account, amount);

        assertEq(token.balanceOf(account), amount, "precondition: balanceOf must match");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(account))),
            amount,
            "balanceSlot must locate the slot holding balanceOf(account)"
        );
    }

    /// @notice Verifies `balanceSlot` produces disjoint slots for distinct accounts.
    /// @dev Two mints to different accounts must not alias.
    function test_balanceSlot_success_disjointAcrossAccounts(address a, address b, uint256 amountA, uint256 amountB)
        public
    {
        _assumeValidActor(a);
        _assumeValidActor(b);
        vm.assume(a != b);
        // Bound the cumulative mint to the uint128.max supply ceiling so the
        // second mint doesn't trip SupplyCapExceeded.
        amountA = bound(amountA, 0, B20Constants.MAX_SUPPLY_CAP);
        amountB = bound(amountB, 0, B20Constants.MAX_SUPPLY_CAP - amountA);

        _mint(a, amountA);
        _mint(b, amountB);

        assertEq(uint256(vm.load(address(token), MockB20Storage.balanceSlot(a))), amountA, "a balance slot");
        assertEq(uint256(vm.load(address(token), MockB20Storage.balanceSlot(b))), amountB, "b balance slot");
        assertTrue(
            MockB20Storage.balanceSlot(a) != MockB20Storage.balanceSlot(b),
            "balanceSlot must differ for distinct accounts"
        );
    }

    /// @notice Verifies `allowanceSlot(owner, spender)` locates the slot
    ///         `approve` writes to.
    /// @dev Read-after-write: approve a fuzzed amount, then `vm.load`
    ///      the helper's slot and compare against `allowance`.
    function test_allowanceSlot_success_locatesAllowance(address owner, address spender, uint256 amount) public {
        _assumeValidActor(owner);
        _assumeValidActor(spender);

        vm.prank(owner);
        token.approve(spender, amount);

        assertEq(token.allowance(owner, spender), amount, "precondition: allowance must match");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(owner, spender))),
            amount,
            "allowanceSlot must locate the slot holding allowance(owner, spender)"
        );
    }

    /// @notice Verifies `allowanceSlot` is directional: swapping owner
    ///         and spender produces a disjoint slot.
    /// @dev allowance[owner][spender] != allowance[spender][owner] when
    ///      owner != spender; the helper must respect that ordering.
    function test_allowanceSlot_success_directionallySensitive(address owner, address spender) public pure {
        vm.assume(owner != spender);

        assertTrue(
            MockB20Storage.allowanceSlot(owner, spender) != MockB20Storage.allowanceSlot(spender, owner),
            "allowanceSlot(o, s) must differ from allowanceSlot(s, o)"
        );
    }

    /// @notice Verifies `roleMembershipSlot(role, account)` locates the
    ///         bool flag `grantRole` sets.
    /// @dev After granting, slot value == bytes32(uint256(1)).
    function test_roleMembershipSlot_success_locatesMembershipBit(bytes32 role, address account) public {
        // Bootstrap admin grant of DEFAULT_ADMIN_ROLE to `admin` already wrote
        // the slot; skip that combo to keep this test focused on a NEW grant.
        vm.assume(!(role == B20Constants.DEFAULT_ADMIN_ROLE && account == admin));

        _grantRole(role, account);

        assertTrue(token.hasRole(role, account), "precondition: role must be held");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.roleMembershipSlot(role, account))),
            uint256(1),
            "roleMembershipSlot must locate the bool flag set by grantRole"
        );
    }

    /// @notice Verifies `roleAdminSlot(role)` locates the slot
    ///         `setRoleAdmin` writes to.
    /// @dev Read-after-write: set a non-zero admin role, then `vm.load`
    ///      and compare against `getRoleAdmin`.
    function test_roleAdminSlot_success_locatesAdminRole(bytes32 role, bytes32 adminRole) public {
        // Skip combos where getRoleAdmin is already the target (default 0).
        vm.assume(adminRole != bytes32(0));

        vm.prank(admin);
        token.setRoleAdmin(role, adminRole);

        assertEq(token.getRoleAdmin(role), adminRole, "precondition: role admin must match");
        assertEq(
            vm.load(address(token), MockB20Storage.roleAdminSlot(role)),
            adminRole,
            "roleAdminSlot must locate the slot holding getRoleAdmin(role)"
        );
    }

    /// @notice Verifies `nonceSlot(owner)` locates the slot `permit` increments.
    /// @dev A fresh account has nonce 0; the slot must read 0 too.
    function test_nonceSlot_success_locatesNonceInitiallyZero(address owner) public {
        _assumeValidActor(owner);

        assertEq(token.nonces(owner), 0, "precondition: fresh nonce is zero");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.nonceSlot(owner))),
            uint256(0),
            "nonceSlot must locate the zero-initialized nonce"
        );
    }

    /// @notice Verifies `totalSupplySlot()` returns the slot `_mint` updates.
    /// @dev Read-after-write: mint to alice, then `vm.load` the helper.
    function test_totalSupplySlot_success_locatesTotalSupply(uint256 amount) public {
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(alice, amount);

        assertEq(token.totalSupply(), amount, "precondition: totalSupply must match");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.totalSupplySlot())),
            amount,
            "totalSupplySlot must locate totalSupply"
        );
    }

    /// @notice Verifies `pausedVectorsSlot()` returns the slot pause flips bits in.
    /// @dev After pausing TRANSFER, bit 0 of the vectors slot is set.
    function test_pausedVectorsSlot_success_locatesPauseBit() public {
        _pause(IB20.PausableFeature.TRANSFER);

        uint256 vectors = uint256(vm.load(address(token), MockB20Storage.pausedVectorsSlot()));
        assertEq(vectors & 1, 1, "TRANSFER bit (bit 0) must be set after pause");
    }

    /// @notice Verifies `supplyCapSlot()` returns the slot updateSupplyCap writes to.
    /// @dev Default-token bootstrap sets supplyCap = B20Constants.MAX_SUPPLY_CAP; we lower it
    ///      and re-read both via surface and slot.
    function test_supplyCapSlot_success_locatesSupplyCap(uint256 cap) public {
        // Lower the cap to a value that won't violate the
        // "cannot lower below totalSupply" invariant (totalSupply == 0)
        // and stays within the uint128.max ceiling.
        cap = bound(cap, 0, B20Constants.MAX_SUPPLY_CAP - 1);

        _grantRole(B20Constants.MINT_ROLE, admin);
        vm.prank(admin);
        token.updateSupplyCap(cap);

        assertEq(token.supplyCap(), cap, "precondition: supplyCap must match");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.supplyCapSlot())), cap, "supplyCapSlot must locate supplyCap"
        );
    }

    /// @notice Verifies `transferPolicyIdsSlot()` and the lane decoders
    ///         locate the TRANSFER_SENDER lane.
    /// @dev `_setPolicy(TRANSFER_SENDER, ALWAYS_BLOCK_ID)` writes the
    ///      low 64 bits of the packed slot; the helper reads the same lane.
    function test_transferPolicyIdsSlot_success_decodesSenderLane() public {
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        uint256 packed = uint256(vm.load(address(token), MockB20Storage.transferPolicyIdsSlot()));
        assertEq(
            MockB20Storage.transferSenderPolicyId(packed),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "transferSenderPolicyId lane must reflect the policy write"
        );
        assertEq(
            MockB20Storage.transferReceiverPolicyId(packed),
            0,
            "TRANSFER_RECEIVER lane must remain at its default (ALWAYS_ALLOW = 0)"
        );
        assertEq(
            MockB20Storage.transferExecutorPolicyId(packed), 0, "TRANSFER_EXECUTOR lane must remain at its default"
        );
    }

    /// @notice Verifies `mintPolicyIdsSlot()` locates the MINT_RECEIVER lane.
    /// @dev Write to MINT_RECEIVER via `updatePolicy`; lane decoder reads back.
    function test_mintPolicyIdsSlot_success_decodesReceiverLane() public {
        _setPolicy(B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        uint256 packed = uint256(vm.load(address(token), MockB20Storage.mintPolicyIdsSlot()));
        assertEq(
            MockB20Storage.mintReceiverPolicyId(packed),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "mintReceiverPolicyId lane must reflect the policy write"
        );
    }

    /// @notice Verifies `packTransferPolicyIds` is the inverse of the lane decoders.
    /// @dev Round-trip: pack three uint64s, decode, expect the inputs back.
    function test_packTransferPolicyIds_success_roundtrips(uint64 senderId, uint64 receiverId, uint64 executorId)
        public
        pure
    {
        uint256 packed = MockB20Storage.packTransferPolicyIds(senderId, receiverId, executorId);
        assertEq(MockB20Storage.transferSenderPolicyId(packed), senderId);
        assertEq(MockB20Storage.transferReceiverPolicyId(packed), receiverId);
        assertEq(MockB20Storage.transferExecutorPolicyId(packed), executorId);
    }

    /// @notice Verifies `packMintPolicyIds` is the inverse of `mintReceiverPolicyId`.
    function test_packMintPolicyIds_success_roundtrips(uint64 receiverId) public pure {
        assertEq(MockB20Storage.mintReceiverPolicyId(MockB20Storage.packMintPolicyIds(receiverId)), receiverId);
    }

    /// @notice Verifies `adminCountSlot()` locates the slot factory
    ///         bootstrap and `_grantRole(DEFAULT_ADMIN_ROLE, ...)` write to.
    /// @dev Factory bootstrap grants DEFAULT_ADMIN_ROLE to `admin`, so
    ///      the slot must read exactly `1` after setup. `adminCount`
    ///      lives alone in its own slot (no packing with `initialized`
    ///      anymore), so the raw slot value IS the count.
    function test_adminCountSlot_success_decodesAfterBootstrap() public view {
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.adminCountSlot())),
            1,
            "adminCount slot must read 1 after bootstrap"
        );
    }

    /// @notice Verifies `initializedSlot()` locates the slot the factory
    ///         flips at the end of createToken to close the bootstrap window.
    /// @dev `initialized` lives alone in its own slot at the end of the
    ///      layout, so the raw word IS the flag's value (1 = true, 0 = false).
    ///
    ///      Mock-world-only: the Rust precompile impl marks initialization
    ///      via a 0xef bytecode stub at the token address rather than a
    ///      storage slot (see `B20FactoryTest._assertInitialized`), so the
    ///      slot pinned here is a Solidity-mock invariant with no
    ///      counterpart on the live precompile. Skip under LIVE_PRECOMPILES.
    function test_initializedSlot_success_decodesAfterBootstrap() public {
        vm.skip(livePrecompiles);
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.initializedSlot())),
            1,
            "initialized slot must read 1 after bootstrap (window closed)"
        );
    }

    /// @notice Verifies `adminCountSlot()` and `initializedSlot()` are disjoint.
    /// @dev Regression: under the old packed layout these aliased to slot 8;
    ///      after the move they must land at distinct absolute slots.
    ///
    ///      Mock-world-only: same rationale as
    ///      `test_initializedSlot_success_decodesAfterBootstrap`. The Rust
    ///      layout doesn't have an `initialized` slot at all, so disjointness
    ///      from `adminCountSlot` is a Solidity-mock invariant.
    function test_adminCountSlot_success_disjointFromInitializedSlot() public {
        vm.skip(livePrecompiles);
        assertTrue(
            MockB20Storage.adminCountSlot() != MockB20Storage.initializedSlot(),
            "adminCount and initialized must live in disjoint slots"
        );
    }

    /// @notice Verifies `nameSlot()` returns a slot whose value encodes
    ///         the short-string form of the token's name.
    /// @dev Short-string encoding (length < 32): the slot holds
    ///      `bytes || (length * 2)` with the bytes in the high portion
    ///      and `length * 2` in the low byte. We assert the low byte
    ///      against `bytes(name).length * 2` for the bootstrap-default name.
    function test_nameSlot_success_holdsShortStringEncoding() public view {
        bytes32 raw = vm.load(address(token), MockB20Storage.nameSlot());
        // Bootstrap-default name from MockB20Factory: empty string until
        // updateName is called, so encoding is the all-zero slot. We
        // also check the encoding is well-formed for whatever name is
        // currently set.
        bytes memory nameBytes = bytes(token.name());
        if (nameBytes.length == 0) {
            assertEq(raw, bytes32(0), "empty name slot must be zero");
        } else if (nameBytes.length < 32) {
            // Low byte == length * 2; this is enough to confirm the slot
            // is the SHORT-STRING field slot (and not the long-string
            // marker slot, which would have low bit set).
            assertEq(uint256(raw) & 0xff, nameBytes.length * 2, "low byte must equal length * 2");
        }
    }
}
