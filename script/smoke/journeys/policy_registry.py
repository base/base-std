"""PolicyRegistry precompile smoketest.

Policy creation (both types), membership, the built-in sentinels, the two-step
admin lifecycle, and — the part that matters most — a token actually enforcing a
policy (PolicyForbids on transfer + mint). Edges cover the registry's reverts and
the token-side write-time validation, then a flow-level event check.

`_composite` covers the UNION/INTERSECT composite gates: construction, live
gate evaluation over child membership, full-replacement `updateComposite`
semantics, the child-set validation reverts, and token enforcement through a
composite.
"""

from __future__ import annotations

from .. import config
from ..chain import Chain, log, step
from ..codec import AssetCreateParams, init_call


def _journey(c: Chain) -> int:
    step(1, "create ALLOWLIST policy (pidA); admin == deployer")
    pid_a = c.create_policy(c.DEPLOYER, config.POLICY_TYPE_ALLOWLIST)
    c.assert_eq(c.policy.functions.policyExists(pid_a).call(), True, "pidA exists")
    c.assert_eq(c.policy.functions.policyAdmin(pid_a).call(), c.DEPLOYER, "pidA admin == deployer")

    step(2, "create seeded BLOCKLIST policy (pidB) blocking bob")
    pid_b = c.create_policy_with_accounts(c.DEPLOYER, config.POLICY_TYPE_BLOCKLIST, [c.BOB])
    c.assert_eq(c.policy.functions.isAuthorized(pid_b, c.BOB).call(), False, "bob blocked in pidB")
    c.assert_eq(c.policy.functions.isAuthorized(pid_b, c.ALICE).call(), True, "alice allowed (blocklist default)")

    step(3, "allowlist membership: add alice to pidA")
    c.send(c.policy.functions.updateAllowlist(pid_a, True, [c.ALICE]), c.deployer)
    c.assert_eq(c.policy.functions.isAuthorized(pid_a, c.ALICE).call(), True, "alice allowed in pidA")
    c.assert_eq(c.policy.functions.isAuthorized(pid_a, c.BOB).call(), False, "bob not in pidA (allowlist default)")

    step(4, "built-in sentinels")
    c.assert_eq(c.policy.functions.isAuthorized(config.ALWAYS_ALLOW_ID, c.BOB).call(), True, "ALWAYS_ALLOW authorizes anyone")
    c.assert_eq(c.policy.functions.isAuthorized(config.ALWAYS_BLOCK_ID, c.BOB).call(), False, "ALWAYS_BLOCK blocks anyone")

    step(5, "two-step admin transfer pidA: deployer stages user2, user2 finalizes")
    c.send(c.policy.functions.stageUpdateAdmin(pid_a, c.USER2), c.deployer)
    c.assert_eq(c.policy.functions.pendingPolicyAdmin(pid_a).call(), c.USER2, "user2 staged as pending admin")
    c.fund_user2()
    c.send(c.policy.functions.finalizeUpdateAdmin(pid_a), c.user2)
    c.assert_eq(c.policy.functions.policyAdmin(pid_a).call(), c.USER2, "pidA admin == user2")
    c.assert_eq(c.policy.functions.pendingPolicyAdmin(pid_a).call(), config.ZERO, "pending admin cleared")

    step(6, "renounce pidA admin (user2); policy frozen but still queryable")
    c.send(c.policy.functions.renounceAdmin(pid_a), c.user2)
    c.assert_eq(c.policy.functions.policyAdmin(pid_a).call(), config.ZERO, "pidA admin renounced")
    c.assert_eq(c.policy.functions.policyExists(pid_a).call(), True, "pidA still exists (frozen)")

    return pid_b


