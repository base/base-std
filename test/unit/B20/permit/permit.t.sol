// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20PermitTest is B20Test {
    /// @notice Verifies permit reverts when the deadline has passed
    /// @dev Time-bound signature; checks ExpiredSignature(deadline) error
    function test_permit_revert_expired(uint256 ownerPrivateKey, address spender, uint256 amount, uint256 deadline)
        public
    {
        ownerPrivateKey = boundPrivateKey(ownerPrivateKey);
        vm.assume(spender != address(0));
        deadline = bound(deadline, 0, block.timestamp - 1);
        address owner = vm.addr(ownerPrivateKey);

        // Sign a permit (with the bad deadline; sig is well-formed but expired).
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(ownerPrivateKey, spender, amount, deadline);

        vm.expectRevert(abi.encodeWithSelector(IB20.ExpiredSignature.selector, deadline));
        token.permit(owner, spender, amount, deadline, v, r, s);
    }

    /// @notice Verifies permit reverts when (v, r, s) recovers to an address other than owner
    /// @dev Signature integrity; checks InvalidSigner(signer, owner) error.
    ///      We sign the digest AS bob (so ecrecover deterministically returns vm.addr(pk))
    ///      but use pk that is NOT bob's, then submit with claimedOwner = bob.
    function test_permit_revert_invalidSigner(uint256 ownerPrivateKey, address spender, uint256 amount) public {
        ownerPrivateKey = boundPrivateKey(ownerPrivateKey);
        vm.assume(spender != address(0));
        address signer = vm.addr(ownerPrivateKey);
        vm.assume(signer != bob);
        uint256 deadline = type(uint256).max;

        // Sign the digest under bob's identity but with our (non-bob) private key.
        (uint8 v, bytes32 r, bytes32 s) = _signPermitAs(ownerPrivateKey, bob, spender, amount, deadline);

        // Recovery yields `signer`, which is not bob -> revert.
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSigner.selector, signer, bob));
        token.permit(bob, spender, amount, deadline, v, r, s);
    }

    /// @notice Verifies permit reverts for malformed (v, r, s) that causes recovery to fail
    /// @dev Backend-parity test for the recovered == address(0) path. EVM's `ecrecover` returns
    ///      `address(0)` on malformed signatures (invalid `v`, etc.); alloy in the Rust
    ///      precompile returns `Err` from `recover_address_from_prehash` on the same input,
    ///      which is mapped to `InvalidSigner(address(0), owner)`. Both backends therefore
    ///      revert with the same selector on a malformed signature, but via different code
    ///      paths. This test pins that parity so neither side can silently drift.
    ///
    ///      We pick v = 0 (only 27 and 28 are valid), so ecrecover deterministically returns
    ///      `address(0)` regardless of r and s.
    function test_permit_revert_malformedSignature(address spender, uint256 amount) public {
        vm.assume(spender != address(0));
        uint256 deadline = type(uint256).max;
        address owner = alice;
        uint8 v = 0; // invalid: only 27 and 28 produce a valid recovery
        bytes32 r = bytes32(uint256(1));
        bytes32 s = bytes32(uint256(2));

        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSigner.selector, address(0), owner));
        token.permit(owner, spender, amount, deadline, v, r, s);
    }

    /// @notice Verifies permit reverts when the same signature is replayed
    /// @dev Nonce monotonicity guards replay: after the first call advances the nonce,
    ///      the second call's digest is computed against the OLD nonce, so ecrecover
    ///      returns a different address (or random garbage); we expect a generic
    ///      InvalidSigner revert.
    function test_permit_revert_replayedSignature(uint256 ownerPrivateKey, address spender, uint256 amount) public {
        ownerPrivateKey = boundPrivateKey(ownerPrivateKey);
        vm.assume(spender != address(0));
        uint256 deadline = type(uint256).max;
        address owner = vm.addr(ownerPrivateKey);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(ownerPrivateKey, spender, amount, deadline);

        // First call succeeds, advances nonce.
        token.permit(owner, spender, amount, deadline, v, r, s);

        // Second call: the digest verified by the contract now uses nonce+1, but the
        // signature was over the original nonce. ecrecover returns some other address.
        // We can't predict which, so we use a partial-selector match.
        vm.expectPartialRevert(IB20.InvalidSigner.selector);
        token.permit(owner, spender, amount, deadline, v, r, s);
    }

    /// @notice Verifies permit reverts for the zero owner address
    /// @dev ECDSA precondition: a signature signed by some private key recovers to a non-zero
    ///      address, so claiming owner = 0 mismatches the recovered signer and reverts
    ///      InvalidSigner(recovered, 0). We sign the digest AS address(0) so ecrecover
    ///      deterministically returns vm.addr(pk) rather than garbage.
    function test_permit_revert_zeroOwner(address spender, uint256 amount) public {
        vm.assume(spender != address(0));
        uint256 deadline = type(uint256).max;
        uint256 privateKey = 0xA11CE;
        address signer = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = _signPermitAs(privateKey, address(0), spender, amount, deadline);

        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSigner.selector, signer, address(0)));
        token.permit(address(0), spender, amount, deadline, v, r, s);
    }

    /// @notice Verifies permit sets allowance(owner, spender) to amount
    /// @dev Same effect as approve via signature; canonical allowance readback test lives in allowance.t.sol.
    ///      Paired slot assertion: `allowances[owner][spender]` slot
    ///      reflects the permit value.
    function test_permit_success_setsAllowance(uint256 ownerPrivateKey, address spender, uint256 amount) public {
        ownerPrivateKey = boundPrivateKey(ownerPrivateKey);
        vm.assume(spender != address(0));
        uint256 deadline = type(uint256).max;
        address owner = vm.addr(ownerPrivateKey);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(ownerPrivateKey, spender, amount, deadline);
        token.permit(owner, spender, amount, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), amount, "allowance must reflect permit");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(owner, spender))),
            amount,
            "allowances[owner][spender] slot must reflect the permit"
        );
    }

    /// @notice Verifies a second permit REPLACES the prior allowance, not ADDS to it
    /// @dev `permit` MUST set `allowance[owner][spender] = value`, not
    ///      `allowance[owner][spender] += value`. A single permit success test can't
    ///      catch the additive bug (0 + value == value), so we permit twice with
    ///      distinct values and assert only the second value remains.
    ///      Paired slot assertion confirms the slot is overwritten, not summed.
    function test_permit_success_secondPermitReplacesAllowance(uint256 ownerPrivateKey, address spender) public {
        ownerPrivateKey = boundPrivateKey(ownerPrivateKey);
        vm.assume(spender != address(0));
        uint256 deadline = type(uint256).max;
        address owner = vm.addr(ownerPrivateKey);

        uint256 first = 100;
        uint256 second = 7;

        // Scope the first permit's (v, r, s) so they release before the
        // second batch is declared; avoids stack-too-deep on Solidity's
        // legacy codegen.
        {
            (uint8 v1, bytes32 r1, bytes32 s1) = _signPermit(ownerPrivateKey, spender, first, deadline);
            token.permit(owner, spender, first, deadline, v1, r1, s1);
        }
        assertEq(token.allowance(owner, spender), first, "first permit sets baseline");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(owner, spender))),
            first,
            "allowance slot must hold the first permit value"
        );

        {
            (uint8 v2, bytes32 r2, bytes32 s2) = _signPermit(ownerPrivateKey, spender, second, deadline);
            token.permit(owner, spender, second, deadline, v2, r2, s2);
        }
        assertEq(token.allowance(owner, spender), second, "second permit must REPLACE, not ADD");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(owner, spender))),
            second,
            "allowance slot must hold the REPLACED second value, not first+second"
        );
    }

    /// @notice Verifies permit advances nonces(owner) by exactly one
    /// @dev Replay protection; canonical nonces readback test lives in nonces.t.sol.
    ///      Paired slot assertion: `nonces[owner]` slot increments by 1.
    function test_permit_success_advancesNonce(uint256 ownerPrivateKey, address spender, uint256 amount) public {
        ownerPrivateKey = boundPrivateKey(ownerPrivateKey);
        vm.assume(spender != address(0));
        uint256 deadline = type(uint256).max;
        address owner = vm.addr(ownerPrivateKey);

        uint256 before = token.nonces(owner);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(ownerPrivateKey, spender, amount, deadline);
        token.permit(owner, spender, amount, deadline, v, r, s);

        assertEq(token.nonces(owner), before + 1, "nonce must advance by 1");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.nonceSlot(owner))),
            before + 1,
            "nonces[owner] slot must reflect the increment"
        );
    }

    /// @notice Verifies permit emits Approval(owner, spender, amount)
    /// @dev Event integrity; canonical Approval test lives in approve.t.sol -- permit emits the same event
    function test_permit_success_emitsApproval(uint256 ownerPrivateKey, address spender, uint256 amount) public {
        ownerPrivateKey = boundPrivateKey(ownerPrivateKey);
        vm.assume(spender != address(0));
        uint256 deadline = type(uint256).max;
        address owner = vm.addr(ownerPrivateKey);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(ownerPrivateKey, spender, amount, deadline);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Approval(owner, spender, amount);
        token.permit(owner, spender, amount, deadline, v, r, s);
    }
}
