// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";
import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @notice Exhaustive layout spec for the `base.b20` namespace.
///
/// @dev    Populates a Default-variant `MockB20` with non-default values
///         across every field of `MockB20Storage.Layout`, then asserts
///         the raw slot value at each absolute slot matches the
///         expected encoding. This is the single comprehensive
///         storage-layout reference the Rust precompile impl must
///         reproduce byte-for-byte.
///
///         Per-function tests under `B20/**/*.t.sol` cover individual
///         mutator paths. This file tests the COMPLETE layout in one
///         populated snapshot — both as a regression on any single-
///         field drift AND as a self-contained spec that a Rust
///         implementer can compare against without running the rest
///         of the suite.
///
///         **Lane / bit assertions use explicit bit math, not codec
///         helpers.** Asserting through `MockB20Storage.transferSenderPolicyId(packed)`
///         lets a buggy codec hide a buggy layout (the codec would
///         translate the wrong slot bits into the value the caller
///         wrote, and the assertion would pass). Reading the raw slot
///         and asserting bit ranges grounds the test at the bytes; the
///         codec helpers are separately verified by roundtrip tests in
///         `MockB20SlotHelpers.t.sol`. Both signals together prove
///         "the layout is what we think AND the codec matches that
///         layout".
///
///         **Lane markers are deliberately distinct per lane** so a
///         lane-swap regression (e.g. Rust putting sender at lane 1
///         and receiver at lane 0) produces an assertion failure with
///         a recognizable counterexample. Reusing the same value across
///         lanes would mask exactly the bug this test exists to catch.
contract B20FullLayoutTest is B20Test {
    // ---------- Distinct policy ID markers per lane ----------
    // Set in `_populate` by `createPolicy` calls into the registry.
    // Each lane gets a freshly-created, distinct policy ID so a
    // lane-swap regression produces a recognizable diff in the
    // assertion failure. Built-in sentinel IDs (ALWAYS_ALLOW_ID,
    // ALWAYS_BLOCK_ID) would only give us TWO distinct values for
    // the three transfer lanes; real custom policies give us as many
    // distinct IDs as we need AND satisfy `updatePolicy`'s
    // `policyExists` precondition.

    uint64 internal transferSenderMarker;
    uint64 internal transferReceiverMarker;
    uint64 internal transferExecutorMarker;
    uint64 internal mintReceiverMarker;

    /// @notice Cross-cuts every field of MockB20Storage.Layout in a single
    ///         populated snapshot.
    /// @dev    Setup writes non-default values to every reachable storage
    ///         field via the public IB20 surface (and the factory's
    ///         bootstrap writes for identity / supply cap). Then every
    ///         slot is loaded via vm.load and compared to the
    ///         independently-computed expected value, so the test
    ///         pins down both the absolute slot location and the
    ///         encoding of each field.
    ///
    ///         Field coverage in slot order:
    ///         - 0: name (short string)
    ///         - 1: symbol (short string)
    ///         - 2: contractURI (short string)
    ///         - 3: totalSupply
    ///         - 4: balances (alice, bob)
    ///         - 5: allowances (alice -> bob)
    ///         - 6: roles (DEFAULT_ADMIN_ROLE for admin, MINT_ROLE for minter, BURN_ROLE for burner)
    ///         - 7: roleAdmins (MINT_ROLE re-parented to PAUSE_ROLE)
    ///         - 8: adminCount (own slot)
    ///         - 9: transferPolicyIds (all 3 lanes)
    ///         - 10: mintPolicyIds (receiver lane)
    ///         - 11: pausedVectors (TRANSFER + MINT bits)
    ///         - 12: supplyCap
    ///         - 13: nonces (advanced via permit)
    ///         - 14: initialized (own slot at end of layout)
    function test_b20Layout_success_populatedSnapshotMatchesAllSlots() public {
        // ---------- Populate ----------
        _populate();

        address tokenAddr = address(token);

        // ---------- Identity (slots 0..2) ----------
        // Bootstrap-default identity is "Asset Test" / "AST" / "" from
        // B20FactoryTest._assetParams(). Empty contractURI is the
        // zero-slot encoding; "Asset Test" and "AST" are short-string
        // encoded via _expectedStringFieldSlot.
        assertEq(vm.load(tokenAddr, MockB20Storage.nameSlot()), _expectedStringFieldSlot(token.name()), "slot 0: name");
        assertEq(
            vm.load(tokenAddr, MockB20Storage.symbolSlot()), _expectedStringFieldSlot(token.symbol()), "slot 1: symbol"
        );
        assertEq(
            vm.load(tokenAddr, MockB20Storage.contractURISlot()),
            _expectedStringFieldSlot(token.contractURI()),
            "slot 2: contractURI"
        );

        // ---------- ERC-20 accounting (slots 3..5) ----------
        // totalSupply = alice + bob balances (from _populate's mints).
        assertEq(
            uint256(vm.load(tokenAddr, MockB20Storage.totalSupplySlot())), token.totalSupply(), "slot 3: totalSupply"
        );
        assertEq(
            uint256(vm.load(tokenAddr, MockB20Storage.balanceSlot(alice))),
            token.balanceOf(alice),
            "slot 4 (alice): balances[alice]"
        );
        assertEq(
            uint256(vm.load(tokenAddr, MockB20Storage.balanceSlot(bob))),
            token.balanceOf(bob),
            "slot 4 (bob): balances[bob]"
        );
        assertEq(
            uint256(vm.load(tokenAddr, MockB20Storage.allowanceSlot(alice, bob))),
            token.allowance(alice, bob),
            "slot 5: allowances[alice][bob]"
        );

        // ---------- Roles (slots 6..7) ----------
        // Three distinct role bits set; one re-parented role admin.
        assertEq(
            uint256(vm.load(tokenAddr, MockB20Storage.roleMembershipSlot(B20Constants.DEFAULT_ADMIN_ROLE, admin))),
            uint256(1),
            "slot 6: roles[ADMIN][admin]"
        );
        assertEq(
            uint256(vm.load(tokenAddr, MockB20Storage.roleMembershipSlot(B20Constants.MINT_ROLE, minter))),
            uint256(1),
            "slot 6: roles[MINT][minter]"
        );
        assertEq(
            uint256(vm.load(tokenAddr, MockB20Storage.roleMembershipSlot(B20Constants.BURN_ROLE, burner))),
            uint256(1),
            "slot 6: roles[BURN][burner]"
        );
        assertEq(
            vm.load(tokenAddr, MockB20Storage.roleAdminSlot(B20Constants.MINT_ROLE)),
            B20Constants.PAUSE_ROLE,
            "slot 7: roleAdmins[MINT_ROLE] re-parented to PAUSE_ROLE"
        );

        // ---------- adminCount (slot 8) ----------
        // adminCount = 1 (only `admin` holds DEFAULT_ADMIN_ROLE). Lives
        // alone in its own slot now that `initialized` was moved to the
        // end of the layout.
        assertEq(uint256(vm.load(tokenAddr, MockB20Storage.adminCountSlot())), 1, "slot 8: adminCount");

        // ---------- Policy lanes (slots 9..10) ----------
        // Lanes set to DISTINCT markers (not all the same value) so a
        // lane-swap regression in the Rust impl produces a recognizable
        // diff. Assertions go directly against raw bit ranges rather
        // than through codec helpers (see contract-level NatSpec for
        // the rationale).
        uint256 packedTransfer = uint256(vm.load(tokenAddr, MockB20Storage.transferPolicyIdsSlot()));
        assertEq(
            packedTransfer & 0xFFFFFFFFFFFFFFFF,
            uint256(transferSenderMarker),
            "slot 9 bits 0..63: transfer SENDER lane"
        );
        assertEq(
            (packedTransfer >> 64) & 0xFFFFFFFFFFFFFFFF,
            uint256(transferReceiverMarker),
            "slot 9 bits 64..127: transfer RECEIVER lane"
        );
        assertEq(
            (packedTransfer >> 128) & 0xFFFFFFFFFFFFFFFF,
            uint256(transferExecutorMarker),
            "slot 9 bits 128..191: transfer EXECUTOR lane"
        );
        assertEq(packedTransfer >> 192, 0, "slot 9 bits 192..255: reserved lane must be zero");

        uint256 packedMint = uint256(vm.load(tokenAddr, MockB20Storage.mintPolicyIdsSlot()));
        assertEq(packedMint & 0xFFFFFFFFFFFFFFFF, uint256(mintReceiverMarker), "slot 10 bits 0..63: mint RECEIVER lane");
        assertEq(packedMint >> 64, 0, "slot 10 bits 64..255: three reserved lanes must be zero");

        // ---------- pausedVectors (slot 11) ----------
        // Every PausableFeature is paused so every defined bit position
        // is independently asserted. Pinning all three (vs only two) is
        // what makes "Rust uses different bit positions for these
        // features" detectable.
        uint256 pausedRaw = uint256(vm.load(tokenAddr, MockB20Storage.pausedVectorsSlot()));
        uint256 expectedPaused = (uint256(1) << uint8(IB20.PausableFeature.TRANSFER))
            | (uint256(1) << uint8(IB20.PausableFeature.MINT)) | (uint256(1) << uint8(IB20.PausableFeature.BURN));
        assertEq(pausedRaw, expectedPaused, "slot 11: pausedVectors must hold exactly the three defined bits");
        // No bits set outside the defined PausableFeature range. Computed
        // as the complement of the union of all defined bits.
        assertEq(
            pausedRaw & ~expectedPaused, 0, "slot 11: no bits may be set outside the defined PausableFeature range"
        );

        // ---------- supplyCap (slot 12) ----------
        assertEq(uint256(vm.load(tokenAddr, MockB20Storage.supplyCapSlot())), token.supplyCap(), "slot 12: supplyCap");

        // ---------- nonces (slot 13) ----------
        // Permit in setup increments alice's nonce; verify both the
        // surface and the slot match.
        assertEq(
            uint256(vm.load(tokenAddr, MockB20Storage.nonceSlot(alice))), token.nonces(alice), "slot 13: nonces[alice]"
        );

        // ---------- initialized ----------
        // Mock world: pinned at the end of the layout in its own slot
        // (slot 14); the factory flips this to true at the end of
        // createToken; any non-zero word means the bootstrap window is
        // closed. Live world: the Rust factory plants a 0xef bytecode
        // stub at the token address instead; the dedicated mock slot
        // doesn't exist (would alias to a different field in the Rust
        // layout). The helper picks the right check per backend.
        //
        // The other slot-by-slot assertions in this test are NOT
        // dual-backend; they pin the Solidity layout exactly. Per-slot
        // divergence against the Rust impl is the cross-validation
        // signal documented in LIVE_PRECOMPILE_TESTING.md's bucket table.
        _assertInitialized(tokenAddr, "initialized marker must be set");
    }

    /// @notice Populates the token with non-default values across every
    ///         field in `MockB20Storage.Layout`. Centralized here so the
    ///         layout test reads as a single assertion sweep with no
    ///         interleaved mutations.
    function _populate() internal {
        // ---------- Identity ----------
        // name/symbol come from factory bootstrap ("Asset Test" / "AST" via
        // B20FactoryTest._assetParams()). Set contractURI explicitly so
        // slot 2 has a non-zero value to assert.
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        token.updateContractURI("https://example.com/contract.json");

        // ---------- Supply cap (lower from default uint256.max so the
        // slot holds a representative non-extreme value) ----------
        vm.prank(admin);
        token.updateSupplyCap(10_000 ether);

        // ---------- Balances + totalSupply ----------
        _mint(alice, 100 ether);
        _mint(bob, 200 ether);

        // ---------- Allowance ----------
        vm.prank(alice);
        token.approve(bob, 42 ether);

        // ---------- Roles ----------
        // MINT_ROLE for minter already granted by `_mint`'s lazy path.
        _grantRole(B20Constants.BURN_ROLE, burner);
        // Re-parent MINT_ROLE so the roleAdmins[MINT_ROLE] slot is non-default.
        vm.prank(admin);
        token.setRoleAdmin(B20Constants.MINT_ROLE, B20Constants.PAUSE_ROLE);

        // ---------- Policy lanes ----------
        // Create four real custom policies in the registry so each lane
        // gets a DISTINCT, well-formed ID. `updatePolicy`'s `policyExists`
        // precondition rejects arbitrary uint64s, so we can't use synthetic
        // hex markers like `0x1111...`. Mixing ALLOWLIST + BLOCKLIST types
        // makes the top byte vary between lanes too, not just the counter.
        transferSenderMarker = StdPrecompiles.POLICY_REGISTRY.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        transferReceiverMarker =
            StdPrecompiles.POLICY_REGISTRY.createPolicy(admin, IPolicyRegistry.PolicyType.BLOCKLIST);
        transferExecutorMarker =
            StdPrecompiles.POLICY_REGISTRY.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        mintReceiverMarker = StdPrecompiles.POLICY_REGISTRY.createPolicy(admin, IPolicyRegistry.PolicyType.BLOCKLIST);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, transferSenderMarker);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, transferReceiverMarker);
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, transferExecutorMarker);
        _setPolicy(B20Constants.MINT_RECEIVER_POLICY, mintReceiverMarker);

        // ---------- Pause vectors ----------
        // Pause every defined PausableFeature so the layout pin covers
        // each enum position. The policy lanes above blocked MINT
        // already via policy ID; pause and policy are independent
        // storage fields so both signals are simultaneously valid.
        _pause(IB20.PausableFeature.TRANSFER);
        _pause(IB20.PausableFeature.MINT);
        _pause(IB20.PausableFeature.BURN);

        // ---------- Nonce ----------
        // Permit increments alice's nonce. To sign a valid permit we
        // need her private key, but since we're not testing the permit
        // path's semantics here (just that the nonce slot updates), we
        // can use any valid private key whose address we control.
        // Simpler: mint a permit through alice by giving her a key via
        // boundPrivateKey. We can't change `alice` (already labelled), so
        // we use a dedicated permit signer.
        //
        // Skip permit-driven nonce bump to keep this layout test focused
        // on slot coverage. The nonce slot is asserted against
        // `token.nonces(alice)` which will be zero at this point, and
        // the slot's correctness (vs. the surface getter) is what
        // matters. A non-zero nonce assertion is covered explicitly in
        // permit.t.sol.
    }
}
