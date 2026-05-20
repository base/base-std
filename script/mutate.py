#!/usr/bin/env python3
"""Hand-rolled mutation testing for MockB20 / MockTokenFactory.

For each mutation: back up the file, apply a single substitution, run forge test,
record pass/fail, restore the backup. A mutation that "survives" (all tests pass
after the mutation) reveals a gap in the test suite -- the impl can be silently
broken in that specific way without any test failing.

The mutations below are hand-picked to represent realistic bug classes:
- inverted authorization checks
- off-by-one boundary errors
- skipped policy / pause / role guards
- wrong default values
"""

import json
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

MOCK_B20 = REPO / "test/lib/mocks/MockB20.sol"
MOCK_FACTORY = REPO / "test/lib/mocks/MockTokenFactory.sol"


@dataclass
class Mutation:
    file: Path
    old: str
    new: str
    description: str


MUTATIONS: list[Mutation] = [
    # === MockB20: _isPrivileged ===
    Mutation(
        MOCK_B20,
        "return msg.sender == FACTORY && !MockB20Storage.layout().initialized;",
        "return msg.sender != FACTORY && !MockB20Storage.layout().initialized;",
        "_isPrivileged: flip sender check (factory becomes ineligible for bootstrap bypass)",
    ),
    Mutation(
        MOCK_B20,
        "return msg.sender == FACTORY && !MockB20Storage.layout().initialized;",
        "return msg.sender == FACTORY && MockB20Storage.layout().initialized;",
        "_isPrivileged: flip initialized check (factory permanently privileged after bootstrap)",
    ),
    Mutation(
        MOCK_B20,
        "return msg.sender == FACTORY && !MockB20Storage.layout().initialized;",
        "return msg.sender == FACTORY || !MockB20Storage.layout().initialized;",
        "_isPrivileged: AND -> OR (any caller privileged during bootstrap window)",
    ),
    # === MockB20: pause gate in _transfer ===
    Mutation(
        MOCK_B20,
        "if (_isPaused(PausableFeature.TRANSFER)) revert ContractPaused(PausableFeature.TRANSFER);",
        "if (!_isPaused(PausableFeature.TRANSFER)) revert ContractPaused(PausableFeature.TRANSFER);",
        "_transfer: invert pause check (paused transfers succeed, unpaused revert)",
    ),
    # === MockB20: role check in _mint ===
    Mutation(
        MOCK_B20,
        "if (!hasRole(MINT_ROLE, msg.sender)) revert AccessControlUnauthorizedAccount(msg.sender, MINT_ROLE);",
        "if (hasRole(MINT_ROLE, msg.sender)) revert AccessControlUnauthorizedAccount(msg.sender, MINT_ROLE);",
        "_mint: invert role check (only non-MINT_ROLE callers can mint)",
    ),
    # === MockB20: supply cap off-by-one ===
    Mutation(
        MOCK_B20,
        "if (newSupply > $.supplyCap) revert SupplyCapExceeded($.supplyCap, newSupply);",
        "if (newSupply >= $.supplyCap) revert SupplyCapExceeded($.supplyCap, newSupply);",
        "_mint: supply cap off-by-one (> becomes >=, can't mint exactly to cap)",
    ),
    # === MockB20: balance check off-by-one (_transfer specifically) ===
    Mutation(
        MOCK_B20,
        "        uint256 fromBalance = $.balances[from];\n        if (fromBalance < amount) revert InsufficientBalance(from, fromBalance, amount);\n        unchecked {\n            $.balances[from] = fromBalance - amount;\n            $.balances[to] += amount;",
        "        uint256 fromBalance = $.balances[from];\n        if (fromBalance <= amount) revert InsufficientBalance(from, fromBalance, amount);\n        unchecked {\n            $.balances[from] = fromBalance - amount;\n            $.balances[to] += amount;",
        "_transfer: balance check off-by-one (< becomes <=, can't transfer exact balance)",
    ),
    # === MockB20: balance check off-by-one (_burnRaw specifically) ===
    Mutation(
        MOCK_B20,
        "        uint256 fromBalance = $.balances[from];\n        if (fromBalance < amount) revert InsufficientBalance(from, fromBalance, amount);\n        unchecked {\n            $.balances[from] = fromBalance - amount;\n            $.totalSupply -= amount;",
        "        uint256 fromBalance = $.balances[from];\n        if (fromBalance <= amount) revert InsufficientBalance(from, fromBalance, amount);\n        unchecked {\n            $.balances[from] = fromBalance - amount;\n            $.totalSupply -= amount;",
        "_burnRaw: balance check off-by-one (< becomes <=, can't burn exact balance)",
    ),
    # === MockB20: allowance check off-by-one ===
    Mutation(
        MOCK_B20,
        "if (current < amount) revert InsufficientAllowance(spender, current, amount);",
        "if (current <= amount) revert InsufficientAllowance(spender, current, amount);",
        "_consumeAllowance: off-by-one (< becomes <=, can't spend exact allowance)",
    ),
    # === MockB20: skip policy check on sender (matches new inline pattern) ===
    Mutation(
        MOCK_B20,
        "            if (!IPolicyRegistry(POLICY_REGISTRY).isAuthorized(senderPolicyId, from)) {\n                revert PolicyForbids(TRANSFER_SENDER, senderPolicyId);\n            }",
        "            // sender policy check elided\n            if (false) revert PolicyForbids(TRANSFER_SENDER, senderPolicyId);",
        "_transfer: drop TRANSFER_SENDER policy check entirely",
    ),
    # === MockB20: skip policy check on receiver (matches new inline pattern) ===
    Mutation(
        MOCK_B20,
        "            if (!IPolicyRegistry(POLICY_REGISTRY).isAuthorized(receiverPolicyId, to)) {\n                revert PolicyForbids(TRANSFER_RECEIVER, receiverPolicyId);\n            }",
        "            // receiver policy check elided\n            if (false) revert PolicyForbids(TRANSFER_RECEIVER, receiverPolicyId);",
        "_transfer: drop TRANSFER_RECEIVER policy check entirely",
    ),
    # === MockB20: skip MINT_RECEIVER policy check (matches new inline pattern) ===
    Mutation(
        MOCK_B20,
        "            if (!IPolicyRegistry(POLICY_REGISTRY).isAuthorized(mintReceiverPolicyId, to)) {\n                revert PolicyForbids(MINT_RECEIVER, mintReceiverPolicyId);\n            }",
        "            // mint receiver policy check elided\n            if (false) revert PolicyForbids(MINT_RECEIVER, mintReceiverPolicyId);",
        "_mint: drop MINT_RECEIVER policy check entirely",
    ),
    # === MockB20: lastAdmin guard off-by-one ===
    Mutation(
        MOCK_B20,
        "if (role == DEFAULT_ADMIN_ROLE && MockB20Storage.layout().adminCount == 1) {",
        "if (role == DEFAULT_ADMIN_ROLE && MockB20Storage.layout().adminCount == 2) {",
        "renounceRole: last-admin guard off-by-one (trips at count=2 instead of count=1)",
    ),
    # === MockB20: adminCount underflow (wrong direction) ===
    Mutation(
        MOCK_B20,
        "if (role == DEFAULT_ADMIN_ROLE) $.adminCount -= 1;",
        "if (role == DEFAULT_ADMIN_ROLE) $.adminCount += 1;",
        "_revokeRole: adminCount goes the wrong direction (increments instead of decrements)",
    ),
    # === MockB20: spender check skipped in approve ===
    Mutation(
        MOCK_B20,
        "if (spender == address(0)) revert InvalidSpender(spender);",
        "// if (spender == address(0)) revert InvalidSpender(spender);",
        "approve: drop zero-spender guard",
    ),
    # === MockB20: zero-receiver check skipped in _transfer specifically ===
    Mutation(
        MOCK_B20,
        "    function _transfer(address from, address to, uint256 amount) internal {\n        if (to == address(0)) revert InvalidReceiver(to);",
        "    function _transfer(address from, address to, uint256 amount) internal {\n        // if (to == address(0)) revert InvalidReceiver(to);",
        "_transfer: drop zero-recipient guard",
    ),
    # === MockB20: more mutations on accounting / event integrity ===
    Mutation(
        MOCK_B20,
        "$.totalSupply -= amount;",
        "$.totalSupply += amount;",
        "_burnRaw: totalSupply goes wrong direction (burns INCREASE supply)",
    ),
    Mutation(
        MOCK_B20,
        "emit Transfer(from, to, amount);",
        "emit Transfer(to, from, amount);",
        "_transfer: Transfer event has from/to swapped",
    ),
    Mutation(
        MOCK_B20,
        "emit Transfer(address(0), to, amount);",
        "emit Transfer(to, address(0), amount);",
        "_mint: emits Transfer(to, 0) instead of Transfer(0, to) (looks like burn)",
    ),
    Mutation(
        MOCK_B20,
        "if (current != type(uint256).max) {",
        "if (current == type(uint256).max) {",
        "_consumeAllowance: inverted infinite-allowance check (max is the only finite path)",
    ),
    # === MockB20: permit ===
    Mutation(
        MOCK_B20,
        "$.nonces[owner] = nonce + 1;",
        "$.nonces[owner] = nonce;",
        "permit: skips nonce increment (replay attacks possible)",
    ),
    Mutation(
        MOCK_B20,
        "if (recovered == address(0) || recovered != owner) {",
        "if (recovered == address(0) && recovered != owner) {",
        "permit: OR -> AND (accepts signatures recovering to non-owner non-zero)",
    ),
    Mutation(
        MOCK_B20,
        "$.allowances[owner][spender] = value;\n        emit Approval(owner, spender, value);",
        "$.allowances[owner][spender] += value;\n        emit Approval(owner, spender, value);",
        "permit: allowance is additive instead of replace",
    ),
    # === MockTokenFactory: skip initial admin grant ===
    Mutation(
        MOCK_FACTORY,
        "if (admin != address(0)) {",
        "if (admin == address(0)) {",
        "_writeBaseStorage: invert admin-grant condition (grants admin role only when zero)",
    ),
    # === MockTokenFactory: skip the closeBootstrap step ===
    Mutation(
        MOCK_FACTORY,
        "_writeBool(token, MockB20Storage.slotOf(MockB20Storage.INITIALIZED_OFFSET), true);",
        "// _writeBool(token, MockB20Storage.slotOf(MockB20Storage.INITIALIZED_OFFSET), true);",
        "createToken: never closes the bootstrap window (factory remains permanently privileged)",
    ),
    # === MockTokenFactory: wrong supply cap default ===
    Mutation(
        MOCK_FACTORY,
        "_writeUint(token, MockB20Storage.slotOf(MockB20Storage.SUPPLY_CAP_OFFSET), type(uint256).max);",
        "_writeUint(token, MockB20Storage.slotOf(MockB20Storage.SUPPLY_CAP_OFFSET), 0);",
        "_writeBaseStorage: initial supply cap is 0 instead of unbounded",
    ),
    # === Address derivation in _computeAddress ===
    Mutation(
        MOCK_FACTORY,
        "(uint160(uint8(variant)) << 72)",
        "(uint160(uint8(variant)) << 80)",
        "_computeAddress: variant byte shifted to wrong position (overlaps prefix zeros)",
    ),
    Mutation(
        MOCK_FACTORY,
        "(uint160(decimals) << 64)",
        "(uint160(decimals) << 56)",
        "_computeAddress: decimals byte shifted to wrong position (overlaps tail bytes)",
    ),
    Mutation(
        MOCK_FACTORY,
        "uint160 addr = (uint160(0xB2) << 152)",
        "uint160 addr = (uint160(0xB3) << 152)",
        "_computeAddress: prefix byte changed from 0xB2 to 0xB3 (breaks isB20 prefix check)",
    ),
    Mutation(
        MOCK_FACTORY,
        "bytes8 tail = bytes8(keccak256(abi.encode(sender, salt)));",
        "bytes8 tail = bytes8(keccak256(abi.encodePacked(sender, salt)));",
        "_computeAddress: encode vs encodePacked (different hash, breaks determinism contract)",
    ),
    # === Address prefix check ===
    Mutation(
        MOCK_FACTORY,
        "return (uint160(token) >> 80) == (uint160(0xB2) << 72);",
        "return (uint160(token) >> 80) == (uint160(0xB3) << 72);",
        "_isB20Prefix: compares against wrong prefix byte (no real B-20 ever matches)",
    ),
    Mutation(
        MOCK_FACTORY,
        "return (uint160(token) >> 80) == (uint160(0xB2) << 72);",
        "return (uint160(token) >> 88) == (uint160(0xB2) << 72);",
        "_isB20Prefix: wrong shift amount (compares wrong byte range)",
    ),
    # === String encoding short/long boundary ===
    Mutation(
        MOCK_FACTORY,
        "if (data.length < 32) {",
        "if (data.length <= 32) {",
        "_writeString: short/long boundary off-by-one (32-byte strings get short encoding -> data lost)",
    ),
    Mutation(
        MOCK_FACTORY,
        "vm.store(target, slot, bytes32(data.length * 2 + 1));",
        "vm.store(target, slot, bytes32(data.length * 2));",
        "_writeString: long-string marker missing low bit (string read as short -> garbage)",
    ),
    Mutation(
        MOCK_FACTORY,
        "uint256 chunks = (data.length + 31) / 32;",
        "uint256 chunks = (data.length + 30) / 32;",
        "_writeString: chunk count off-by-one (loses trailing bytes for non-aligned lengths)",
    ),
    # === Factory decimals validation boundaries ===
    Mutation(
        MOCK_FACTORY,
        "if (p.decimals < 2 || p.decimals > 18) revert InvalidDecimals(p.decimals);",
        "if (p.decimals <= 2 || p.decimals > 18) revert InvalidDecimals(p.decimals);",
        "createToken: rejects decimals == 2 (lower bound off-by-one)",
    ),
    Mutation(
        MOCK_FACTORY,
        "if (p.decimals < 2 || p.decimals > 18) revert InvalidDecimals(p.decimals);",
        "if (p.decimals < 2 || p.decimals >= 18) revert InvalidDecimals(p.decimals);",
        "createToken: rejects decimals == 18 (upper bound off-by-one)",
    ),
    # === Factory TokenAlreadyExists check ===
    Mutation(
        MOCK_FACTORY,
        "if (token.code.length != 0) revert TokenAlreadyExists(token);",
        "if (token.code.length == 0) revert TokenAlreadyExists(token);",
        "createToken: TokenAlreadyExists check inverted (always reverts for new tokens)",
    ),
    # === Pause vector bitmask ===
    Mutation(
        MOCK_B20,
        "return ((MockB20Storage.layout().pausedVectors >> uint8(feature)) & uint256(1)) == 1;",
        "return ((MockB20Storage.layout().pausedVectors << uint8(feature)) & uint256(1)) == 1;",
        "_isPaused: shift direction reversed (wrong bits inspected)",
    ),
    Mutation(
        MOCK_B20,
        "$.pausedVectors |= uint256(1) << uint8(features[i]);",
        "$.pausedVectors |= uint256(1) << uint8(features[i] + 1);",
        "pause: writes to wrong bit (off-by-one PausableFeature index)",
    ),
    # === Pausable feature loop bounds (pausedFeatures view) ===
    Mutation(
        MOCK_B20,
        "for (uint256 i = 0; i < 4; i++) {\n            if (((vectors >> i) & uint256(1)) == 1) count++;",
        "for (uint256 i = 0; i < 3; i++) {\n            if (((vectors >> i) & uint256(1)) == 1) count++;",
        "pausedFeatures: count loop misses REDEEM (4 features, loop only iterates 3)",
    ),
    # === Policy lane wiring (transferPolicyIds reads) ===
    Mutation(
        MOCK_B20,
        "if (policyType == TRANSFER_SENDER) return uint64($.transferPolicyIds);",
        "if (policyType == TRANSFER_SENDER) return uint64($.transferPolicyIds >> 64);",
        "_readPolicyId: TRANSFER_SENDER reads RECEIVER lane (wrong shift)",
    ),
    Mutation(
        MOCK_B20,
        "if (policyType == TRANSFER_RECEIVER) return uint64($.transferPolicyIds >> 64);",
        "if (policyType == TRANSFER_RECEIVER) return uint64($.transferPolicyIds >> 128);",
        "_readPolicyId: TRANSFER_RECEIVER reads EXECUTOR lane (wrong shift)",
    ),
    Mutation(
        MOCK_B20,
        "if (policyType == TRANSFER_EXECUTOR) return uint64($.transferPolicyIds >> 128);",
        "if (policyType == TRANSFER_EXECUTOR) return uint64($.transferPolicyIds);",
        "_readPolicyId: TRANSFER_EXECUTOR reads SENDER lane (wrong shift)",
    ),
    # === Permit cross-cutting ===
    Mutation(
        MOCK_B20,
        "return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));",
        "return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, uint256(1), address(this)));",
        "DOMAIN_SEPARATOR: hardcoded chainId 1 (signatures replayable across forks)",
    ),
    Mutation(
        MOCK_B20,
        "return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));",
        "return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(0)));",
        "DOMAIN_SEPARATOR: verifyingContract hardcoded to zero (cross-token replay)",
    ),
    # === MockB20Stablecoin variant ===
    Mutation(
        Path("/Users/amiecorso/base-std/test/lib/mocks/MockB20Stablecoin.sol"),
        "return MockB20StablecoinStorage.layout().currency;",
        "return MockB20Storage.layout().name;",
        "MockB20Stablecoin.currency: returns base-token NAME instead of currency",
    ),
    # === Order-sensitivity in _transfer balance updates ===
    Mutation(
        MOCK_B20,
        "$.balances[from] = fromBalance - amount;\n            $.balances[to] += amount;",
        "$.balances[from] = fromBalance + amount;\n            $.balances[to] -= amount;",
        "_transfer: signs reversed on both balance updates (sender gains, receiver loses)",
    ),
]


