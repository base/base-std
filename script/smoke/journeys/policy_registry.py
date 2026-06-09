"""PolicyRegistry precompile smoketest.

Policy creation (both types), membership, the built-in sentinels, the two-step
admin lifecycle, and — the part that matters most — a token actually enforcing a
policy (PolicyForbids on transfer + mint). Edges cover the registry's reverts and
the token-side write-time validation, then a flow-level event check.
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


def _events(c: Chain) -> None:
    step(17, "expected events emitted across the flow")
    c.assert_events_emitted(
        "policy events",
        "PolicyCreated(uint64,address,uint8)",
        "AllowlistUpdated(uint64,address,bool,address[])",
        "PolicyAdminStaged(uint64,address,address)",
        "PolicyAdminUpdated(uint64,address,address)",
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
    _events(c)
    log("policy-registry: OK")
