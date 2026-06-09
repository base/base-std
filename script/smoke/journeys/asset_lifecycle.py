"""B20 Asset variant smoketest.

Full operator lifecycle of an Asset token (decimals 18): issuance, transfers +
memo, delegated spend, announcements (batchMint + rebase), metadata, burn — then
the gates that must reject (cap, pause, role, announce-id reuse) — then a
flow-level event check.
"""

from __future__ import annotations

from .. import config
from ..chain import Chain, die, log, ok, step
from ..codec import AssetCreateParams, init_call

MEMO = b"smoke".ljust(32, b"\x00")


def _setup(c: Chain):
    salt = c.cfg.salt_for("asset")
    params = AssetCreateParams("Asset One", "AST", c.DEPLOYER, config.ASSET_DECIMALS).encode()
    cap = config.amt(1_000_000_000, 18)
    roles = [
        config.MINT_ROLE,
        config.BURN_ROLE,
        config.BURN_BLOCKED_ROLE,
        config.PAUSE_ROLE,
        config.UNPAUSE_ROLE,
        config.METADATA_ROLE,
        config.OPERATOR_ROLE,
    ]
    init_calls = [init_call(c.asset_abi, "grantRole", r, c.DEPLOYER) for r in roles]
    init_calls.append(init_call(c.asset_abi, "updateSupplyCap", cap))

    step("setup", f"create ASSET token (admin=deployer, decimals={config.ASSET_DECIMALS}, all roles -> deployer)")
    tok_addr = c.predict_b20(config.VARIANT_ASSET, salt)
    c.create_b20(config.VARIANT_ASSET, salt, params, init_calls)
    tok = c.asset_at(tok_addr)
    c.assert_eq(c.factory.functions.isB20Initialized(tok_addr).call(), True, "token initialized")
    c.assert_eq(tok.functions.decimals().call(), config.ASSET_DECIMALS, f"decimals == {config.ASSET_DECIMALS}")
    return tok


def _journey(c: Chain, tok) -> None:
    step(1, "mint(alice, 1000)")
    c.send(tok.functions.mint(c.ALICE, config.amt(1000, 18)), c.deployer)
    c.assert_eq(tok.functions.balanceOf(c.ALICE).call(), config.amt(1000, 18), "alice balance")
    c.assert_eq(tok.functions.totalSupply().call(), config.amt(1000, 18), "total supply")

    step(2, "mint(deployer, 500)")
    c.send(tok.functions.mint(c.DEPLOYER, config.amt(500, 18)), c.deployer)

    step(3, "transfer(bob, 200) from deployer")
    c.send(tok.functions.transfer(c.BOB, config.amt(200, 18)), c.deployer)
    c.assert_eq(tok.functions.balanceOf(c.BOB).call(), config.amt(200, 18), "bob balance")
    c.assert_eq(tok.functions.balanceOf(c.DEPLOYER).call(), config.amt(300, 18), "deployer balance")

    step(4, "transferWithMemo(bob, 1) from deployer; Memo follows Transfer")
    receipt = c.send(tok.functions.transferWithMemo(c.BOB, config.amt(1, 18), MEMO), c.deployer)
    c.assert_log_order(
        receipt, "Transfer(address,address,uint256)", "Memo(address,bytes32)", "Memo immediately follows Transfer"
    )

    step(5, "delegated spend: approve(user2,50) then user2 transferFrom(deployer,bob,50)")
    c.send(tok.functions.approve(c.USER2, config.amt(50, 18)), c.deployer)
    c.fund_user2()
    c.send(tok.functions.transferFrom(c.DEPLOYER, c.BOB, config.amt(50, 18)), c.user2)
    c.assert_eq(tok.functions.allowance(c.DEPLOYER, c.USER2).call(), 0, "allowance consumed")
    c.assert_eq(tok.functions.balanceOf(c.BOB).call(), config.amt(251, 18), "bob balance after delegated spend")

    step(6, "announce + batchMint([alice:10, bob:20])")
    batch = init_call(c.asset_abi, "batchMint", [c.ALICE, c.BOB], [config.amt(10, 18), config.amt(20, 18)])
    c.send(
        tok.functions.announce([batch], "smoke-batch-1", "batch issuance", "ipfs://smoke/batch-1"),
        c.deployer,
    )
    c.assert_eq(tok.functions.isAnnouncementIdUsed("smoke-batch-1").call(), True, "announcement id consumed")
    c.assert_eq(tok.functions.balanceOf(c.ALICE).call(), config.amt(1010, 18), "alice balance after batch")
    c.assert_eq(tok.functions.balanceOf(c.BOB).call(), config.amt(271, 18), "bob balance after batch")

    step(7, "announce + rebase: updateMultiplier(2e18); scaled view doubles")
    rebase = init_call(c.asset_abi, "updateMultiplier", config.amt(2, 18))
    c.send(tok.functions.announce([rebase], "smoke-rebase-1", "2x rebase", "ipfs://smoke/rebase-1"), c.deployer)
    c.assert_eq(tok.functions.multiplier().call(), config.amt(2, 18), "multiplier == 2e18")
    raw = tok.functions.balanceOf(c.ALICE).call()
    scaled = tok.functions.scaledBalanceOf(c.ALICE).call()
    c.assert_eq(scaled, raw * 2, "scaledBalanceOf(alice) == 2 * balanceOf(alice)")

    step("7b", "round-trip toRawBalance(toScaledBalance(x)) within 1 ULP of x")
    x = config.amt(12345, 18)
    rt = tok.functions.toRawBalance(tok.functions.toScaledBalance(x).call()).call()
    if abs(x - rt) > 1:
        die(f"round-trip drift > 1 ULP: x={x} rt={rt}")
    ok("round-trip within 1 ULP")

    step(8, "extra metadata set then remove")
    c.send(tok.functions.updateExtraMetadata("category", "rwa"), c.deployer)
    c.assert_eq(tok.functions.extraMetadata("category").call(), "rwa", "extraMetadata set")
    c.send(tok.functions.updateExtraMetadata("category", ""), c.deployer)
    c.assert_eq(tok.functions.extraMetadata("category").call(), "", "extraMetadata removed")

    step(9, "metadata: updateName / updateSymbol")
    c.send(tok.functions.updateName("Asset Two"), c.deployer)
    c.assert_eq(tok.functions.name().call(), "Asset Two", "name updated")
    c.send(tok.functions.updateSymbol("AST2"), c.deployer)
    c.assert_eq(tok.functions.symbol().call(), "AST2", "symbol updated")

    step(10, "burn(100) from deployer")
    c.send(tok.functions.burn(config.amt(100, 18)), c.deployer)
    c.assert_eq(tok.functions.totalSupply().call(), config.amt(1430, 18), "total supply after burn")


