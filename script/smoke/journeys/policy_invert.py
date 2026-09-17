"""PolicyRegistry NOT/invert smoketest (Denim).

Exercises bit-63 policy inversion against the live precompile. The journey first
checks every policy read view against a simple base policy and its inverse. It
then attaches an inverted simple policy to one Asset token, and an inverted
composite to another. Mutating the underlying membership sets must immediately
flip authorization on the attached tokens: policy inversion has no copied state.

Fork-gated: ``invertedPolicyId(uint64)`` is introduced at Denim. The journey
probes that selector and skips before Denim, where the selector is unknown.
"""

from __future__ import annotations

from web3.exceptions import BadFunctionCallOutput, ContractLogicError

from .. import config
from ..chain import Chain, log, skip, step
from ..codec import AssetCreateParams, init_call


def _is_denim(c: Chain) -> bool:
    """Return whether the PolicyRegistry exposes the Denim inversion view.

    A pre-Denim registry rejects this new selector. A registry that accepts the
    selector must return its specified result; a wrong result is an assertion
    failure, not a reason to skip.
    """
    try:
        inverted_always_allow = c.policy.functions.invertedPolicyId(config.ALWAYS_ALLOW_ID).call()
    except (ContractLogicError, BadFunctionCallOutput):
        return False
    c.assert_eq(
        inverted_always_allow,
        config.INVERTED_POLICY_BIT,
        "invertedPolicyId(ALWAYS_ALLOW) sets bit 63",
    )
    return True


def _policy_views(c: Chain) -> tuple[int, int]:
    """Create a simple base policy and verify all policy views through its inverse."""
    step(1, "policy views: create a simple ALLOWLIST base containing alice, then obtain its NOT form")
    simple = c.create_policy_with_accounts(c.DEPLOYER, config.POLICY_TYPE_ALLOWLIST, [c.ALICE])
    inverted_simple = c.policy.functions.invertedPolicyId(simple).call()

    c.assert_eq(inverted_simple, simple ^ config.INVERTED_POLICY_BIT, "invertedPolicyId toggles bit 63")
    c.assert_eq(
        c.policy.functions.invertedPolicyId(inverted_simple).call(), simple, "invertedPolicyId is involutive"
    )
    c.assert_eq(
        c.policy.functions.MIN_COMPOSITE_CHILD_POLICIES().call(),
        config.MIN_CHILD_POLICIES,
        "minimum child count",
    )
    c.assert_eq(
        c.policy.functions.MAX_COMPOSITE_CHILD_POLICIES().call(),
        config.MAX_CHILD_POLICIES,
        "maximum child count",
    )

    c.assert_eq(c.policy.functions.policyExists(simple).call(), True, "simple base exists")
    c.assert_eq(c.policy.functions.policyExists(inverted_simple).call(), True, "inverted simple resolves as existing")
    c.assert_eq(c.policy.functions.policyAdmin(simple).call(), c.DEPLOYER, "simple base admin == deployer")
    c.assert_eq(
        c.policy.functions.policyAdmin(inverted_simple).call(), c.DEPLOYER, "inverted simple resolves base admin"
    )
    c.assert_eq(c.policy.functions.pendingPolicyAdmin(simple).call(), config.ZERO, "simple base has no pending admin")
    c.assert_eq(
        c.policy.functions.pendingPolicyAdmin(inverted_simple).call(),
        config.ZERO,
        "inverted simple resolves pending admin",
    )
    c.assert_eq(c.policy.functions.compositePolicyChildIds(simple).call(), [], "simple base has no composite children")
    c.assert_eq(
        c.policy.functions.compositePolicyChildIds(inverted_simple).call(),
        [],
        "inverted simple has no composite children",
    )
    c.assert_eq(c.policy.functions.isAuthorized(simple, c.ALICE).call(), True, "simple base authorizes alice")
    c.assert_eq(c.policy.functions.isAuthorized(inverted_simple, c.ALICE).call(), False, "NOT simple denies alice")
    c.assert_eq(c.policy.functions.isAuthorized(simple, c.BOB).call(), False, "simple base denies bob")
    c.assert_eq(c.policy.functions.isAuthorized(inverted_simple, c.BOB).call(), True, "NOT simple authorizes bob")

    step(2, "pendingPolicyAdmin view resolves the same base record through the NOT form")
    c.send(c.policy.functions.stageUpdateAdmin(simple, c.USER2), c.deployer)
    c.assert_eq(c.policy.functions.pendingPolicyAdmin(simple).call(), c.USER2, "simple pending admin == user2")
    c.assert_eq(
        c.policy.functions.pendingPolicyAdmin(inverted_simple).call(), c.USER2, "inverted simple resolves staged admin"
    )
    c.send(c.policy.functions.stageUpdateAdmin(simple, config.ZERO), c.deployer)
    c.assert_eq(
        c.policy.functions.pendingPolicyAdmin(inverted_simple).call(),
        config.ZERO,
        "clearing base admin clears inverse",
    )

    unknown = 999999
    inverted_unknown = c.policy.functions.invertedPolicyId(unknown).call()
    c.assert_eq(c.policy.functions.policyExists(unknown).call(), False, "unknown base does not exist")
    c.assert_eq(c.policy.functions.policyExists(inverted_unknown).call(), False, "inverted unknown does not exist")
    c.assert_eq(c.policy.functions.policyAdmin(inverted_unknown).call(), config.ZERO, "inverted unknown has no admin")
    c.assert_eq(
        c.policy.functions.pendingPolicyAdmin(inverted_unknown).call(),
        config.ZERO,
        "inverted unknown has no pending admin",
    )
    c.assert_eq(
        c.policy.functions.compositePolicyChildIds(inverted_unknown).call(),
        [],
        "inverted unknown has no children",
    )
    c.assert_eq(c.policy.functions.isAuthorized(inverted_unknown, c.BOB).call(), False, "inverted unknown fails closed")
    return simple, inverted_simple


