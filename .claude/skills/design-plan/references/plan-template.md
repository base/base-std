---
plan_id: <short-stable-id>
perspective: <design perspective this plan takes>
inputs_ref: <case input and snapshot this plan was written against>
breaking: <true|false>
activation: <how and when the change takes effect, or why no activation step is needed>
surface:
  external_functions: <n>
  roles: <n>
  storage_slots: <n>
  config_params: <n>
  errors: <n>
  events: <n>
---

# Design plan (template v1.1)

<!--
How to fill this in (see README.md in this folder for the full conventions):
- Replace every <placeholder>. A finished plan contains no placeholders and no TBD.
- Keep every heading and every table header exactly as written, in this order.
- If a table has no rows, keep the header, leave the body empty and write "None:" with the reason below it.
- `breaking` is true if any existing function returns a different outcome for the same inputs.
- `surface` counts only additions: new external functions, roles, storage slots, configuration
  parameters, errors and events. Reused items count zero. The counts equal the New surface table in §3.
-->

## 1 Approach

<Two to five sentences: the design, and why it meets the Motivation, the active user flows and the
constraints of the input.>

## 2 Requirement trace

<One row per requirement the design must meet, in your own words. Cite its source in one of two forms: the
FLOW-n items it serves (for example "FLOW-1, FLOW-3"; retired items cannot be cited), or the one Motivation
sentence it answers, quoted in full as Motivation: "the sentence". Do not mix the two forms in one row. Escape a
literal "|" inside a quote as "\|". Every Change ID must exist in §3 and every acceptance test must be
defined in §8.>

| Requirement | Source | Change IDs | Acceptance tests |
| --- | --- | --- | --- |
| <requirement the design meets> | <FLOW-1> | <IF-1, BEH-1> | <test_function_outcome_variant> |
| <requirement the design meets> | <Motivation: "complete Motivation sentence"> | <BEH-1> | <test_function_outcome_variant> |

## 3 Changes

<IDs are stable and unique: IF-n interface, ST-n storage, BEH-n behavior, ERR-n errors, EVT-n events.>

### Interface

<Full Solidity signatures, including visibility, mutability and return types. New/Changed is `new` or `changed`.>

| ID | Signature | New/Changed |
| --- | --- | --- |
| IF-1 | <function name(type arg) external returns (type)> | <new> |

### Storage

<One row per field. Status is `new`, `changed` or `unchanged`. Existing slots keep their meaning, type and
position; packing a field into free bits of an existing slot is described explicitly in Slot and Field.
Mock = Rust states that the Solidity mock and the Rust precompile use the identical layout (`yes`), or
explains the difference.>

| ID | Slot | Field | Type | Status | Mock = Rust |
| --- | --- | --- | --- | --- | --- |
| ST-1 | <slot or derivation> | <field name> | <type and bit range> | <new> | <yes> |

### Behavior

<One row per function whose behavior is added or changed. Changes existing function is `yes` or `no`.
Before and After describe outcomes for the same inputs, including authorization (name the role for every
privileged action), state changes, errors and events. Mark breaking changes and give the reason in After.>

| ID | Function | Changes existing function (yes/no) | Before | After |
| --- | --- | --- | --- | --- |
| BEH-1 | <function> | <no> | <behavior before the change> | <behavior after the change> |

### Errors and events

| ID | Name | Params | Trigger |
| --- | --- | --- | --- |
| ERR-1 | <ErrorName> | <(type name)> | <condition that raises it> |
| EVT-1 | <EventName> | <(type indexed name, type name)> | <operation that emits it> |

### New surface

<One row per addition counted in the front-matter `surface`. Kind is one of external_functions, roles,
storage_slots, config_params, errors, events. Change IDs point at the §3 rows that introduce the item.
Several fields packed into one new slot count as one storage slot. Reused items are not listed.>

| Kind | Name | Change IDs |
| --- | --- | --- |
| <external_functions> | <name> | <IF-1, BEH-1> |

## 4 User flows

<One row per FLOW-n in the input, in order. Walk each flow end to end: setup, call, state changes, events,
observable result. Keep retired FLOW items at their IDs and write "retired: not applicable" in Steps.>

| Flow | Steps (setup → call → state change → events → observable result) | Change IDs | Tests |
| --- | --- | --- | --- |
| FLOW-1 | <setup → call → state change → events → result> | <BEH-1> | <test_function_outcome_variant> |

## 5 Hot-path cost

<One row per affected path plus the unchanged hot paths (transfer, transferFrom, mint, burn). Counts are
worst-case storage operations per call. Deltas are signed and relative to the pre-change snapshot. State the
condition behind each worst case, the slot behind each packing claim, and the contract each external call reaches.>

| Function | Cold reads | Warm reads | Writes | External calls | Δ cold | Δ warm | Δ writes | Packed into a slot already read |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| <transfer> | <n> | <n> | <n> | <n> | <+0> | <+0> | <+0> | <yes: slot / no / n/a> |

## 6 Invariants

<One row per CANT-n in the input (keep retired items at their IDs and mark them retired), then G-INV-1
(see ../invariants/global.md), then any NEW-n invariants this plan adds. Status is `holds` or `at risk`;
explain how it holds or why it is at risk, and cite the change IDs and tests.>

| ID | Status | How it holds | Change IDs | Tests |
| --- | --- | --- | --- | --- |
| CANT-1 | <holds> | <explanation> | <BEH-1> | <test_function_outcome_variant> |
| G-INV-1 | <holds> | <every call target the change uses is a precompile, or no calls> | <BEH-1> | <test_function_outcome_variant> |
| NEW-1 | <holds> | <invariant this plan introduces> | <ST-1> | <test_function_outcome_variant> |

## 7 Interactions

<Each existing mechanism or component the change touches (policies, roles, pause, allowances, other
precompiles, events consumers) and how it interacts. For mechanisms that do not apply, say why.>

## 8 Edge cases and test plan

<list the edge cases you considered and their tests. Test names follow test_{function}_{outcome}_{variant}.
Every test named in §2, §4 and §6 is defined here.>

| Test | Covers | Setup and action | Expected result |
| --- | --- | --- | --- |
| <test_function_outcome_variant> | <FLOW-1, CANT-1> | <setup; call> | <outcome, state, events> |

## 9 What this plan gives up

<Deliberate tradeoffs and what they cost. A tradeoff never drops a requirement.>

## 10 Open questions

<Genuine open questions and their impact on the design, or "None". Do not hide unspecified behavior here.>
