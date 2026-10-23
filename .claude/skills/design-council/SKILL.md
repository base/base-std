---
name: design-council
description: "Run several independent designer passes on the same change, each from a different perspective, and choose one plan. Live mode runs the passes in isolation, shows the plans side by side and lets the architect pick or override; eval mode leaves running and picking to an external runner. Use when asked to convene a design council, compare design options or produce competing design plans."
version: 1.1.0
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

- perspective id, plan id and the path to the full plan, so the architect can open any
  candidate in full;
- the approach in one or two sentences;
- how well it serves each active FLOW-n and requirement from the Motivation, not only
  whether it covers them: what the caller has to do, the setup and update effort, the
  capacity the flow actually gets, the trust it asks for and its recurring cost;
- whether every CANT-n and the global invariant still hold, and anything left uncertain;
- each new limit with the value chosen, the flow evidence behind it and the cost of a
  lower or a higher value;
- for every contract or stored record the design adds, which party (if any) may modify
  it once it exists and, when none may, the price of deploying a replacement and
  updating everything that points at the old one;
- added public surface (functions, storage, errors, events);
- worst-case cost on the hot paths;
- compatibility and activation impact;
- main trade-offs and open questions;
- lint status.

Point to the plan sections and change ids (BEH-n, ST-n) behind each entry instead of
restating them.

A clean lint run shows structure only, not that the design is correct, and a small
surface count shows economy, not fitness. Say which claims you checked against the
code and which are assumptions. Report unmet constraints, uncertain claims and failed
or incomplete passes visibly and separately; do not drop them silently or present them
as successes.

You may add a recommendation. Keep it apart from the table, give its reasons and its
costs, and leave the choice to the architect. Base it on how well each candidate
serves the user flows and requirements, weighed against what it costs:

- `minimal-change` is the reference point the other candidates are measured against. It
  wins when the evidence shows it serves the flows best, never by default and never as
  a tie-break only because it adds less.
- A larger candidate earns its extra surface only through a concrete, evidenced benefit
  to a stated flow or requirement, not through speculative features or headroom.
- Treat a candidate that serves a flow only with heavy caller effort, a capacity below
  what the flow needs, or a hidden trust assumption as weaker on that flow, even if it
  technically covers it.

### 3. The architect decides

Ask the architect to do one of the following:

- **select** a named candidate (the recommended one or another);
- **override** by asking for specific revisions, or for a combination of candidates;
- **reject** all candidates and say what is missing.

Wait for an explicit answer. Silence, list order, a clean lint run or your
recommendation is not approval. If no candidate is acceptable, go back to revision
(new or revised passes) instead of inventing a winner. Never offer a failed, incomplete
or constraint-violating plan as ready for handoff.

Overrides:

- Selecting a different complete candidate changes the selection only, never that
  plan's content.
- An override that changes content produces one complete, coherent revised plan in the
  plan template, not a patch list or a union of incompatible fragments. Keep
  traceability, the BEH-n and ST-n changes, FLOW-n and CANT-n coverage, interface
  declarations, surface counts, breaking and activation metadata, and code-backed
  claims consistent across the whole plan.
- A revision is a designer pass: it writes `.council/plan.md` in its own working copy,
  runs design-plan's exact self-lint until it exits 0, and then the content review. Only
  the coordinator collects and stores the result.
- Show the architect what changed and how the trade-offs moved, and get an explicit
  confirmation of the revised plan.
- An override never waives a requirement, a FLOW-n, a CANT-n or the global invariant.

### 4. Finalize and hand off

1. Keep every original candidate under `.council/plans/<id>.md` unchanged.
2. Once the architect has confirmed a lint-clean plan, the coordinator copies that exact
   plan to `.council/plan.md` in the live workspace with the file tools. Never silently
   overwrite a different selection that is already there.
3. In the reply, record the chosen plan id and perspective, the final path, the
   architect's confirmation, the rationale and trade-offs the architect stated, and,
   for a revised plan, which candidates it came from. Do not add selection notes to
   the plan itself, and do not invent reasons the architect did not give.
4. Hand off to the adr-writer skill (`../adr-writer/SKILL.md`) with explicit inputs:
   the unchanged `.council/input.md`, the confirmed main-plan path, and the paths of
   the other complete candidates as alternatives (for a revised plan, keep its source
   candidates among them). List failed or incomplete passes separately; they are not
   alternatives.
5. The council stops here. The adr-writer writes the Summary and the ADR.

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
- [ ] Live mode: any recommendation rests on flow and requirement fit, with
      `minimal-change` as the reference point rather than the default.
- [ ] Live mode: the comparison shows each added bound with its evidence and costs, and
      the modification rights over each added contract or record.
- [ ] Live mode: the comparison came after all passes, and the architect explicitly
      selected, overrode or rejected; no approval means no handoff.
- [ ] Live mode: any revised plan was lint-clean, reviewed again and confirmed.
- [ ] Live mode: original candidates are preserved, and the handoff names one main
      plan and the other complete candidates.
- [ ] Eval mode: no questions, no nested council, no selection inside a pass.