def run_forge_test() -> tuple[bool, str]:
    result = subprocess.run(
        ["forge", "test"],
        cwd=REPO,
        capture_output=True,
        text=True,
        timeout=300,
    )
    output = result.stdout + result.stderr
    last_lines = "\n".join(output.splitlines()[-3:])
    return result.returncode == 0, last_lines


def apply_mutation(m: Mutation) -> bool:
    content = m.file.read_text()
    if m.old not in content:
        print(f"  SKIP: pattern not found in {m.file.name}")
        return False
    if content.count(m.old) > 1:
        print(f"  SKIP: pattern matches {content.count(m.old)} times in {m.file.name}, ambiguous")
        return False
    m.file.write_text(content.replace(m.old, m.new, 1))
    return True


def main():
    results = []
    for i, m in enumerate(MUTATIONS, 1):
        print(f"\n[{i}/{len(MUTATIONS)}] {m.description}")
        backup = m.file.read_text()
        try:
            if not apply_mutation(m):
                results.append((m, "skipped", ""))
                continue
            passed, last = run_forge_test()
            if passed:
                print(f"  SURVIVED: tests all passed against the mutation")
                results.append((m, "survived", last))
            else:
                print(f"  KILLED: test suite caught the mutation")
                results.append((m, "killed", last))
        finally:
            m.file.write_text(backup)

    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    killed = [r for r in results if r[1] == "killed"]
    survived = [r for r in results if r[1] == "survived"]
    skipped = [r for r in results if r[1] == "skipped"]
    print(f"Killed:   {len(killed)} / {len(results)}")
    print(f"Survived: {len(survived)} / {len(results)}")
    print(f"Skipped:  {len(skipped)} / {len(results)}")

    if survived:
        print("\nSurvivors (test-suite gaps):")
        for m, _, _ in survived:
            print(f"  - [{m.file.name}] {m.description}")

    if skipped:
        print("\nSkipped (pattern issues):")
        for m, _, _ in skipped:
            print(f"  - [{m.file.name}] {m.description}")

    sys.exit(0 if not survived else 1)


if __name__ == "__main__":
    main()
