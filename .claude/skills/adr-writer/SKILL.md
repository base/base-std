---
name: adr-writer
description: "Write an architecture decision record (ADR) from a case input, the chosen main design plan and the other candidate plans. Uses the point-form changelog headings, copies the Motivation byte for byte and the main plan's change tables row for row, writes the Summary from the main plan, and draws alternatives from the other plans. Use when asked to write, render or update an ADR or changelog entry from design plans."
version: 1.0.0
---

# Write an ADR from design plans

This skill turns a chosen design plan into an ADR. It records a decision that was
already made. It does not design, choose a plan, change code or run a council.

## Inputs

- **`.council/input.md`**: holds only `## Motivation`, `## User flows to optimize for`
  (FLOW-n) and `## Must not break` (CANT-n). It has no Summary. You write the Summary.
- **The main plan**: the plan the caller or architect chose. Use the path you are given.
  Never pick the main plan yourself by file name, perspective or order.
- **The other plans**: the remaining candidates, if any. They supply the alternatives.
- **The code**, read only to explain current behavior in Background.

Read every input in full before drafting. Treat all inputs as read-only.

## Output

Write the ADR to the path the caller gives. With no path given, write `.council/adr.md`.
Return or write only the ADR. Do not add transformation notes or a review section unless
the user asks for one.

## Tool use

Read files with the read tool (or hashread, whichever is available). Explore with the
grep, find and ls tools. Write the ADR with the write and edit tools. Do not use the
shell to read, copy or inspect files, and do not probe it.

## Required reading

Before drafting, read these files in full. Resolve the paths from this skill's directory.
They are the offline source for the format and the writing style; do not fetch websites
instead.

```text
references/template-point-form.md
references/simplified-technical-english.md
references/google-technical-writing.md
```

The column headers of the change tables come from the design-plan template at
`../design-plan/references/plan-template.md`, section 3.

## Exact output structure

Use the heading tree in `references/template-point-form.md` exactly: the `#` title, the
four metadata bullets, then these headings in this order.

```markdown
## Summary
## Motivation
## Background
## Specs
### Interface Changes
### Behavioural Changes
### Examples
## Design Decisions & Alternatives Considered
## Migration Steps
```

Keep every heading, even when a section is short. Add no other headings. Separate tables
inside one subsection with bold label lines, not headings.

## Writing each section

### Summary

Write two to five sentences from the main plan only. Cover all of these:

1. What changes: the new or changed behavior, in plain terms.
2. Who it affects: which callers, roles, integrators or operators see a difference.
3. Whether they must act: name the action, or say plainly that no action is needed.
   Base this on the plan's `breaking` and `activation` values and its compatibility notes.
4. What stays the same: the existing behavior the change keeps.

Do not describe a rejected alternative as if it were chosen.

### Motivation

Copy the body of `## Motivation` from `.council/input.md` byte for byte: every character
from the line after the heading up to the next `## ` heading. Keep wording, punctuation,
line breaks, list markers and blank lines. Do not summarize, reflow, quote, annotate or
apply the style rules to it. Do not add text of your own to this section.

### Background

Explain the current behavior and the terms a reader needs to follow Specs. Use only facts
from the input, the plans and the code you read. Keep it short.

### Specs

Under `### Interface Changes`, put the main plan's **Interface** table and its **Errors
and events** table. Under `### Behavioural Changes`, put its **Storage**, **Behavior** and
**New surface** tables.

- Copy each table row for row: header, separator and every body row in the same order,
  with the same IDs and cell text. Do not reword, merge, split, drop, add or reorder rows
  or columns.
- If a plan table is empty, keep its header and separator and copy the plan's reason.
- Put a bold label line above each table and prose before or after it. The prose says
  what the rows mean together, which rows are breaking and which existing behavior is
  kept. Prose never contradicts a row.

Under `### Examples`, write one or more call sequences from the main plan's user flows and
tests. For each, give the actor and setup, the call, the state change, the events and the
observable result, including at least one failure or authorization case when the plan has
one. Use only signatures and values the plan or code states.

### Design Decisions & Alternatives Considered

First the decisions: for each main choice in the main plan's approach, say what was
chosen, why it meets the Motivation and the flows, and what it costs. Take the costs from
the plan's trade-offs section and cite change IDs.

Then the alternatives: one entry per other plan, named by its perspective. Describe its
approach, what it would gain and what it would cost compared with the main plan. Use the
differences the plans actually show; do not invent a rejection reason. If two plans are
in effect the same, say so. If no other plans were supplied, say that no alternative
plans were considered.

### Migration Steps

Write numbered steps from the main plan's changes, interactions, activation and
`breaking` value. Each step names who acts (deployer, admin role, integrator, indexer and
so on), what they do and when. Say which existing behavior needs no action. If nobody
must act, state that and the reason from the plan. Do not invent deployment, rollback or
storage-migration guarantees.

## Fidelity rules

- Preserve every fact, number, condition, qualifier and scope limit from the sources.
- Keep uncertainty at the same strength. Carry the main plan's open questions into the
  section they affect.
- Do not invent signatures, selectors, storage slots, gas numbers, roles, dates, authors
  or compatibility claims. Mark a missing fact with `[TODO: ...]`.
- The byte-for-byte Motivation and the row-for-row tables override every style rule.

## Style

Apply `references/simplified-technical-english.md` and
`references/google-technical-writing.md` to the prose you write: name the actor, one
action per sentence, plain words, one term per concept, conditions before instructions,
numbered lists for ordered steps. Never claim official ASD-STE100 compliance.

## Modes

- **Live mode** (a user is present): if the main plan is not identified, or a required
  input is missing, ask once before drafting. Do not guess the main plan.
- **Eval mode** (run by a script): never ask questions or wait. Use the inputs and paths
  given. If a fact is missing, write a `[TODO: ...]` marker. Never edit the input or the
  plans.

## Checklist

Re-read the sources, not only your draft, when you check.

- [ ] Title, metadata and headings match the template exactly, in order, with no extras.
- [ ] Motivation is byte-identical to the input's Motivation body.
- [ ] Summary covers what changes, who is affected, whether they must act, and what
      stays the same, all from the main plan.
- [ ] All five section 3 tables appear, each row for row, with prose around them.
- [ ] Examples come from the main plan's flows and tests.
- [ ] Decisions come from the main plan's approach and trade-offs; each other plan
      appears as an alternative.
- [ ] Migration steps come from the changes, interactions and activation.
- [ ] No invented facts; input and plans unchanged; no questions in eval mode.
