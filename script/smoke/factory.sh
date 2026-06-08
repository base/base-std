#!/usr/bin/env bash
# factory.sh — B20Factory precompile smoketest.
#
# STUB: step-level scaffold for scope review. No executable bodies yet.
# Flexes deterministic creation + address prediction + the variant/identity
# query surface, then the factory's creation-time reverts.
#
# Run: RPC_URL=... DEPLOYER_PK=... USER2_PK=... ./factory.sh   (or `make smoke-factory`)

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/smoke/smoke-lib.sh
source "$HERE/smoke-lib.sh"

# Golden path: deterministic creation + identity queries for both variants.
factory_journey() {
    # 1. predict: addrA = getB20Address(ASSET, deployer, salt_for asset)
    #    assert isB20(addrA) == true (prefix recoverable, no storage read)
    #    assert isB20Initialized(addrA) == false (not created yet)
    # 2. create: tok = createB20(ASSET, salt, encode_asset_params(...), [])
    #    assert tok == addrA (prediction matches actual)
    #    assert isB20Initialized(tok) == true (flips exactly once on completion)
    # 3. predict + create STABLECOIN at salt_for stablecoin
    #    assert returned addr == getB20Address(STABLECOIN, deployer, salt)
    #    assert isB20(addrS) == true
    # 4. assert isB20(some random non-b20 address) == false
    :
}

# Critical edges: creation-time reverts (match the exact selector).
factory_edges() {
    # 5. dup salt: createB20(ASSET, same salt as step 2) -> TokenAlreadyExists(address)
    # 6. decimals out of range: createB20(ASSET, decimals=5)  -> InvalidDecimals(5)
    #                           createB20(ASSET, decimals=19) -> InvalidDecimals(19)
    # 7. bad currency: createB20(STABLECOIN, currency="usd")  -> InvalidCurrency("usd")
    #                  createB20(STABLECOIN, currency="")     -> MissingRequiredField("currency")
    # 8. bad variant: createB20(variant=2, ...)              -> InvalidVariant()
    :
}

main() {
    preflight
    log "factory: starting"
    factory_journey
    factory_edges
    log "factory: OK"
}

main "$@"
