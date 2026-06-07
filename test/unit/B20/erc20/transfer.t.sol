// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";
import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract B20TransferTest is B20Test {
    /// @notice Verifies transfer reverts when the TRANSFER feature is paused
    /// @dev Pause guard fires before policy or balance checks; checks ContractPaused(TRANSFER) error
    function test_transfer_revert_whenTransferPaused(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _pause(IB20.PausableFeature.TRANSFER);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transfer(to, amount);
    }

    /// @notice Verifies transfer reverts when sender is not authorized under TRANSFER_SENDER_POLICY
    /// @dev Policy guard for the from-side; checks PolicyForbids(TRANSFER_SENDER_POLICY, policyId) error
    function test_transfer_revert_senderPolicyForbids(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(from);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_SENDER_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transfer(to, amount);
    }

    /// @notice Verifies transfer reverts when recipient is not authorized under TRANSFER_RECEIVER_POLICY
    /// @dev Policy guard for the to-side; checks PolicyForbids(TRANSFER_RECEIVER_POLICY, policyId) error
    function test_transfer_revert_receiverPolicyForbids(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(from);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_RECEIVER_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transfer(to, amount);
    }

    /// @notice Verifies transfer reverts when sender balance is insufficient
    /// @dev Balance precondition; checks InsufficientBalance(sender, balance, amount) error
    function test_transfer_revert_insufficientBalance(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint256).max);
        // from has zero balance; any nonzero amount exceeds it.

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, from, 0, amount));
        token.transfer(to, amount);
    }

    /// @notice Verifies transfer reverts for the zero recipient address
    /// @dev OZ ERC-6093 invariant; checks InvalidReceiver(address(0)) error
    function test_transfer_revert_zeroRecipient(address from, uint256 amount) public {
        _assumeValidActor(from);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
    }

    /// @notice Verifies transfer reverts when called by the zero address
    /// @dev Defense-in-depth check inside _transfer: from == address(0) reverts InvalidSender
    ///      before any pause / policy / balance checks. For the public `transfer` path
    ///      from = msg.sender, so reaching this branch requires pranking address(0)
    ///      (filtered out of our normal fuzz tests by _assumeValidActor).
    function test_transfer_revert_zeroSender(address to, uint256 amount) public {
        _assumeValidActor(to);

        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSender.selector, address(0)));
        token.transfer(to, amount);
    }

    /// @notice Verifies transfer debits the sender balance by amount
    /// @dev Accounting half: balanceOf(from) decreases by exactly amount.
    ///      Paired slot assertion: `balances[from]` slot reflects the
    ///      debit so the Rust precompile impl can be cross-validated
    ///      against the same storage layout.
    function test_transfer_success_debitsSender(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);

        _mint(from, amount);
        uint256 before = token.balanceOf(from);

        vm.prank(from);
        token.transfer(to, amount);
        assertEq(token.balanceOf(from), before - amount, "from must be debited by amount");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(from))),
            before - amount,
            "balances[from] slot must reflect the debit"
        );
    }

    /// @notice Verifies transfer credits the receiver balance by amount
    /// @dev Accounting half: balanceOf(to) increases by exactly amount.
    ///      Paired slot assertion: `balances[to]` slot reflects the credit.
    function test_transfer_success_creditsReceiver(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);

        _mint(from, amount);
        uint256 before = token.balanceOf(to);

        vm.prank(from);
        token.transfer(to, amount);
        assertEq(token.balanceOf(to), before + amount, "to must be credited by amount");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(to))),
            before + amount,
            "balances[to] slot must reflect the credit"
        );
    }

    /// @notice Verifies transfer emits Transfer(from, to, amount)
    /// @dev Event integrity; canonical Transfer event test for the transfer path
    function test_transfer_success_emitsTransfer(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);

        _mint(from, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(from, to, amount);
        vm.prank(from);
        token.transfer(to, amount);
    }

    /// @notice Verifies transfer returns true on success
    /// @dev ERC-20 return-value contract
    function test_transfer_success_returnsTrue(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);

        _mint(from, amount);

        vm.prank(from);
        assertTrue(token.transfer(to, amount), "transfer must return true");
    }

    /// @notice Verifies repeated self-transfers never inflate balance or totalSupply
    /// @dev Regression guard against a dual-write bug where `balances[from] -= amount` followed by
    ///      `balances[to] += amount` with from == to could net non-zero. Five self-transfers must
    ///      leave both the balance and totalSupply exactly where they started.
    function test_transfer_success_selfTransferNoInflation(address account, uint256 amount) public {
        _assumeValidActor(account);
        amount = bound(amount, 0, type(uint128).max);

        _mint(account, amount);
        uint256 balanceBefore = token.balanceOf(account);
        uint256 supplyBefore = token.totalSupply();

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(account);
            token.transfer(account, amount);
        }

        assertEq(token.balanceOf(account), balanceBefore, "self-transfer must not change balance");
        assertEq(token.totalSupply(), supplyBefore, "self-transfer must not change totalSupply");
    }

    /// @notice Verifies a privileged (factory bootstrap) transfer bypasses the TRANSFER_SENDER_POLICY
    /// @dev During the bootstrap window the factory caller is privileged and the sender policy is not
    ///      consulted. With the sender policy set to ALWAYS_BLOCK a non-privileged transfer would
    ///      revert PolicyForbids; the privileged path must succeed. Window reopened via vm.store on
    ///      the initialized slot, mirroring the privileged transferFrom regression tests.
    function test_transfer_success_privilegedBypassesSenderPolicy(address to, uint256 amount) public {
        // Mock-only: the privileged path is reached by reopening the bootstrap window via
        // vm.store on the mock's initialized slot. The live precompile derives privilege from a
        // real factory bootstrap call, not a storable flag, so this mechanism doesn't apply.
        vm.skip(vm.envOr("LIVE_PRECOMPILES", false));
        _assumeValidActor(to);
        amount = bound(amount, 0, type(uint128).max);

        _mint(address(factory), amount);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        // Reopen the factory bootstrap window so the factory caller is privileged.
        vm.store(address(token), MockB20Storage.initializedSlot(), bytes32(0));

        vm.prank(address(factory));
        token.transfer(to, amount);

        assertEq(token.balanceOf(to), amount, "privileged transfer must succeed despite blocked sender policy");
    }

    /// @notice Verifies a privileged (factory bootstrap) transfer bypasses the TRANSFER_RECEIVER_POLICY
    /// @dev Receiver-side mirror of the sender bypass: with the receiver policy set to ALWAYS_BLOCK a
    ///      non-privileged transfer would revert PolicyForbids, but the privileged path must succeed.
    function test_transfer_success_privilegedBypassesReceiverPolicy(address to, uint256 amount) public {
        // Mock-only: see test_transfer_success_privilegedBypassesSenderPolicy. The vm.store
        // bootstrap-window reopen has no effect on the live precompile.
        vm.skip(vm.envOr("LIVE_PRECOMPILES", false));
        _assumeValidActor(to);
        amount = bound(amount, 0, type(uint128).max);

        _mint(address(factory), amount);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        // Reopen the factory bootstrap window so the factory caller is privileged.
        vm.store(address(token), MockB20Storage.initializedSlot(), bytes32(0));

        vm.prank(address(factory));
        token.transfer(to, amount);

        assertEq(token.balanceOf(to), amount, "privileged transfer must succeed despite blocked receiver policy");
    }

    /// @notice Verifies transfer succeeds when the sender is a member of a custom ALLOWLIST policy
    /// @dev Exercises the external-registry authorization path (a real custom policy id, not the
    ///      ALWAYS_ALLOW / ALWAYS_BLOCK sentinels): isAuthorized resolves to a membership SLOAD.
    ///      The sentinel-only tests cannot catch a divergence in custom-allowlist evaluation.
    function test_transfer_success_externalSenderPolicyAllows(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 0, type(uint128).max);

        uint64 id = _createAllowlist(from, true);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, id);
        _mint(from, amount);

        vm.prank(from);
        token.transfer(to, amount);

        assertEq(token.balanceOf(to), amount, "transfer must succeed when sender is allowlisted");
    }

    /// @notice Verifies transfer succeeds when the receiver is a member of a custom ALLOWLIST policy
    /// @dev Receiver-side mirror of the external sender allow path.
    function test_transfer_success_externalReceiverPolicyAllows(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 0, type(uint128).max);

        uint64 id = _createAllowlist(to, true);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, id);
        _mint(from, amount);

        vm.prank(from);
        token.transfer(to, amount);

        assertEq(token.balanceOf(to), amount, "transfer must succeed when receiver is allowlisted");
    }

    /// @notice Verifies transfer reverts when the sender is NOT a member of a custom ALLOWLIST policy
    /// @dev Negative external-registry path: an allowlist with no membership for `from` resolves
    ///      isAuthorized to false, so the sender guard reverts PolicyForbids with the custom id.
    ///      No balance needed — the policy check fires before the balance check.
    function test_transfer_revert_externalSenderPolicyDenies(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);

        uint64 id = _createAllowlist(from, false); // create the allowlist but do NOT add `from`
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, id);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyForbids.selector, B20Constants.TRANSFER_SENDER_POLICY, id));
        token.transfer(to, amount);
    }

    /// @notice Creates a custom ALLOWLIST policy administered by `admin`, optionally seeding
    ///         `member`, and returns its id. Drives the external-registry authorization path
    ///         (custom policy id) beyond the ALWAYS_ALLOW / ALWAYS_BLOCK sentinels.
    function _createAllowlist(address member, bool addMember) private returns (uint64 id) {
        vm.prank(admin);
        id = StdPrecompiles.POLICY_REGISTRY.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        if (addMember) {
            address[] memory accounts = new address[](1);
            accounts[0] = member;
            vm.prank(admin);
            StdPrecompiles.POLICY_REGISTRY.updateAllowlist(id, true, accounts);
        }
    }
}