def _inverted_simple_token(c: Chain, simple: int, inverted_simple: int) -> None:
    """Attach NOT(allowlist) and show base membership changes flip token access."""
    step(3, "attach NOT simple policy to mint and transfer receivers on an Asset token")
    salt = c.cfg.salt_for("policy-invert-simple")
    params = AssetCreateParams("NOT Simple Asset", "NSIMP", c.DEPLOYER, config.ASSET_DECIMALS).encode()
    init_calls = [
        init_call(c.asset_abi, "updatePolicy", config.MINT_RECEIVER_POLICY, inverted_simple),
        init_call(c.asset_abi, "updatePolicy", config.TRANSFER_RECEIVER_POLICY, inverted_simple),
        init_call(c.asset_abi, "grantRole", config.MINT_ROLE, c.DEPLOYER),
    ]
    token_address = c.predict_b20(config.VARIANT_ASSET, salt)
    c.create_b20(config.VARIANT_ASSET, salt, params, init_calls)
    token = c.asset_at(token_address)
    c.assert_eq(
        token.functions.policyId(config.MINT_RECEIVER_POLICY).call(),
        inverted_simple,
        "token stores NOT simple mint policy",
    )
    c.assert_eq(
        token.functions.policyId(config.TRANSFER_RECEIVER_POLICY).call(),
        inverted_simple,
        "token stores NOT simple transfer policy",
    )

    step(4, "NOT simple policy denies listed alice, but permits unlisted deployer")
    c.send(token.functions.mint(c.DEPLOYER, config.amt(10, 18)), c.deployer)
    c.expect_revert("PolicyForbids", token.functions.mint(c.ALICE, config.amt(1, 18)), c.DEPLOYER)
    c.expect_revert("PolicyForbids", token.functions.transfer(c.ALICE, config.amt(1, 18)), c.DEPLOYER)

    step(5, "removing alice from the simple base immediately permits mint and transfer through its NOT form")
    c.send(c.policy.functions.updateAllowlist(simple, False, [c.ALICE]), c.deployer)
    c.assert_eq(
        c.policy.functions.isAuthorized(inverted_simple, c.ALICE).call(),
        True,
        "NOT simple flips after base removal",
    )
    c.send(token.functions.mint(c.ALICE, config.amt(100, 18)), c.deployer)
    c.send(token.functions.transfer(c.ALICE, config.amt(1, 18)), c.deployer)
    c.assert_eq(
        token.functions.balanceOf(c.ALICE).call(),
        config.amt(101, 18),
        "alice receives mint and transfer after flip",
    )

    step(6, "restoring alice to the simple base immediately denies her through the attached NOT form")
    c.send(c.policy.functions.updateAllowlist(simple, True, [c.ALICE]), c.deployer)
    c.assert_eq(
        c.policy.functions.isAuthorized(inverted_simple, c.ALICE).call(),
        False,
        "NOT simple flips after base restoration",
    )
    c.expect_revert("PolicyForbids", token.functions.mint(c.ALICE, config.amt(1, 18)), c.DEPLOYER)