def _edges(c: Chain, tok) -> None:
    step(11, "supply cap: lower cap to current supply, then mint 1 -> SupplyCapExceeded")
    total = tok.functions.totalSupply().call()
    c.send(tok.functions.updateSupplyCap(total), c.deployer)
    c.expect_revert("SupplyCapExceeded", tok.functions.mint(c.ALICE, 1), c.DEPLOYER)

    step("11b", "transfer insufficient balance -> InsufficientBalance (user2 holds 0 tokens)")
    c.expect_revert("InsufficientBalance", tok.functions.transfer(c.BOB, config.amt(1, 18)), c.USER2)

    step("11c", "transferFrom insufficient allowance -> InsufficientAllowance (allowance consumed in step 5)")
    c.expect_revert("InsufficientAllowance", tok.functions.transferFrom(c.DEPLOYER, c.BOB, config.amt(1, 18)), c.USER2)

    step(12, "pause TRANSFER: transfer AND transferFrom revert ContractPaused; unpause restores")
    # Approve user2 first so transferFrom clears the allowance check and the pause gate is the binding revert.
    c.send(tok.functions.approve(c.USER2, config.amt(5, 18)), c.deployer)
    c.send(tok.functions.pause([config.FEATURE_TRANSFER]), c.deployer)
    c.assert_eq(tok.functions.isPaused(config.FEATURE_TRANSFER).call(), True, "TRANSFER paused")
    c.expect_revert("ContractPaused", tok.functions.transfer(c.BOB, 1), c.DEPLOYER)
    c.expect_revert("ContractPaused", tok.functions.transferFrom(c.DEPLOYER, c.BOB, config.amt(1, 18)), c.USER2)
    c.send(tok.functions.unpause([config.FEATURE_TRANSFER]), c.deployer)
    c.assert_eq(tok.functions.isPaused(config.FEATURE_TRANSFER).call(), False, "TRANSFER unpaused")
    c.send(tok.functions.transfer(c.BOB, config.amt(1, 18)), c.deployer)
    c.assert_eq(tok.functions.balanceOf(c.BOB).call(), config.amt(272, 18), "transfer works again after unpause")

    step(13, "role gate: user2 mint -> AccessControlUnauthorizedAccount")
    c.expect_revert("AccessControlUnauthorizedAccount", tok.functions.mint(c.ALICE, 1), c.USER2)

    step(14, "announce id reuse -> AnnouncementIdAlreadyUsed")
    reuse = tok.functions.announce([], "smoke-batch-1", "dup", "ipfs://smoke/dup")
    c.expect_revert("AnnouncementIdAlreadyUsed", reuse, c.DEPLOYER)


def _events(c: Chain) -> None:
    step(15, "expected events emitted across the flow")
    c.assert_events_emitted(
        "asset events",
        "B20Created(address,uint8,string,string,uint8,bytes)",
        "RoleGranted(bytes32,address,address)",
        "SupplyCapUpdated(address,uint256,uint256)",
        "Transfer(address,address,uint256)",
        "Memo(address,bytes32)",
        "Approval(address,address,uint256)",
        "Announcement(address,string,string,string)",
        "EndAnnouncement(string)",
        "MultiplierUpdated(uint256)",
        "ExtraMetadataUpdated(string,string)",
        "NameUpdated(address,string)",
        "SymbolUpdated(address,string)",
        "Paused(address,uint8[])",
        "Unpaused(address,uint8[])",
    )


def run(c: Chain) -> None:
    log("asset-lifecycle: starting")
    tok = _setup(c)
    _journey(c, tok)
    _edges(c, tok)
    _events(c)
    log("asset-lifecycle: OK")
