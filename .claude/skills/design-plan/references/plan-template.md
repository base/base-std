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

# Design plan (template v2)

<!--
How to fill this in (see README.md in this folder for the full conventions):
- Replace every <placeholder>. A finished plan contains no placeholders and no TBD.
- Keep every heading exactly as written, in this order. The readable part (sections 1 to 6) is for people:
  concise technical English, code and diagrams instead of large tables. The reference part (sections 7 to 11)
  is for tools and reviewers checking the details.
- Mermaid diagrams (```mermaid) are welcome wherever a flow is easier to see than to read.
- `breaking` is true if any existing function returns a different outcome for the same inputs.
- `surface` counts only additions: new external functions, roles, storage slots, configuration
  parameters, errors and events. Reused items count zero. The counts equal the §8 New surface table.
-->

## 1 Approach

<The plan in a few short paragraphs: the design, and why it meets the Motivation, the user flows and the
constraints of the input.>

## 2 Interface

<One Solidity block with every new or changed function, type, error and event. End each declaration line with
`// new` or `// changed`, optionally followed by a short note; put a brief comment above it. Keep full sentences in
prose after the block. When nothing is added or changed, the block holds only the line `// No interface change.`>

```solidity
// <Brief comment.>
function exampleName(<parameters>) external; // new
```

## 3 Changes

<One subsection per behaviour change, titled in plain words and tagged with its ID at the end. The first line
names the functions it touches and whether their existing behaviour changes. Then the logic as numbered steps:
checks and their errors in order, state changes, events, and the role that authorizes every privileged action.
State the reason for any breaking change.>

### <What changes, in a few words> (BEH-1)

Functions: <`functionName`>; changes existing behaviour: <yes|no>

1. <step>
2. <step>

### Storage

<One row per field. Status is `new`, `changed` or `unchanged`. Existing slots keep their meaning, type and
position; packing a field into free bits of an existing slot is described explicitly in Slot and Field.
Mock = Rust states that the Solidity mock and the Rust precompile use the identical layout (`yes`), or
explains the difference.>

| ID | Slot | Field | Type | Status | Mock = Rust |
| --- | --- | --- | --- | --- | --- |
| ST-1 | <slot or derivation> | <field name> | <type and bit range> | <new> | <yes> |

## 4 User flows

<One subsection per FLOW-n in the input, in order, titled in plain words and tagged with its ID at the end.
Walk the flow end to end as numbered steps: setup, call, state changes, events, observable result. A retired
FLOW keeps its subsection and says "retired: not applicable" on its first line.>

### <What the user does, in a few words> (FLOW-1)

1. <setup>
2. <call>
3. <state change and events>
4. <observable result>

## 5 What this plan gives up

<Deliberate tradeoffs and what they cost, at a high level. A tradeoff never drops a requirement.>

## 6 Open questions

<Genuine open questions and their impact on the design, or "None". Do not hide unspecified behaviour here.>

# Reference

<!-- Sections 7 to 11 are read by tools and reviewers. Keep them exact and terse. -->

## 7 Requirement trace

<One row per requirement the design must meet, in your own words. Cite its source in one of two forms: the
FLOW-n items it serves (for example "FLOW-1, FLOW-3"; retired items cannot be cited), or the one Motivation
sentence it answers, quoted in full as Motivation: "the sentence". Do not mix the two forms in one row. Escape a
literal "|" inside a quote as "\|". Every Change ID must exist in §3.>

| Requirement | Source | Change IDs |
| --- | --- | --- |
| <requirement the design meets> | <FLOW-1> | <BEH-1> |
| <requirement the design meets> | <Motivation: "complete Motivation sentence"> | <BEH-1, ST-1> |

## 8 New surface

<One row per addition counted in the front-matter `surface`. Kind is one of external_functions, roles,
storage_slots, config_params, errors, events. Functions, errors and events are declared in the §2 block.
Change IDs point at the §3 change that introduces the item; a storage slot cites its new ST row. Several fields
packed into one new slot count as one storage slot. Reused items are not listed.>

| Kind | Name | Change IDs |
| --- | --- | --- |
| <external_functions> | <functionName> | <BEH-1> |

## 9 Hot-path cost

<One row per affected path plus the unchanged hot paths (transfer, transferFrom, mint, burn). Counts are
worst-case storage operations per call. Deltas are signed and relative to the pre-change snapshot. State the
condition behind each worst case, the slot behind each packing claim, and the contract each external call reaches.>

| Function | Cold reads | Warm reads | Writes | External calls | Δ cold | Δ warm | Δ writes | Packed into a slot already read |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| <transfer> | <n> | <n> | <n> | <n> | <+0> | <+0> | <+0> | <yes: slot / no / n/a> |

## 10 Invariants

<One row per CANT-n in the input (keep retired items at their IDs and mark them retired), then G-INV-1
(see ../invariants/global.md), then any NEW-n invariants this plan adds. Status is `holds` or `at risk`;
explain how it holds or why it is at risk, and cite the change IDs.>

| ID | Status | How it holds | Change IDs |
| --- | --- | --- | --- |
| CANT-1 | <holds> | <explanation> | <BEH-1> |
| G-INV-1 | <holds> | <every call target the change uses is a precompile, or no calls> | <BEH-1> |
| NEW-1 | <holds> | <invariant this plan introduces> | <ST-1> |

## 11 Interactions

<Each existing mechanism or component the change touches (policies, roles, pause, allowances, other
precompiles, events consumers) and how it interacts. For mechanisms that do not apply, say why.>
