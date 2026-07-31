"""B20 Stablecoin variant smoketest.

The Stablecoin deltas (fixed 6 decimals, immutable currency) plus the
regulated-issuer freeze-and-seize path (blocklist + burnBlocked), then a
flow-level event check.
"""

from __future__ import annotations

from .. import config
from ..abis import STABLECOIN_ABI
from ..chain import Chain, log, step
from ..codec import StablecoinCreateParams, init_call

# `burnBlocked` is a deprecated precompile selector that base-std #186 removed from the IB20
# interface, so it is absent from STABLECOIN_ABI. The selector still dispatches on the precompile
# (retained for back-compat), so bind it via an explicit fragment to keep exercising the legacy
# burn-based freeze-and-seize path. The transfer-based seize surface is covered by the `seize` journey.
_BURN_BLOCKED_FRAGMENT = {
    "type": "function",
    "name": "burnBlocked",
    "stateMutability": "nonpayable",
    "inputs": [{"name": "from", "type": "address"}, {"name": "amount", "type": "uint256"}],
    "outputs": [],
}


def _burn_blocked_at(c: Chain, tok):
    """A token binding including the deprecated `burnBlocked` selector (absent from STABLECOIN_ABI)."""
    return c.w3.eth.contract(address=tok.address, abi=[*STABLECOIN_ABI, _BURN_BLOCKED_FRAGMENT])


def _setup(c: Chain):
    salt = c.cfg.salt_for("stablecoin")
    params = StablecoinCreateParams("USD Coin", "USDC", c.DEPLOYER, "USD").encode()
    roles = [
        config.MINT_ROLE,
        config.BURN_ROLE,
        config.BURN_BLOCKED_ROLE,
        config.PAUSE_ROLE,
        config.UNPAUSE_ROLE,
        config.METADATA_ROLE,
    ]
    init_calls = [init_call(c.stablecoin_abi, "grantRole", r, c.DEPLOYER) for r in roles]

    step("setup", "create STABLECOIN token (admin=deployer, currency=USD, roles -> deployer)")
    tok_addr = c.predict_b20(config.VARIANT_STABLECOIN, salt)
    c.create_b20(config.VARIANT_STABLECOIN, salt, params, init_calls)
    tok = c.stablecoin_at(tok_addr)
    c.assert_eq(c.factory.functions.isB20Initialized(tok_addr).call(), True, "token initialized")
    return tok


def _journey(c: Chain, tok) -> None:
    step(1, "variant identity: currency == USD, decimals == 6")
    c.assert_eq(tok.functions.currency().call(), "USD", "currency() == USD")
    c.assert_eq(tok.functions.decimals().call(), config.STABLECOIN_DECIMALS, f"decimals == {config.STABLECOIN_DECIMALS}")

    step(2, "mint(alice, 1000)")
    c.send(tok.functions.mint(c.ALICE, config.amt(1000, 6)), c.deployer)
    c.assert_eq(tok.functions.balanceOf(c.ALICE).call(), config.amt(1000, 6), "alice balance")

    step(3, "mint(deployer, 500); transfer(bob, 200)")
    c.send(tok.functions.mint(c.DEPLOYER, config.amt(500, 6)), c.deployer)
    c.send(tok.functions.transfer(c.BOB, config.amt(200, 6)), c.deployer)
    c.assert_eq(tok.functions.balanceOf(c.BOB).call(), config.amt(200, 6), "bob balance")
    c.assert_eq(tok.functions.balanceOf(c.DEPLOYER).call(), config.amt(300, 6), "deployer balance")

    step(4, "freeze setup: blocklist policy on TRANSFER_SENDER_POLICY, block alice")
    pid = c.create_policy(c.DEPLOYER, config.POLICY_TYPE_BLOCKLIST)
    c.send(tok.functions.updatePolicy(config.TRANSFER_SENDER_POLICY, pid), c.deployer)
    c.send(c.policy.functions.updateBlocklist(pid, True, [c.ALICE]), c.deployer)
    c.assert_eq(c.policy.functions.isAuthorized(pid, c.ALICE).call(), False, "alice blocked")

    step(5, "seize: burnBlocked(alice, 400); Transfer then BurnedBlocked")
    receipt = c.send(_burn_blocked_at(c, tok).functions.burnBlocked(c.ALICE, config.amt(400, 6)), c.deployer)
    c.assert_eq(tok.functions.balanceOf(c.ALICE).call(), config.amt(600, 6), "alice balance after seize")
    c.assert_eq(tok.functions.totalSupply().call(), config.amt(1100, 6), "total supply after seize")
    c.assert_log_order(
        receipt,
        "Transfer(address,address,uint256)",
        "BurnedBlocked(address,address,uint256)",
        "BurnedBlocked immediately follows Transfer",
    )


def _edges(c: Chain, tok) -> None:
    step(6, "seize an unblocked account -> AccountNotBlocked")
    c.expect_revert("AccountNotBlocked", _burn_blocked_at(c, tok).functions.burnBlocked(c.BOB, 1), c.DEPLOYER)

    step(7, "role gate: user2 mint -> AccessControlUnauthorizedAccount")
    c.expect_revert("AccessControlUnauthorizedAccount", tok.functions.mint(c.ALICE, 1), c.USER2)


def _events(c: Chain) -> None:
    step(8, "expected events emitted across the flow")
    c.assert_events_emitted(
        "stablecoin events",
        "B20Created(address,uint8,string,string,uint8,bytes)",
        "RoleGranted(bytes32,address,address)",
        "Transfer(address,address,uint256)",
        "BurnedBlocked(address,address,uint256)",
        "PolicyCreated(uint64,address,uint8)",
        "BlocklistUpdated(uint64,address,bool,address[])",
        "PolicyUpdated(bytes32,uint64,uint64)",
    )


def run(c: Chain) -> None:
    log("stablecoin-lifecycle: starting")
    tok = _setup(c)
    _journey(c, tok)
    _edges(c, tok)
    _events(c)
    log("stablecoin-lifecycle: OK")
