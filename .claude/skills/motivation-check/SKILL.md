---
name: motivation-check
description: "Check the quality of a change request in .council/input.md before design starts: does the Motivation say what real situation forces the change and why the current path fails there, is it free of design content and solution hints, does every FLOW-n name an actor, calls and an observable result, and can every CANT-n be checked from a plan. Live mode asks the user to fill gaps; eval mode writes .council/motivation-check.md."
version: 1.0.0
---

# Motivation check

Review the change request in `.council/input.md` and report gaps before anyone
designs a solution. This skill does not design, compare or pick plans, write an
ADR, implement code, or rewrite the input.

## Input

`.council/input.md` holds only three sections:

- `## Motivation`: prose explaining why a change is needed.
- `## User flows to optimize for`: items `FLOW-1`, `FLOW-2`, ...
- `## Must not break`: items `CANT-1`, `CANT-2`, ...

There is no Summary. Do not require one and do not draft one.

Read the whole file. Never edit it. Quote section names and item IDs exactly as
written in every finding. If the file or a section is missing or empty, report
that as a finding; do not fill the gap with guessed content. An item marked as
retired stays listed under its ID with its retired status; do not check it as an
active requirement.

## Check 1: the Motivation answers two questions

Judge the Motivation against these two questions only, each on its own:

1. **What real situation forces the change?** A concrete circumstance a user,
   integrator or operator is actually in, not a wish for a feature.
2. **Why does the current path fail in that situation?** What happens today when
   they try, and why that outcome is not acceptable.

For each question, quote the sentence(s) that answer it, or flag the answer as
missing or unclear and say what fact is absent. Do not add other required
questions (business value, urgency, success metrics, proposed design). A
Motivation that answers both questions is sufficient even if it is short.

## Check 2: no design content or solution hints in the Motivation

The Motivation states the problem; designers choose the solution. Flag passages
that already pick an approach, such as:

- a new or changed interface, function, parameter, event or error;
- a data layout, storage scheme or encoding;
- an algorithm, component split or sequence of implementation steps;
- wording such as "we should add", "by introducing", "the fix is" that settles
  the answer.

Describing current behavior in technical terms is fine: "calls to X revert when Y"
explains a present limitation. Flag only proposed mechanisms. For each finding,
quote the passage and say why it narrows the design space. Do not offer a
replacement design and do not rewrite the Motivation.

## Check 3: every FLOW-n is concrete

For each active FLOW-n, confirm it names:

- **an actor**: who performs the flow (a role, account type or calling contract);
- **the calls**: the actions or calls they make, in order;
- **an observable result**: what they or an outside observer can see afterwards
  (returned data, state that can be read, emitted events, a clear failure).

Name exactly which element is missing. Calls may be described at the level of
intent ("registers a policy, then queries it"); do not invent signatures or
demand implementation detail to make a flow concrete.

## Check 4: every CANT-n is checkable from a plan

For each active CANT-n, confirm a reviewer could hold a proposed plan against it
and decide whether the plan keeps it. A checkable item says:

- what behavior or property must stay true;
- under which conditions or for which callers;
- what a plan would have to show to demonstrate it (for example an unchanged
  interface, preserved stored data, an existing caller still succeeding).

Flag vague assurances ("nothing should break", "stay secure", "keep performance
good") and say what would make them checkable. Do not require a plan to exist,
do not assume a particular design, and do not claim any plan passes.

## Modes

### Live mode (a user is present)

Present the findings in the report structure below. Then ask the user only for
the missing facts or clarifications the findings name, grouped by section. The
user owns the input; suggest what is missing, but do not silently edit
`.council/input.md`. If there are no findings, say the input is ready and ask
nothing.

### Eval mode (unattended)

Never ask questions, never wait for a reply, and never edit
`.council/input.md`. Always write `.council/motivation-check.md`, creating the
`.council/` directory if needed, even when the input is clean or missing. Record
open gaps as findings, not as questions to the user. Do not infer facts the input
does not state.

## Report structure

Use this structure for `.council/motivation-check.md` (eval mode) and for the
findings shown to the user (live mode). Write "No findings." under any section
that has none.

```markdown
# Motivation check

## Readiness
Ready | Needs input. One sentence on the main gap, if any.

## Motivation: forcing situation
Answered | Missing | Unclear. Quote the evidence, or state the missing fact.

## Motivation: why the current path fails
Answered | Missing | Unclear. Quote the evidence, or state the missing fact.

## Design content and solution hints
- "<quoted passage>": why it presupposes a solution.

## User flows
| ID | Actor | Calls | Observable result | Finding |
|----|-------|-------|-------------------|---------|

## Must not break
| ID | Checkable | Finding |
|----|-----------|---------|

## Missing information
- <section or ID>: the fact the author needs to supply.
```

In the tables, mark each element present or missing and give the reason in the
Finding column. List retired items with the status "retired" and no finding.