def _enforcement(c: Chain):
    step(7, "create ALLOWLIST policy (pidR) seeded with alice")
    pid_r = c.create_policy_with_accounts(c.DEPLOYER, config.POLICY_TYPE_ALLOWLIST, [c.ALICE])

    step(8, "create ASSET token wired to pidR on TRANSFER_RECEIVER + MINT_RECEIVER")
    salt = c.cfg.salt_for("policy-enforce")
    params = AssetCreateParams("Gated Asset", "GATE", c.DEPLOYER, config.ASSET_DECIMALS).encode()
    init_calls = [
        init_call(c.asset_abi, "updatePolicy", config.TRANSFER_RECEIVER_POLICY, pid_r),
        init_call(c.asset_abi, "updatePolicy", config.MINT_RECEIVER_POLICY, pid_r),
        init_call(c.asset_abi, "grantRole", config.MINT_ROLE, c.DEPLOYER),
    ]
    tok_addr = c.predict_b20(config.VARIANT_ASSET, salt)
    c.create_b20(config.VARIANT_ASSET, salt, params, init_calls)
    tok = c.asset_at(tok_addr)
    c.assert_eq(tok.functions.policyId(config.MINT_RECEIVER_POLICY).call(), pid_r, "MINT_RECEIVER_POLICY == pidR")

    step(9, "allowed paths: mint to allowlisted accounts, then transfer to one")
    c.send(tok.functions.mint(c.ALICE, config.amt(100, 18)), c.deployer)
    c.assert_eq(tok.functions.balanceOf(c.ALICE).call(), config.amt(100, 18), "alice minted (in allowlist)")
    c.send(c.policy.functions.updateAllowlist(pid_r, True, [c.DEPLOYER]), c.deployer)
    c.send(tok.functions.mint(c.DEPLOYER, config.amt(100, 18)), c.deployer)
    c.send(tok.functions.transfer(c.ALICE, config.amt(1, 18)), c.deployer)
    c.assert_eq(tok.functions.balanceOf(c.ALICE).call(), config.amt(101, 18), "transfer to allowlisted receiver")

    step(10, "denied receiver on transfer -> PolicyForbids")
    c.expect_revert("PolicyForbids", tok.functions.transfer(c.BOB, config.amt(1, 18)), c.DEPLOYER)

    step(11, "denied receiver on mint -> PolicyForbids")
    c.expect_revert("PolicyForbids", tok.functions.mint(c.BOB, config.amt(1, 18)), c.DEPLOYER)

    return tok, pid_r


def _edges(c: Chain, tok, pid_r: int, pid_b: int) -> None:
    step(12, "wrong-type mutation: updateBlocklist on an ALLOWLIST -> IncompatiblePolicyType")
    c.expect_revert("IncompatiblePolicyType", c.policy.functions.updateBlocklist(pid_r, True, [c.BOB]), c.DEPLOYER)

    step(13, "non-admin mutation: user2 updates pidR -> Unauthorized")
    c.expect_revert("Unauthorized", c.policy.functions.updateAllowlist(pid_r, True, [c.BOB]), c.USER2)

    step(14, "zero admin: createPolicy(0) -> ZeroAddress")
    c.expect_revert("ZeroAddress", c.policy.functions.createPolicy(config.ZERO, config.POLICY_TYPE_ALLOWLIST), c.DEPLOYER)

    step(15, "finalize with nothing staged -> NoPendingAdmin")
    c.expect_revert("NoPendingAdmin", c.policy.functions.finalizeUpdateAdmin(pid_b), c.DEPLOYER)

    step(16, "token write-time validation: updatePolicy(unknown id) -> PolicyNotFound")
    c.expect_revert("PolicyNotFound", tok.functions.updatePolicy(config.TRANSFER_SENDER_POLICY, 999999), c.DEPLOYER)


