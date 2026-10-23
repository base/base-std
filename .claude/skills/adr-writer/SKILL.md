---
name: adr-writer
description: "Write a specification ADR from a case input, the chosen main design plan (template v2) and the other candidate plans. Produces the point-form changelog headings: a short decision-first Summary, a problem-only Motivation, a Background on how the affected contracts work today, Specs with one interface block and step-by-step behaviour changes, before/after Examples, plain-language alternatives and integrator Migration Steps. Use when asked to write, render or update an ADR or changelog entry from design plans."
version: 2.0.0
---

# Write a specification ADR from design plans

This skill turns a chosen design plan into an ADR. The ADR records a decision that was
already made. This skill does not design, choose a plan, change code or run a council.

## Inputs

- **`.council/input.md`**: holds only `## Motivation`, `## User flows to optimize for` and
  `## Must not break`. It has no Summary. You write the Summary.
- **The main plan**: the plan the caller or architect chose. Use the path you are given.
  Never pick the main plan yourself by file name, perspective or order.
- **The other plans**: the remaining candidates, if any. They supply the alternatives.
- **The code**, read only to confirm how the affected contracts behave today.

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

The structure of the main plan is described in `../design-plan/references/plan-template.md`.

## What an ADR is about

The ADR is a specification for people who build on the protocol. It describes public
contracts, their observable behaviour, permissions, storage meaning, errors, events and
the effect on integrators.

It never covers how a node or client implements the specification. Leave out the
implementation language, libraries or packages, client code, comparisons between a mock
and a node, internal source paths and lists of development work. You may read code to
learn facts; those facts still appear only as contract behaviour.

## Voice

Write as the author of the decision. State facts directly: "Existing callers see no
change", not "the plan says callers see no change". Never mention a plan, a plan section
or field, a source file of the inputs, a perspective name, a candidate number or how the
ADR was produced. Never write internal trace labels such as FLOW-n, CANT-n, BEH-n, ST-n,
G-INV-n or similar IDs, in prose, tables, code or diagrams. Describe the thing they label
in words instead.

## Output structure

Use the heading tree in `references/template-point-form.md`: the `#` title, optional
metadata bullets, then these headings in this order, with this spelling.

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

Keep every heading. You may add descriptive subheadings one level below a section (for
example one `####` per behaviour change, or one `###` per subsystem in Background). Do not
add other top-level sections.

## Metadata

Give the ADR a short, meaningful title and feature name. Fill a metadata field only when
you know its value: the date of writing, and `adr-writer` as the author. Omit any field you
cannot fill. Never write a placeholder, a TODO marker or an invented person.

## Writing each section

### Summary

A few sentences that answer three questions and then end:

1. What is decided: the change in one sentence. Use a short before/after contrast only
   when it reads more clearly.
2. Who is affected, and whether they must do anything before the change activates. Base
   this on the main plan's `breaking` and `activation` values and its interactions; do not
   assume the change is non-breaking.
3. What does not change, where a reader could reasonably expect it to.

Leave the reasons for the change to Motivation, rejected options to the alternatives
section and mechanics to Specs.

### Motivation

Rewrite the input's Motivation in your own clear prose. Cover:

- the concrete situation that makes a change necessary;
- why today's behaviour cannot handle it, and what that leads to;
- what must become possible.

Keep every supported fact, number and scope limit from the input. Do not describe the
solution, argue against other designs or add specification details. Do not copy the
input's flow or constraint labels.

### Background

Give a reader without context what they need to follow Specs:

1. Introduce each affected contract as a whole: its role and who uses it.
2. Walk through the affected flow as it works today, from start to result: who calls
   which function, which contract it reaches next, and where checks are enforced.
3. Add a Mermaid sequence or flow diagram when it makes the path easier to follow.

Group facts under one subheading per subsystem when more than one is involved. Describe
only current behaviour, confirmed from the code or inputs; nothing invented.

### Specs