def _inverted_composite_token(c: Chain) -> None:
    """Attach NOT(INTERSECT[KYC, NOT sanctions]) and verify live composite inversion."""
    step(7, "create INTERSECT[KYC, NOT sanctions], and verify composite base views preserve inverted children")
    kyc = c.create_policy_with_accounts(c.DEPLOYER, config.POLICY_TYPE_ALLOWLIST, [c.ALICE, c.DEPLOYER])
    sanctions = c.create_policy_with_accounts(c.DEPLOYER, config.POLICY_TYPE_ALLOWLIST, [c.ALICE])
    not_sanctions = c.policy.functions.invertedPolicyId(sanctions).call()
    composite = c.create_composite_policy(c.DEPLOYER, config.POLICY_TYPE_INTERSECT, [kyc, not_sanctions])
    inverted_composite = c.policy.functions.invertedPolicyId(composite).call()

    c.assert_eq(c.policy.functions.policyExists(composite).call(), True, "composite base exists")
    c.assert_eq(
        c.policy.functions.policyExists(inverted_composite).call(),
        True,
        "inverted composite resolves as existing",
    )
    c.assert_eq(
        c.policy.functions.policyAdmin(inverted_composite).call(),
        c.DEPLOYER,
        "inverted composite resolves base admin",
    )
    c.assert_eq(
        c.policy.functions.pendingPolicyAdmin(inverted_composite).call(),
        config.ZERO,
        "inverted composite has no pending admin",
    )
    expected_children = [kyc, not_sanctions]
    c.assert_eq(
        c.policy.functions.compositePolicyChildIds(composite).call(),
        expected_children,
        "composite children retain order",
    )
    c.assert_eq(
        c.policy.functions.compositePolicyChildIds(inverted_composite).call(),
        expected_children,
        "inverted composite returns base children verbatim",
    )
    c.assert_eq(
        c.policy.functions.isAuthorized(composite, c.ALICE).call(),
        False,
        "sanctioned alice is denied by base composite",
    )
    c.assert_eq(
        c.policy.functions.isAuthorized(inverted_composite, c.ALICE).call(),
        True,
        "NOT composite authorizes alice",
    )
    c.assert_eq(
        c.policy.functions.isAuthorized(composite, c.DEPLOYER).call(),
        True,
        "deployer passes KYC and NOT sanctions",
    )
    c.assert_eq(
        c.policy.functions.isAuthorized(inverted_composite, c.DEPLOYER).call(),
        False,
        "NOT composite denies deployer",
    )

    step(8, "attach NOT composite to mint and transfer receivers on a second Asset token")
    salt = c.cfg.salt_for("policy-invert-composite")
    params = AssetCreateParams("NOT Composite Asset", "NCOMP", c.DEPLOYER, config.ASSET_DECIMALS).encode()
    init_calls = [
        init_call(c.asset_abi, "updatePolicy", config.MINT_RECEIVER_POLICY, inverted_composite),
        init_call(c.asset_abi, "updatePolicy", config.TRANSFER_RECEIVER_POLICY, inverted_composite),
        init_call(c.asset_abi, "grantRole", config.MINT_ROLE, c.DEPLOYER),
    ]
    token_address = c.predict_b20(config.VARIANT_ASSET, salt)
    c.create_b20(config.VARIANT_ASSET, salt, params, init_calls)
    token = c.asset_at(token_address)
    c.assert_eq(
        token.functions.policyId(config.MINT_RECEIVER_POLICY).call(),
        inverted_composite,
        "token stores NOT composite mint policy",
    )
    c.assert_eq(
        token.functions.policyId(config.TRANSFER_RECEIVER_POLICY).call(),
        inverted_composite,
        "token stores NOT composite transfer policy",
    )

    step(9, "NOT composite permits base-denied accounts and rejects the base-authorized deployer")
    c.send(token.functions.mint(c.ALICE, config.amt(100, 18)), c.deployer)
    c.send(token.functions.mint(c.BOB, config.amt(10, 18)), c.deployer)
    c.expect_revert("PolicyForbids", token.functions.mint(c.DEPLOYER, config.amt(1, 18)), c.DEPLOYER)

    step(10, "removing alice from sanctions flips the attached NOT composite and denies her")
    c.send(c.policy.functions.updateAllowlist(sanctions, False, [c.ALICE]), c.deployer)
    c.assert_eq(
        c.policy.functions.isAuthorized(composite, c.ALICE).call(),
        True,
        "base composite flips to authorize alice",
    )
    c.assert_eq(
        c.policy.functions.isAuthorized(inverted_composite, c.ALICE).call(),
        False,
        "NOT composite flips to deny alice",
    )
    c.expect_revert("PolicyForbids", token.functions.mint(c.ALICE, config.amt(1, 18)), c.DEPLOYER)
    c.expect_revert("PolicyForbids", token.functions.transfer(c.ALICE, config.amt(1, 18)), c.BOB)


def _events(c: Chain) -> None:
    step(11, "expected policy-invert flow events were emitted")
    c.assert_events_emitted(
        "policy-invert events",
        "PolicyCreated(uint64,address,uint8)",
        "PolicyAdminStaged(uint64,address,address)",
        "AllowlistUpdated(uint64,address,bool,address[])",
        "CompositePolicyUpdated(uint64,address,uint64[])",
        "B20Created(address,uint8,string,string,uint8,bytes)",
        "PolicyUpdated(bytes32,uint64,uint64)",
        "RoleGranted(bytes32,address,address)",
        "Transfer(address,address,uint256)",
    )


def run(c: Chain) -> None:
    log("policy-invert: starting")
    step("fork", "probe invertedPolicyId(uint64) (Denim)")
    if not _is_denim(c):
        skip("PolicyRegistry does not expose invertedPolicyId(uint64) — pre-Denim")
    simple, inverted_simple = _policy_views(c)
    _inverted_simple_token(c, simple, inverted_simple)
    _inverted_composite_token(c)
    _events(c)
    log("policy-invert: OK")
