#!/usr/bin/env bash
# policy-registry.sh — PolicyRegistry precompile smoketest.
#
# STUB: step-level scaffold for scope review. No executable bodies yet.
# Flexes policy creation (both types), membership, the built-in sentinels, the
# two-step admin lifecycle, and — the part that matters most — a token actually
# enforcing a policy (PolicyForbids on transfer + mint). Edges cover the
# registry's reverts and the token-side write-time validation.
#
# Run: RPC_URL=... DEPLOYER_PK=... USER2_PK=... ./policy-registry.sh
#      (or `make smoke-policy`)

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/smoke/smoke-lib.sh
source "$HERE/smoke-lib.sh"

# Golden path: registry mechanics.
policy_journey() {
    # 1. create allowlist: pidA = createPolicy(deployer, ALLOWLIST)
    #    assert policyExists(pidA) == true; assert policyAdmin(pidA) == deployer
    # 2. create seeded blocklist: pidB = createPolicyWithAccounts(deployer, BLOCKLIST, [bob])
    #    assert isAuthorized(pidB, bob) == false  (blocked)
    #    assert isAuthorized(pidB, alice) == true (blocklist default-allow)
    # 3. membership: updateAllowlist(pidA, true, [alice])
    #    assert isAuthorized(pidA, alice) == true; isAuthorized(pidA, bob) == false
    # 4. built-ins: assert isAuthorized(ALWAYS_ALLOW_ID, anyone) == true
    #               assert isAuthorized(ALWAYS_BLOCK_ID, anyone) == false
    # 5. two-step admin transfer: stageUpdateAdmin(pidA, user2) from deployer
    #    assert pendingPolicyAdmin(pidA) == user2; fund_user2;
    #    finalizeUpdateAdmin(pidA) signed by USER2
    #    assert policyAdmin(pidA) == user2; assert pendingPolicyAdmin(pidA) == 0
    # 6. renounce: renounceAdmin(pidA) signed by USER2
    #    assert policyAdmin(pidA) == 0; assert policyExists(pidA) == true (frozen, still queryable)
    :
}

# Golden path: a token enforcing a policy end-to-end.
policy_enforcement() {
    # 7. fresh allowlist with alice as the only member:
    #    pidR = createPolicyWithAccounts(deployer, ALLOWLIST, [alice])
    # 8. create an ASSET token wired to it via initCalls:
    #    updatePolicy(TRANSFER_RECEIVER_POLICY, pidR) + updatePolicy(MINT_RECEIVER_POLICY, pidR)
    #    + grant MINT_ROLE to deployer. admin=deployer.
    # 9. allowed paths: mint(alice, 100e18) succeeds (alice ∈ allowlist)
    #    mint(deployer, 100e18) requires deployer ∈ allowlist — add deployer to pidR first,
    #    then transfer(alice, 1e18) from deployer succeeds.
    # 10. denied receiver on transfer: transfer(bob, 1e18) from deployer
    #         -> PolicyForbids(TRANSFER_RECEIVER_POLICY, pidR)   (bob ∉ allowlist)
    # 11. denied receiver on mint: mint(bob, 1e18)
    #         -> PolicyForbids(MINT_RECEIVER_POLICY, pidR)
    :
}

# Critical edges.
policy_edges() {
    # 12. wrong-type mutation: updateBlocklist(pidA /* an ALLOWLIST */, …)
    #         -> IncompatiblePolicyType()
    # 13. non-admin mutation: updateAllowlist(pidR, …) signed by USER2 (not admin)
    #         -> Unauthorized()
    # 14. zero admin: createPolicy(address(0), ALLOWLIST) -> ZeroAddress()
    # 15. no pending: finalizeUpdateAdmin(pidB) with nothing staged -> NoPendingAdmin()
    # 16. token write-time validation: updatePolicy(TRANSFER_SENDER_POLICY, <unknown id>)
    #         on the token -> PolicyNotFound(id)   (consumer must validate at write time)
    :
}

main() {
    preflight
    log "policy-registry: starting"
    policy_journey
    policy_enforcement
    policy_edges
    log "policy-registry: OK"
}

main "$@"