def _composite(c: Chain, pid_b: int) -> None:
    """Composite (UNION / INTERSECT) policies: construction, evaluation, update, edges, enforcement."""
    carol = c.cfg.new_addr("carol")
    dave = c.cfg.new_addr("dave")
    erin = c.cfg.new_addr("erin")

    step(17, "seed two simple children, then create a UNION and an INTERSECT over them")
    # childX allows {alice, dave}; childY allows {bob, dave}. dave is the only account in BOTH.
    pid_x = c.create_policy_with_accounts(c.DEPLOYER, config.POLICY_TYPE_ALLOWLIST, [c.ALICE, dave])
    pid_y = c.create_policy_with_accounts(c.DEPLOYER, config.POLICY_TYPE_ALLOWLIST, [c.BOB, dave])
    pid_union = c.create_composite_policy(c.DEPLOYER, config.POLICY_TYPE_UNION, [pid_x, pid_y])
    pid_inter = c.create_composite_policy(c.DEPLOYER, config.POLICY_TYPE_INTERSECT, [pid_x, pid_y])
    c.assert_eq(c.policy.functions.policyExists(pid_union).call(), True, "UNION composite exists")
    c.assert_eq(c.policy.functions.policyAdmin(pid_union).call(), c.DEPLOYER, "UNION admin == deployer")
    c.assert_eq(c.policy.functions.policyExists(pid_inter).call(), True, "INTERSECT composite exists")
    c.assert_eq(c.policy.functions.policyAdmin(pid_inter).call(), c.DEPLOYER, "INTERSECT admin == deployer")

    step(18, "UNION authorizes an account in ANY child; denies one in none")
    c.assert_eq(c.policy.functions.isAuthorized(pid_union, c.ALICE).call(), True, "UNION: alice (childX only) allowed")
    c.assert_eq(c.policy.functions.isAuthorized(pid_union, c.BOB).call(), True, "UNION: bob (childY only) allowed")
    c.assert_eq(c.policy.functions.isAuthorized(pid_union, dave).call(), True, "UNION: dave (both children) allowed")
    c.assert_eq(c.policy.functions.isAuthorized(pid_union, carol).call(), False, "UNION: carol (no child) denied")

    step(19, "INTERSECT authorizes only an account in EVERY child")
    c.assert_eq(c.policy.functions.isAuthorized(pid_inter, dave).call(), True, "INTERSECT: dave (every child) allowed")
    c.assert_eq(c.policy.functions.isAuthorized(pid_inter, c.ALICE).call(), False, "INTERSECT: alice missing childY -> denied")
    c.assert_eq(c.policy.functions.isAuthorized(pid_inter, c.BOB).call(), False, "INTERSECT: bob missing childX -> denied")
    c.assert_eq(c.policy.functions.isAuthorized(pid_inter, carol).call(), False, "INTERSECT: carol (no child) denied")

    step(20, "live evaluation: mutate a CHILD's membership, composite verdict flips (no call on the composite)")
    c.send(c.policy.functions.updateAllowlist(pid_x, True, [carol]), c.deployer)
    c.assert_eq(c.policy.functions.isAuthorized(pid_union, carol).call(), True, "UNION: carol allowed after childX add")
    c.assert_eq(c.policy.functions.isAuthorized(pid_inter, carol).call(), False, "INTERSECT: carol still denied (childY missing)")
    c.send(c.policy.functions.updateAllowlist(pid_y, True, [carol]), c.deployer)
    c.assert_eq(c.policy.functions.isAuthorized(pid_inter, carol).call(), True, "INTERSECT: carol allowed once in every child")
    c.send(c.policy.functions.updateAllowlist(pid_x, False, [carol]), c.deployer)
    c.assert_eq(c.policy.functions.isAuthorized(pid_inter, carol).call(), False, "INTERSECT: carol denied again after childX removal")

    step(21, "updateComposite REPLACES the child set (no merge); event carries the exact new set")
    pid_c1 = c.create_policy_with_accounts(c.DEPLOYER, config.POLICY_TYPE_ALLOWLIST, [erin])
    pid_c2 = c.create_policy_with_accounts(c.DEPLOYER, config.POLICY_TYPE_ALLOWLIST, [erin])
    c.assert_eq(c.policy.functions.isAuthorized(pid_union, c.ALICE).call(), True, "pre-update: alice allowed via childX")
    receipt = c.send(c.policy.functions.updateComposite(pid_union, [pid_c1, pid_c2]), c.deployer)
    c.assert_eq(c.policy.functions.isAuthorized(pid_union, c.ALICE).call(), False, "post-update: alice denied (old children dropped, not merged)")
    c.assert_eq(c.policy.functions.isAuthorized(pid_union, c.BOB).call(), False, "post-update: bob denied (old children dropped)")
    c.assert_eq(c.policy.functions.isAuthorized(pid_union, erin).call(), True, "post-update: erin allowed via the new children")
    # Payload-level check: assert_events_emitted is presence-only, so decode this specific receipt.
    c.assert_eq(
        c.composite_children_from(receipt, pid_union),
        [pid_c1, pid_c2],
        "CompositePolicyUpdated payload == exactly the new child ids",
    )

    step(22, "child count outside [2,4] -> ChildPoliciesOutsideOfRange")
    too_few = [pid_x]
    too_many = [pid_x, pid_y, pid_c1, pid_c2, pid_b]
    c.assert_eq(len(too_few) < config.MIN_CHILD_POLICIES, True, "fixture: 1 child is below MIN_CHILD_POLICIES")
    c.assert_eq(len(too_many) > config.MAX_CHILD_POLICIES, True, "fixture: 5 children is above MAX_CHILD_POLICIES")
    c.expect_revert(
        "ChildPoliciesOutsideOfRange",
        c.policy.functions.createCompositePolicy(c.DEPLOYER, config.POLICY_TYPE_UNION, too_few),
        c.DEPLOYER,
    )
    c.expect_revert(
        "ChildPoliciesOutsideOfRange",
        c.policy.functions.createCompositePolicy(c.DEPLOYER, config.POLICY_TYPE_UNION, too_many),
        c.DEPLOYER,
    )
    c.expect_revert("ChildPoliciesOutsideOfRange", c.policy.functions.updateComposite(pid_union, too_few), c.DEPLOYER)
    c.expect_revert("ChildPoliciesOutsideOfRange", c.policy.functions.updateComposite(pid_union, too_many), c.DEPLOYER)

    step(23, "a built-in sentinel as a child -> InvalidChildPolicy")
    c.expect_revert(
        "InvalidChildPolicy",
        c.policy.functions.createCompositePolicy(c.DEPLOYER, config.POLICY_TYPE_UNION, [config.ALWAYS_ALLOW_ID, pid_x]),
        c.DEPLOYER,
    )
    c.expect_revert(
        "InvalidChildPolicy",
        c.policy.functions.createCompositePolicy(c.DEPLOYER, config.POLICY_TYPE_UNION, [config.ALWAYS_BLOCK_ID, pid_x]),
        c.DEPLOYER,
    )
    c.expect_revert(
        "InvalidChildPolicy", c.policy.functions.updateComposite(pid_union, [config.ALWAYS_ALLOW_ID, pid_x]), c.DEPLOYER
    )

    step(24, "a composite as a child -> InvalidChildPolicy")
    c.expect_revert(
        "InvalidChildPolicy",
        c.policy.functions.createCompositePolicy(c.DEPLOYER, config.POLICY_TYPE_INTERSECT, [pid_inter, pid_x]),
        c.DEPLOYER,
    )
    c.expect_revert("InvalidChildPolicy", c.policy.functions.updateComposite(pid_union, [pid_inter, pid_x]), c.DEPLOYER)

    step(25, "non-admin updateComposite -> Unauthorized")
    c.expect_revert("Unauthorized", c.policy.functions.updateComposite(pid_union, [pid_x, pid_y]), c.USER2)

    step(26, "composite creator input guards: ZeroAddress, IncompatiblePolicyType")
    # ZeroAddress outranks every later check, so the child set here is deliberately valid.
    c.expect_revert(
        "ZeroAddress",
        c.policy.functions.createCompositePolicy(config.ZERO, config.POLICY_TYPE_UNION, [pid_x, pid_y]),
        c.DEPLOYER,
    )
    # A composite must be UNION or INTERSECT; a simple gate is rejected by the composite creator.
    for simple in (config.POLICY_TYPE_ALLOWLIST, config.POLICY_TYPE_BLOCKLIST):
        c.expect_revert(
            "IncompatiblePolicyType",
            c.policy.functions.createCompositePolicy(c.DEPLOYER, simple, [pid_x, pid_y]),
            c.DEPLOYER,
        )
    # Mirror: updateComposite must reject a SIMPLE target, and the membership mutators must reject a
    # COMPOSITE target. Together with the conformance checks at the end of the journey this closes the
    # type-guard matrix in both directions, so a red conformance check reads as "the two creator-side
    # bugs" rather than "the type byte is ignored everywhere".
    c.expect_revert("IncompatiblePolicyType", c.policy.functions.updateComposite(pid_x, [pid_x, pid_y]), c.DEPLOYER)
    c.expect_revert(
        "IncompatiblePolicyType", c.policy.functions.updateAllowlist(pid_union, True, [c.BOB]), c.DEPLOYER
    )
    c.expect_revert(
        "IncompatiblePolicyType", c.policy.functions.updateBlocklist(pid_inter, True, [c.BOB]), c.DEPLOYER
    )

    step(27, "non-existent child -> PolicyNotFound, and it outranks InvalidChildPolicy")
    # A well-formed but never-created id. Type byte 0 (BLOCKLIST) — note this is exactly the shape whose
    # read-side semantics are permissive (an empty blocklist authorizes everyone), so child-existence
    # validation is the only thing standing between a permissionless caller and a composite that
    # authorizes every account while looking like a legitimate admin-owned gate.
    ghost = 999999
    c.assert_eq(c.policy.functions.policyExists(ghost).call(), False, "fixture: ghost child id does not exist")
    c.expect_revert(
        "PolicyNotFound",
        c.policy.functions.createCompositePolicy(c.DEPLOYER, config.POLICY_TYPE_UNION, [pid_x, ghost]),
        c.DEPLOYER,
    )
    # Ghost in FIRST position too: an impl that only validates childPolicyIds[0] passes the case above.
    c.expect_revert(
        "PolicyNotFound",
        c.policy.functions.createCompositePolicy(c.DEPLOYER, config.POLICY_TYPE_UNION, [ghost, pid_x]),
        c.DEPLOYER,
    )
    c.expect_revert("PolicyNotFound", c.policy.functions.updateComposite(pid_union, [pid_x, ghost]), c.DEPLOYER)
    # Precedence: existence is checked across the WHOLE set before validity. The invalid child is
    # placed FIRST and the ghost LAST, so a per-element validator would answer InvalidChildPolicy.
    c.expect_revert(
        "PolicyNotFound",
        c.policy.functions.createCompositePolicy(c.DEPLOYER, config.POLICY_TYPE_UNION, [pid_inter, ghost]),
        c.DEPLOYER,
    )

    step(28, "create ASSET token wired to a UNION composite on TRANSFER_RECEIVER + MINT_RECEIVER")
    # Dedicated children so the token's gate is unaffected by the mutations above.
    pid_t1 = c.create_policy_with_accounts(c.DEPLOYER, config.POLICY_TYPE_ALLOWLIST, [c.ALICE])
    pid_t2 = c.create_policy_with_accounts(c.DEPLOYER, config.POLICY_TYPE_ALLOWLIST, [c.DEPLOYER])
    pid_tok = c.create_composite_policy(c.DEPLOYER, config.POLICY_TYPE_UNION, [pid_t1, pid_t2])
    c.assert_eq(c.policy.functions.isAuthorized(pid_tok, c.ALICE).call(), True, "gate: alice authorized (child 1)")
    c.assert_eq(c.policy.functions.isAuthorized(pid_tok, c.DEPLOYER).call(), True, "gate: deployer authorized (child 2)")
    c.assert_eq(c.policy.functions.isAuthorized(pid_tok, c.BOB).call(), False, "gate: bob denied (neither child)")

    salt = c.cfg.salt_for("composite-enforce")
    params = AssetCreateParams("Composite Gated Asset", "CGATE", c.DEPLOYER, config.ASSET_DECIMALS).encode()
    init_calls = [
        init_call(c.asset_abi, "updatePolicy", config.TRANSFER_RECEIVER_POLICY, pid_tok),
        init_call(c.asset_abi, "updatePolicy", config.MINT_RECEIVER_POLICY, pid_tok),
        init_call(c.asset_abi, "grantRole", config.MINT_ROLE, c.DEPLOYER),
    ]
    tok_addr = c.predict_b20(config.VARIANT_ASSET, salt)
    c.create_b20(config.VARIANT_ASSET, salt, params, init_calls)
    ctok = c.asset_at(tok_addr)
    c.assert_eq(ctok.functions.policyId(config.MINT_RECEIVER_POLICY).call(), pid_tok, "MINT_RECEIVER_POLICY == composite")
    c.assert_eq(
        ctok.functions.policyId(config.TRANSFER_RECEIVER_POLICY).call(), pid_tok, "TRANSFER_RECEIVER_POLICY == composite"
    )

    step(29, "composite-authorized receivers: mint + transfer succeed")
    c.send(ctok.functions.mint(c.ALICE, config.amt(100, 18)), c.deployer)
    c.assert_eq(ctok.functions.balanceOf(c.ALICE).call(), config.amt(100, 18), "alice minted (authorized via child 1)")
    c.send(ctok.functions.mint(c.DEPLOYER, config.amt(100, 18)), c.deployer)
    c.send(ctok.functions.transfer(c.ALICE, config.amt(1, 18)), c.deployer)
    c.assert_eq(ctok.functions.balanceOf(c.ALICE).call(), config.amt(101, 18), "transfer to composite-authorized receiver")

    step(30, "composite-denied receiver on transfer -> PolicyForbids")
    c.expect_revert("PolicyForbids", ctok.functions.transfer(c.BOB, config.amt(1, 18)), c.DEPLOYER)

    step(31, "composite-denied receiver on mint -> PolicyForbids")
    c.expect_revert("PolicyForbids", ctok.functions.mint(c.BOB, config.amt(1, 18)), c.DEPLOYER)


def _events(c: Chain) -> None:
    step(32, "expected events emitted across the flow")
    c.assert_events_emitted(
        "policy events",
        "PolicyCreated(uint64,address,uint8)",
        "AllowlistUpdated(uint64,address,bool,address[])",
        "PolicyAdminStaged(uint64,address,address)",
        "PolicyAdminUpdated(uint64,address,address)",
        "CompositePolicyUpdated(uint64,address,uint64[])",
        "B20Created(address,uint8,string,string,uint8,bytes)",
        "PolicyUpdated(bytes32,uint64,uint64)",
        "Transfer(address,address,uint256)",
        "RoleGranted(bytes32,address,address)",
    )


def run(c: Chain) -> None:
    log("policy-registry: starting")
    pid_b = _journey(c)
    tok, pid_r = _enforcement(c)
    _edges(c, tok, pid_r, pid_b)
    _composite(c, pid_b)
    _events(c)
    log("policy-registry: OK")
