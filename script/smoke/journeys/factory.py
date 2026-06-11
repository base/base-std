"""B20Factory precompile smoketest.

Deterministic creation + address prediction + the variant/identity query
surface, then the factory's creation-time reverts, then a flow-level event
check.
"""

from __future__ import annotations

from .. import config
from ..chain import Chain, log, ok, step
from ..codec import AssetCreateParams, StablecoinCreateParams

DEAD = "0x000000000000000000000000000000000000dEaD"


def _journey(c: Chain) -> None:
    salt_a = c.cfg.salt_for("factory-asset")
    params_a = AssetCreateParams("Factory Asset", "FAST", c.DEPLOYER, config.ASSET_DECIMALS).encode()

    step(1, "predict ASSET address; isB20 true, isB20Initialized false (pre-create)")
    addr_a = c.predict_b20(config.VARIANT_ASSET, salt_a)
    c.assert_eq(c.factory.functions.isB20(addr_a).call(), True, "isB20(predicted) == true")
    c.assert_eq(c.factory.functions.isB20Initialized(addr_a).call(), False, "isB20Initialized == false pre-create")

    step(2, "create ASSET; prediction matches, isB20Initialized flips true")
    c.create_b20(config.VARIANT_ASSET, salt_a, params_a, [])
    c.assert_eq(c.predict_b20(config.VARIANT_ASSET, salt_a), addr_a, "address prediction is stable")
    c.assert_eq(c.factory.functions.isB20Initialized(addr_a).call(), True, "isB20Initialized == true post-create")

    salt_s = c.cfg.salt_for("factory-stablecoin")
    params_s = StablecoinCreateParams("Factory USD", "FUSD", c.DEPLOYER, "USD").encode()

    step(3, "predict + create STABLECOIN; isB20 true")
    addr_s = c.predict_b20(config.VARIANT_STABLECOIN, salt_s)
    c.create_b20(config.VARIANT_STABLECOIN, salt_s, params_s, [])
    c.assert_eq(c.predict_b20(config.VARIANT_STABLECOIN, salt_s), addr_s, "stablecoin prediction is stable")
    c.assert_eq(c.factory.functions.isB20(addr_s).call(), True, "isB20(stablecoin) == true")

    step(4, "non-b20 address reads false")
    c.assert_eq(c.factory.functions.isB20(c.w3.to_checksum_address(DEAD)).call(), False, "isB20(non-b20) == false")


def _edges(c: Chain) -> None:
    params_a = AssetCreateParams("Factory Asset", "FAST", c.DEPLOYER, config.ASSET_DECIMALS).encode()
    params_bad5 = AssetCreateParams("Bad", "BAD", c.DEPLOYER, 5).encode()
    params_bad19 = AssetCreateParams("Bad", "BAD", c.DEPLOYER, 19).encode()
    params_lower_ccy = StablecoinCreateParams("Lower", "LOW", c.DEPLOYER, "usd").encode()
    params_empty_ccy = StablecoinCreateParams("Empty", "EMP", c.DEPLOYER, "").encode()

    def create(variant, journey, params):
        return c.create_b20_fn(variant, c.cfg.salt_for(journey), params, [])

    step(5, "duplicate salt -> TokenAlreadyExists")
    c.expect_revert("TokenAlreadyExists", create(config.VARIANT_ASSET, "factory-asset", params_a), c.DEPLOYER)

    step(6, "decimals out of range -> InvalidDecimals")
    c.expect_revert("InvalidDecimals", create(config.VARIANT_ASSET, "factory-d5", params_bad5), c.DEPLOYER)
    c.expect_revert("InvalidDecimals", create(config.VARIANT_ASSET, "factory-d19", params_bad19), c.DEPLOYER)

    step(7, "bad currency -> InvalidCurrency / MissingRequiredField")
    c.expect_revert("InvalidCurrency", create(config.VARIANT_STABLECOIN, "factory-lc", params_lower_ccy), c.DEPLOYER)
    c.expect_revert("MissingRequiredField", create(config.VARIANT_STABLECOIN, "factory-ec", params_empty_ccy), c.DEPLOYER)

    step(8, "out-of-range variant -> ABI decode failure")
    c.expect_abi_decode_failed(
        "out-of-range variant AbiDecodeFailed",
        create(2, "factory-bv", params_a),
        c.DEPLOYER,
    )


def _events(c: Chain) -> None:
    step(9, "expected events emitted across the flow")
    c.assert_events_emitted("factory events", "B20Created(address,uint8,string,string,uint8,bytes)")


def run(c: Chain) -> None:
    log("factory: starting")
    _journey(c)
    _edges(c)
    _events(c)
    log("factory: OK")
