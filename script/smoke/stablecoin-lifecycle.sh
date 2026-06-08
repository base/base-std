#!/usr/bin/env bash
# stablecoin-lifecycle.sh — B20 Stablecoin variant smoketest.
#
# STUB: step-level scaffold for scope review. No executable bodies yet.
# Flexes the Stablecoin deltas (fixed 6 decimals, immutable currency) plus the
# regulated-issuer freeze-and-seize path (blocklist + burnBlocked).
#
# Run: RPC_URL=... DEPLOYER_PK=... USER2_PK=... ./stablecoin-lifecycle.sh
#      (or `make smoke-stablecoin`)

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/smoke/smoke-lib.sh
source "$HERE/smoke-lib.sh"

# Golden path.
stablecoin_journey() {
    # Setup. createB20(STABLECOIN, salt_for stablecoin, encode_stablecoin_params(
    #   "USD Coin","USDC",deployer,"USD"), initCalls) where initCalls grants
    #   MINT/BURN/BURN_BLOCKED/PAUSE/UNPAUSE/METADATA to deployer. admin=deployer.
    #   assert isB20Initialized(tok) == true.
    #
    # 1. variant identity: assert currency() == "USD"; assert decimals() == 6
    # 2. mint: mint(alice, 1000e6); assert balanceOf(alice) == 1000e6
    # 3. mint to deployer (500e6) then transfer(bob, 200e6); assert balances
    # 4. freeze setup: pid = createPolicy(deployer, BLOCKLIST);
    #    updatePolicy(TRANSFER_SENDER_POLICY, pid);
    #    updateBlocklist(pid, true, [alice]); assert isAuthorized(pid, alice) == false
    # 5. seize: burnBlocked(alice, 400e6) from deployer (holds BURN_BLOCKED_ROLE)
    #    assert balanceOf(alice) == 600e6; assert totalSupply down by 400e6
    #    assert_log_order tx Transfer BurnedBlocked  (Transfer(alice,0) then BurnedBlocked)
    :
}

# Critical edges.
stablecoin_edges() {
    # 6. seize an unblocked account: burnBlocked(bob, 1) where bob ∉ blocklist
    #        -> AccountNotBlocked(bob)
    # 7. role gate: mint(alice, 1) signed by USER2 (no MINT_ROLE)
    #        -> AccessControlUnauthorizedAccount(user2, MINT_ROLE)
    :
}

main() {
    preflight
    log "stablecoin-lifecycle: starting"
    stablecoin_journey
    stablecoin_edges
    log "stablecoin-lifecycle: OK"
}

main "$@"
