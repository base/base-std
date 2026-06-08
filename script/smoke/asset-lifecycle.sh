#!/usr/bin/env bash
# asset-lifecycle.sh — B20 Asset variant smoketest.
#
# STUB: step-level scaffold for scope review. No executable bodies yet.
# Flexes the full operator lifecycle of an Asset token (decimals 18): issuance,
# transfers + memo, delegated spend, announcements (batchMint + rebase), metadata,
# burn — then the gates that must reject (cap, pause, role, announce-id reuse).
#
# Run: RPC_URL=... DEPLOYER_PK=... USER2_PK=... ./asset-lifecycle.sh
#      (or `make smoke-asset`)

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/smoke/smoke-lib.sh
source "$HERE/smoke-lib.sh"

# Golden path.
asset_journey() {
    # Setup. createB20(ASSET, salt_for asset, params, initCalls) where initCalls
    #   bundles (via encode_init_calls): grantRole(MINT/BURN/BURN_BLOCKED/PAUSE/
    #   UNPAUSE/METADATA/OPERATOR, deployer) + updateSupplyCap(CAP). admin=deployer,
    #   decimals=ASSET_DECIMALS. Policies stay ALWAYS_ALLOW (default).
    #   assert isB20Initialized(tok) == true; assert decimals() == 18.
    #
    # 1. mint: mint(alice, 1000e18)
    #    assert balanceOf(alice) == 1000e18; assert totalSupply() == 1000e18
    # 2. mint to deployer (so it can send): mint(deployer, 500e18)
    # 3. transfer: transfer(bob, 200e18) from deployer
    #    assert balanceOf(bob) == 200e18; assert balanceOf(deployer) == 300e18
    # 4. transferWithMemo: transferWithMemo(bob, 1e18, memo) from deployer
    #    assert_log_order tx Transfer Memo  (Memo immediately follows Transfer)
    # 5. delegated spend (distinct executor): approve(user2, 50e18) from deployer;
    #    fund_user2; transferFrom(deployer, bob, 50e18) signed by USER2
    #    assert allowance(deployer, user2) == 0; assert balances moved
    # 6. announce + batchMint: announce(internalCalls=[call_batch_mint([alice,bob],
    #    [10e18,20e18])], id="smoke-batch-1", desc, uri) from deployer
    #    assert Announcement→EndAnnouncement bracket for the id;
    #    assert isAnnouncementIdUsed("smoke-batch-1") == true; assert balances
    # 7. announce + rebase: announce([call_update_multiplier(2e18)], id="smoke-rebase-1", …)
    #    assert multiplier() == 2e18; assert scaledBalanceOf(alice) == 2 * balanceOf(alice)
    #    assert toRawBalance(toScaledBalance(x)) within 1 ULP of x
    # 8. extra metadata: updateExtraMetadata("category","rwa")
    #    assert extraMetadata("category") == "rwa";
    #    then updateExtraMetadata("category","")  -> assert extraMetadata == ""
    # 9. metadata: updateName("Asset Two"); assert name() == "Asset Two"
    #    updateSymbol("AST2"); assert symbol() == "AST2"
    # 10. burn: burn(100e18) from deployer; assert totalSupply() down by 100e18
    :
}

# Critical edges.
asset_edges() {
    # 11. supply cap: mint(alice, CAP - totalSupply + 1) -> SupplyCapExceeded(cap,attempted)
    # 12. pause: pause([TRANSFER]); assert isPaused(TRANSFER) == true
    #     transfer(bob, 1) -> ContractPaused(TRANSFER)
    #     unpause([TRANSFER]) to restore; assert transfer(bob,1) succeeds again
    # 13. role gate: mint(alice, 1) signed by USER2 (no MINT_ROLE)
    #         -> AccessControlUnauthorizedAccount(user2, MINT_ROLE)
    # 14. announce id reuse: announce([], id="smoke-batch-1", …) -> AnnouncementIdAlreadyUsed
    :
}

main() {
    preflight
    log "asset-lifecycle: starting"
    asset_journey
    asset_edges
    log "asset-lifecycle: OK"
}

main "$@"
