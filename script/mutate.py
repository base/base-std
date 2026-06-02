#!/usr/bin/env python3
"""Hand-rolled mutation testing for MockB20 / MockB20Factory.

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
MOCK_FACTORY = REPO / "test/lib/mocks/MockB20Factory.sol"
MOCK_POLICY = REPO / "test/lib/mocks/MockPolicyRegistry.sol"
MOCK_STABLECOIN = REPO / "test/lib/mocks/MockB20Stablecoin.sol"


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
        "if (_isPaused(feature)) revert ContractPaused(feature);",
        "if (!_isPaused(feature)) revert ContractPaused(feature);",
        "whenNotPaused: invert pause check (paused ops succeed, unpaused revert)",
    ),
    # === MockB20: role check in _requireRole (the onlyRole modifier body) ===
    # After the modifier refactor, role checks at the call site (mint, pause,
    # unpause, burn, burnBlocked, setName, setSymbol, etc.) all funnel through
    # _requireRole. Inverting it inverts every onlyRole-gated path at once;
    # the mint role-revert test (and many others) should still kill it.
    Mutation(
        MOCK_B20,
        "if (!hasRole(role, msg.sender)) {\n            revert AccessControlUnauthorizedAccount(msg.sender, role);\n        }",
        "if (hasRole(role, msg.sender)) {\n            revert AccessControlUnauthorizedAccount(msg.sender, role);\n        }",
        "_requireRole: invert role check (role-holders fail every onlyRole gate)",
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
        "if (!IPolicyRegistry(POLICY_REGISTRY).isAuthorized(packed.sender, from)) {\n                revert PolicyForbids(TRANSFER_SENDER_POLICY, packed.sender);\n            }",
        "if (false) revert PolicyForbids(TRANSFER_SENDER_POLICY, packed.sender);",
        "_transfer: drop TRANSFER_SENDER_POLICY policy check entirely",
    ),
    # === MockB20: skip policy check on receiver (matches new inline pattern) ===
    Mutation(
        MOCK_B20,
        "if (!IPolicyRegistry(POLICY_REGISTRY).isAuthorized(packed.receiver, to)) {\n                revert PolicyForbids(TRANSFER_RECEIVER_POLICY, packed.receiver);\n            }",
        "if (false) revert PolicyForbids(TRANSFER_RECEIVER_POLICY, packed.receiver);",
        "_transfer: drop TRANSFER_RECEIVER_POLICY policy check entirely",
    ),
    # === MockB20: skip MINT_RECEIVER_POLICY policy check (matches new inline pattern) ===
    Mutation(
        MOCK_B20,
        "            if (!IPolicyRegistry(POLICY_REGISTRY).isAuthorized(mintReceiverPolicyId, to)) {\n                revert PolicyForbids(MINT_RECEIVER_POLICY, mintReceiverPolicyId);\n            }",
        "            // mint receiver policy check elided\n            if (false) revert PolicyForbids(MINT_RECEIVER_POLICY, mintReceiverPolicyId);",
        "_mint: drop MINT_RECEIVER_POLICY policy check entirely",
    ),
    # === MockB20: lastAdmin guard off-by-one (inline conjunction) ===
    Mutation(
        MOCK_B20,
        "if (role == DEFAULT_ADMIN_ROLE && $.roles[DEFAULT_ADMIN_ROLE][msg.sender] && $.adminCount == 1) {",
        "if (role == DEFAULT_ADMIN_ROLE && $.roles[DEFAULT_ADMIN_ROLE][msg.sender] && $.adminCount == 2) {",
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
        "    function _requireNonZeroActors(address from, address to) internal pure {\n        if (to == address(0)) revert InvalidReceiver(to);",
        "    function _requireNonZeroActors(address from, address to) internal pure {\n        // if (to == address(0)) revert InvalidReceiver(to);",
        "_requireNonZeroActors: drop zero-recipient guard",
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
        "_writeUint(token, MockB20Storage.initializedSlot(), 1);",
        "// _writeUint(token, MockB20Storage.initializedSlot(), 1);",
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
        "| uint160(uint72(tail));",
        "| (uint160(uint72(tail)) << 8);",
        "_computeAddress: tail shifted left by 8 bits (truncates entropy and breaks deterministic addressing)",
    ),
    Mutation(
        MOCK_FACTORY,
        "uint160 addr = (uint160(0xB2) << 152)",
        "uint160 addr = (uint160(0xB3) << 152)",
        "_computeAddress: prefix byte changed from 0xB2 to 0xB3 (breaks isB20 prefix check)",
    ),
    Mutation(
        MOCK_FACTORY,
        "bytes9 tail = bytes9(keccak256(abi.encode(sender, salt)));",
        "bytes9 tail = bytes9(keccak256(abi.encodePacked(sender, salt)));",
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
        "for (uint256 i = 0; i < featureCount; i++) {\n            if (((vectors >> i) & uint256(1)) == 1) count++;",
        "for (uint256 i = 0; i < featureCount - 1; i++) {\n            if (((vectors >> i) & uint256(1)) == 1) count++;",
        "pausedFeatures: count loop drops the highest feature (off-by-one misses BURN)",
    ),
    # === Policy lane wiring (transferPolicyIds reads) ===
    Mutation(
        MOCK_B20,
        "if (policyScope == TRANSFER_SENDER_POLICY) return $.transferPolicyIds.sender;",
        "if (policyScope == TRANSFER_SENDER_POLICY) return $.transferPolicyIds.receiver;",
        "_readPolicyId: TRANSFER_SENDER_POLICY reads RECEIVER lane (wrong field)",
    ),
    Mutation(
        MOCK_B20,
        "if (policyScope == TRANSFER_RECEIVER_POLICY) return $.transferPolicyIds.receiver;",
        "if (policyScope == TRANSFER_RECEIVER_POLICY) return $.transferPolicyIds.executor;",
        "_readPolicyId: TRANSFER_RECEIVER_POLICY reads EXECUTOR lane (wrong field)",
    ),
    Mutation(
        MOCK_B20,
        "if (policyScope == TRANSFER_EXECUTOR_POLICY) return $.transferPolicyIds.executor;",
        "if (policyScope == TRANSFER_EXECUTOR_POLICY) return $.transferPolicyIds.sender;",
        "_readPolicyId: TRANSFER_EXECUTOR_POLICY reads SENDER lane (wrong field)",
    ),
    # === Permit cross-cutting ===
    Mutation(
        MOCK_B20,
        "block.chainid,\n                address(this)",
        "uint256(1),\n                address(this)",
        "DOMAIN_SEPARATOR: hardcoded chainId 1 (signatures replayable across forks)",
    ),
    Mutation(
        MOCK_B20,
        "block.chainid,\n                address(this)\n            )",
        "block.chainid,\n                address(0)\n            )",
        "DOMAIN_SEPARATOR: verifyingContract hardcoded to zero (cross-token replay)",
    ),
    # === MockB20Stablecoin variant ===
    Mutation(
        MOCK_STABLECOIN,
        "return MockB20StablecoinStorage.layout().currency;",
        "return \"\";",
        "MockB20Stablecoin.currency: returns empty string instead of configured value",
    ),
    # === Order-sensitivity in _transfer balance updates ===
    Mutation(
        MOCK_B20,
        "$.balances[from] = fromBalance - amount;\n            $.balances[to] += amount;",
        "$.balances[from] = fromBalance + amount;\n            $.balances[to] -= amount;",
        "_transfer: signs reversed on both balance updates (sender gains, receiver loses)",
    ),
    # === MockPolicyRegistry: authorization core ===
    Mutation(
        MOCK_POLICY,
        "return _typeOf(policyId) == PolicyType.ALLOWLIST ? member : !member;",
        "return _typeOf(policyId) == PolicyType.ALLOWLIST ? !member : member;",
        "isAuthorized: ALLOWLIST/BLOCKLIST polarity flipped (allowlist becomes blocklist and vice versa)",
    ),
    Mutation(
        MOCK_POLICY,
        "if (policyId == ALWAYS_ALLOW_ID) return true;\n        if (policyId == ALWAYS_BLOCK_ID) return false;",
        "if (policyId == ALWAYS_ALLOW_ID) return false;\n        if (policyId == ALWAYS_BLOCK_ID) return true;",
        "isAuthorized: ALWAYS_ALLOW and ALWAYS_BLOCK semantics swapped",
    ),
    Mutation(
        MOCK_POLICY,
        "if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return true;",
        "if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return false;",
        "policyExists: built-ins report as nonexistent (breaks token updatePolicy guard)",
    ),
    # === MockPolicyRegistry: policy creation ===
    Mutation(
        MOCK_POLICY,
        "return PolicyType(uint8(policyId >> POLICY_ID_TYPE_SHIFT));",
        "return PolicyType(uint8(policyId));",
        "_typeOf: omit type shift (every policyId decodes as PolicyType 0)",
    ),
    Mutation(
        MOCK_POLICY,
        "if (admin == address(0)) revert ZeroAddress();\n        // Out-of-range",
        "if (admin != address(0)) revert ZeroAddress();\n        // Out-of-range",
        "_create: zero-admin guard inverted (only zero-admin is allowed)",
    ),
    Mutation(
        MOCK_POLICY,
        "$.nextCounter = counter + 1;",
        "$.nextCounter = counter;",
        "_create: nextCounter doesn't advance (every create returns the same policy ID)",
    ),
    # === MockPolicyRegistry: admin management ===
    Mutation(
        MOCK_POLICY,
        "        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();\n        MockPolicyRegistryStorage.layout().pendingAdmins[policyId] = newAdmin;",
        "        if (_decodeAdmin(packed) == msg.sender) revert Unauthorized();\n        MockPolicyRegistryStorage.layout().pendingAdmins[policyId] = newAdmin;",
        "stageUpdateAdmin: admin auth check inverted (current admin is forbidden to stage)",
    ),
    Mutation(
        MOCK_POLICY,
        "if (pending != msg.sender) revert Unauthorized();",
        "if (pending == msg.sender) revert Unauthorized();",
        "finalizeUpdateAdmin: pending check inverted (only NON-pending callers succeed)",
    ),
    Mutation(
        MOCK_POLICY,
        "if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();\n        // Admin lane cleared",
        "if (_decodeAdmin(packed) == msg.sender) revert Unauthorized();\n        // Admin lane cleared",
        "renounceAdmin: admin auth check inverted (anyone but admin can renounce)",
    ),
    # === MockPolicyRegistry: list membership ===
    Mutation(
        MOCK_POLICY,
        "if (_typeOf(policyId) != PolicyType.ALLOWLIST) revert IncompatiblePolicyType();",
        "if (_typeOf(policyId) == PolicyType.ALLOWLIST) revert IncompatiblePolicyType();",
        "updateAllowlist: type check inverted (only NON-allowlists accepted)",
    ),
    Mutation(
        MOCK_POLICY,
        "if (_typeOf(policyId) != PolicyType.BLOCKLIST) revert IncompatiblePolicyType();",
        "if (_typeOf(policyId) == PolicyType.BLOCKLIST) revert IncompatiblePolicyType();",
        "updateBlocklist: type check inverted",
    ),
    Mutation(
        MOCK_POLICY,
        "_batchSetMembers({policyId: policyId, policyType: PolicyType.BLOCKLIST, value: blocked, accounts: accounts});",
        "_batchSetMembers({policyId: policyId, policyType: PolicyType.ALLOWLIST, value: blocked, accounts: accounts});",
        "updateBlocklist: passes ALLOWLIST to batch helper (emits wrong event)",
    ),
    # === MockPolicyRegistry: encoding primitives ===
    Mutation(
        MOCK_POLICY,
        "return (uint64(uint8(policyType)) << POLICY_ID_TYPE_SHIFT) | uint64(counter);",
        "return (uint64(uint8(policyType)) << (POLICY_ID_TYPE_SHIFT - 8)) | uint64(counter);",
        "_makeId: type byte shifted to wrong position (collides with counter)",
    ),
    Mutation(
        MOCK_POLICY,
        "return address(uint160(packed));",
        "return address(uint160(packed >> 8));",
        "_decodeAdmin: spurious shift corrupts the decoded admin address",
    ),
    Mutation(
        MOCK_POLICY,
        "return uint8(policyId >> POLICY_ID_TYPE_SHIFT) <= uint8(type(PolicyType).max);",
        "return uint8(policyId >> POLICY_ID_TYPE_SHIFT) < uint8(type(PolicyType).max);",
        "_isWellFormed: off-by-one (rejects last valid PolicyType discriminator)",
    ),
    # === _writePolicyId lane writes (MockB20, mirror of the read mutations) ===
    Mutation(
        MOCK_B20,
        "if (policyScope == TRANSFER_SENDER_POLICY) {\n            $.transferPolicyIds.sender = newPolicyId;",
        "if (policyScope == TRANSFER_SENDER_POLICY) {\n            $.transferPolicyIds.receiver = newPolicyId;",
        "_writePolicyId: TRANSFER_SENDER_POLICY writes to RECEIVER lane (field swap)",
    ),
    Mutation(
        MOCK_B20,
        "} else if (policyScope == TRANSFER_RECEIVER_POLICY) {\n            $.transferPolicyIds.receiver = newPolicyId;",
        "} else if (policyScope == TRANSFER_RECEIVER_POLICY) {\n            $.transferPolicyIds.executor = newPolicyId;",
        "_writePolicyId: TRANSFER_RECEIVER_POLICY writes to EXECUTOR lane",
    ),
    Mutation(
        MOCK_B20,
        "} else if (policyScope == MINT_RECEIVER_POLICY) {\n            $.mintPolicyIds.receiver = newPolicyId;",
        "} else if (policyScope == MINT_RECEIVER_POLICY) {\n            $.transferPolicyIds.receiver = newPolicyId;",
        "_writePolicyId: MINT_RECEIVER_POLICY writes to transfer lane (wrong storage field)",
    ),
    Mutation(
        MOCK_B20,
        "if (policyScope == MINT_RECEIVER_POLICY) return $.mintPolicyIds.receiver;",
        "if (policyScope == MINT_RECEIVER_POLICY) return $.transferPolicyIds.receiver;",
        "_readPolicyId: MINT_RECEIVER_POLICY reads transfer lane (wrong storage field)",
    ),
    # === _writeStablecoinStorage ===
    Mutation(
        MOCK_FACTORY,
        "_writeString(token, MockB20StablecoinStorage.slotOf(MockB20StablecoinStorage.CURRENCY_OFFSET), currency_);",
        "_writeString(token, MockB20Storage.slotOf(MockB20Storage.NAME_OFFSET), currency_);",
        "_writeStablecoinStorage: writes currency to base-token NAME slot instead of variant namespace",
    ),
    Mutation(
        MOCK_FACTORY,
        "        _writeString(token, MockB20StablecoinStorage.slotOf(MockB20StablecoinStorage.CURRENCY_OFFSET), currency_);\n    }",
        "        // currency write elided\n    }",
        "_writeStablecoinStorage: never writes the currency field (silent: currency() returns empty)",
    ),
    # === renounceLastAdmin ===
    Mutation(
        MOCK_B20,
        "if (!$.roles[DEFAULT_ADMIN_ROLE][msg.sender]) {\n            revert AccessControlUnauthorizedAccount(msg.sender, DEFAULT_ADMIN_ROLE);\n        }\n        if ($.adminCount != 1) revert NotSoleAdmin();",
        "if ($.roles[DEFAULT_ADMIN_ROLE][msg.sender]) {\n            revert AccessControlUnauthorizedAccount(msg.sender, DEFAULT_ADMIN_ROLE);\n        }\n        if ($.adminCount != 1) revert NotSoleAdmin();",
        "renounceLastAdmin: role-holder check inverted (only NON-admins can call)",
    ),
    Mutation(
        MOCK_B20,
        "if ($.adminCount != 1) revert NotSoleAdmin();",
        "if ($.adminCount != 0) revert NotSoleAdmin();",
        "renounceLastAdmin: sole-admin guard wrong (only adminCount==0 case passes)",
    ),
    Mutation(
        MOCK_B20,
        "        $.roles[DEFAULT_ADMIN_ROLE][msg.sender] = false;\n        $.adminCount = 0;",
        "        $.roles[DEFAULT_ADMIN_ROLE][msg.sender] = false;\n        $.adminCount = 1;",
        "renounceLastAdmin: leaves adminCount==1 after revoke (hasRole says no but bookkeeping says yes)",
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