**Interface Changes.** Show one `solidity` block with every new and changed declaration
from the main plan's interface section, each with a brief comment saying whether it is new
or changed and what it does. Explain the declarations in sentences outside the block. A
small table may add detail, such as which role may call each function. Do not add
unchanged declarations or invent signatures. If the public interface does not change, say
so in one sentence.

**Behavioural Changes.** Write one subsection per behaviour change, with a plain name.
Explain the logic in execution order: checks, authorization, errors, state updates and
events. Use numbered steps, a Mermaid flow diagram or step-by-step prose. Do not use large
tables for logic. Show storage changes as a readable table (field, type, where it lives,
what changes), keeping any layout or packing guarantee the plan states. Turn the plan's
scaffolding (`Functions:` lines, IDs) into normal prose.

Use the reference part of the plan (requirement trace, new surface, hot-path cost,
invariants, interactions) to check that the Specs are complete and to state costs and
constraints. Do not reproduce those sections as tables.

**Examples.** Build concrete call sequences from the plan's user flows and the verified
current behaviour. Prefer Solidity snippets and Mermaid diagrams. For each, show the setup,
the caller's action and the visible result, including a changed failure case when the
plan has one. Where possible, show the same task before and after the change and label
each version clearly. Do not invent APIs, values or a before version that does not exist.

### Design Decisions & Alternatives Considered

For each main choice, say what was chosen, what it gives the users and what it costs.
Where the design adds a bound or decides who may modify a new contract or record, explain
that choice and what a different choice would cost.

Then describe each rejected option in a few plain words (for example "a separate registry
contract" or "store the list inline"), why it would help and why the chosen design wins.
Merge options that are in effect the same. Never name perspectives or candidates. Do not
invent a rejection reason the inputs do not support. If no other plans were supplied, say
that no alternative designs were weighed.

### Migration Steps

Address integrators: token issuers, applications, wallets and indexers. For each group
that is affected, state what they must do and what they may do, and when relative to
activation. Say plainly which groups need no action. Never list work for protocol or node
developers, such as implementation, testing, release or deployment tasks. Do not invent
rollout, rollback or storage-migration guarantees.

## Fidelity rules

- Preserve every fact, number, condition, qualifier and scope limit from the sources;
  rephrase freely, but never change meaning.
- Keep uncertainty at the same strength. Carry relevant open questions into the section
  they affect, as plain statements of what is not yet decided.
- Do not invent signatures, selectors, storage slots, gas numbers, roles, dates, people or
  compatibility claims.

## Style

Apply `references/simplified-technical-english.md` and
`references/google-technical-writing.md`: name the actor, one action per sentence, plain
words, one term per concept, conditions before instructions, numbered lists for ordered
steps. Never claim official ASD-STE100 compliance.

## Modes

- **Live mode** (a user is present): if the main plan is not identified, or an essential
  input is missing, ask once before drafting. Do not guess the main plan.
- **Eval mode** (run by a script): never ask questions or wait. Use the inputs and paths
  given. If a fact is missing, say in the relevant section that it is not yet decided, or
  leave the optional detail out. Never edit the input or the plans.

## Checklist

Re-read the sources, not only your draft, when you check.

- [ ] Headings match the template in order; extra headings are only subheadings.
- [ ] Metadata holds only known values; no placeholders.
- [ ] No implementation language, client code, packages or developer tasks.
- [ ] No internal labels, perspective names or references to plans or the generation.
- [ ] Summary answers what is decided, who must act and what stays the same, and stops.
- [ ] Motivation states the problem only, with the input's facts intact.
- [ ] Background introduces each contract and walks through today's flow.
- [ ] One solidity interface block; one ordered subsection per behaviour change.
- [ ] Examples show before and after where possible.
- [ ] Alternatives use plain names and supported reasons.
- [ ] Migration steps address integrators only, with timing.
- [ ] No invented facts; input and plans unchanged; no questions in eval mode.
