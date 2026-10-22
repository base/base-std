---
name: design-council
description: "Run several independent designer passes on the same change, each from a different perspective, and choose one plan. Live mode runs the passes in isolation, shows the plans side by side and lets the architect pick or override; eval mode leaves running and picking to an external runner. Use when asked to convene a design council, compare design options or produce competing design plans."
version: 1.0.0
---

# Design council

Produce several complete, independent design plans for one change, each from a
different perspective, so the decision maker can compare real alternatives. This skill
coordinates the passes and, in live mode, the comparison. It does not implement code
and does not write an ADR.

## Tool rules for designer passes

Every designer pass follows the tool rules of the design-plan skill, before anything
else: read files with the read tool (or hashread, whichever is available), explore with
the grep, find and ls tools, write the plan with the write and edit tools, and use bash
only for design-plan's exact self-lint command, from the workspace root, with its
canonical paths and flags. No shell exploration, no shell probes (not even `echo`,
`true` or `pwd`), no wrappers and no alternate plan paths.

Setting up working copies and collecting finished plans is the coordinator's job (or
the external runner's), never something a designer does through its shell.

## Inputs

- **`.council/input.md`**, unchanged. It holds only `## Motivation`,
  `## User flows to optimize for` (FLOW-n) and `## Must not break` (CANT-n). There is no
  Summary; do not require or write one here.
- **The same code snapshot** for every pass.
- **The design-plan skill** (`../design-plan/SKILL.md`, resolved from this skill's
  directory) with its bundled references: plan template, global invariant, linter and
  input parser. Do not copy them here.
- **Perspectives** in `references/perspectives.md` (resolved from this skill's
  directory): `minimal-change` plus three other lenses, one `## <id>` block each. A pass
  receives exactly one block.

## Live mode (an architect is present)

### 1. Run the passes independently

1. Run one designer pass per perspective in `references/perspectives.md`, always
   including `minimal-change`.
2. Give each pass a fresh context and its own working copy with identical input and
   code. Supply only the perspective id, its block and the shared inputs. Do not show a
   pass any other candidate, draft or conclusion until all passes have finished.
3. Each pass follows design-plan, writes its own `.council/plan.md` in its own copy and
   repeats the self-lint until it exits 0.
4. Passes may run in parallel or one after another; either way each needs a fresh
   context and an isolated output. If isolation is not possible, say so plainly instead
   of calling the passes independent.
5. When a pass finishes, the coordinator keeps its plan under the perspective id (for
   example `.council/plans/<id>.md` in the live workspace). Designers never write to a
   shared output file.

### 2. Compare side by side

Only after every pass has finished, show the candidates in one table or parallel
sections with, for each:

- perspective id and plan path;
- the approach in one or two sentences;
- coverage of every FLOW-n and CANT-n, and anything left uncertain;
- added public surface (functions, storage, errors, events);
- worst-case cost on the hot paths;
- compatibility and activation impact;
- main trade-offs and open questions;
- lint status.

A clean lint run shows structure only, not that the design is correct; say which
claims you checked against the code. Report failed or incomplete passes as such; do not
drop them silently or present them as successes.

### 3. The architect decides

The architect picks one candidate or overrides. You may recommend one and say why;
`minimal-change` is the baseline for comparison, not the automatic winner. If the
architect's override changes plan content (for example combining ideas from two
candidates), produce one coherent revised plan and run the self-lint and the content
review again. An override never waives a requirement, a FLOW-n, a CANT-n or the global
invariant.

## Eval mode (no user, run by a script)

An external runner sets up the independent passes, gives each one perspective, collects
the plans and picks the plan. Inside an assigned pass:

- follow design-plan with the given perspective and finish with a lint-clean
  `.council/plan.md`;
- do not start a nested council, compare candidates or pick a winner;
- never ask questions, prompt a user or wait for approval;
- record unresolved facts as uncertainties in the plan; never invent them.

## Checklist

- [ ] Every perspective in `references/perspectives.md` ran, including `minimal-change`.
- [ ] Each pass had a fresh context, an isolated copy and identical inputs.
- [ ] Every candidate is lint-clean, or its failure is reported.
- [ ] Live mode: the comparison came after all passes and the architect made the call.
- [ ] Eval mode: no questions, no nested council, no selection inside a pass.
