---
name: design-plan
description: "Run one designer pass from a given perspective: read .council/input.md, the global invariant and the current code, then write .council/plan.md in the plan template with every requirement traced to a FLOW-n or a Motivation sentence, every FLOW-n and CANT-n covered, and the plan lint-clean. Use when asked for a single design plan for a precompile change."
version: 1.0.0
---

# One designer pass

Write one design plan, from one perspective, for the change described in
`.council/input.md`. The output is `.council/plan.md`. This skill does not compare
plans, pick a winner, write an ADR or implement the change.

## Tool use

Work in the workspace copy with file tools, and keep the shell for one command only.

- Read files with the read tool (or hashread, whichever is available). Explore with
  the grep, find and ls tools: the input, the bundled references and the source code.
- Create and update `.council/plan.md` with the write and edit tools.
- Use bash for exactly one command, the self-lint, run from the workspace root and
  written exactly like this:

  ```sh
  python3 -B .claude/skills/design-plan/references/lint.py .council/plan.md --input .council/input.md
  ```

  Repeating that same command after fixing the plan is fine.
- Run no other shell command: no cat, sed, grep, ls, cp, mkdir, git, Python scripts,
  heredocs, wrappers, variable assignments, pipes, redirects, chained commands or
  extra flags. Do not use the shell to find the working directory either.
- Never probe or test the shell, not even with `echo`, `true` or `pwd`. The only bash
  command in a designer pass is the self-lint command above.

## Inputs

- **Perspective.** A design lens supplied by the caller (for example "smallest change
  that meets every requirement"). It shapes which design you choose. It never permits
  dropping a requirement, a user flow or a must-not-break item. If no perspective is
  given, use `minimal-change`.
- **`.council/input.md`.** It holds only three sections: `## Motivation`,
  `## User flows to optimize for` (FLOW-n) and `## Must not break` (CANT-n). There is
  no Summary; do not require one and do not invent one.
- **References bundled with this skill** (resolve them against this skill's directory,
  not the workspace):
  - `references/plan-template.md`: the exact plan structure.
  - `references/global-invariants.md`: `G-INV-1`, which applies to every plan.
  - `references/lint.py`: the structural linter.
  - `references/plan_inputs.py`: the input parser the linter imports from its own
    directory.
- **The code.** The current contracts, precompile implementation, mocks and tests in
  the target workspace.

Never edit `.council/input.md` or the source code. Keep every ID from the input,
including retired items.

## Modes

- **Live mode** (a user is present): ask a question only when an essential fact is
  still unresolved after reading the input and the code.
- **Eval mode** (no user, run by a script): never ask questions and never wait for an
  answer. Resolve what the code supports. State what remains uncertain, and its
  impact on the design, in §10. Do not invent facts.

## Workflow

### 1. Read before drafting

1. Read `.council/input.md` completely. List every Motivation sentence, every FLOW-n
   and every CANT-n, and note which items are retired.
2. Read `references/plan-template.md` and `references/global-invariants.md`.
3. Read the code the change touches: public interfaces, storage layout and slot
   derivation, authorization roles, errors and events, the hot paths (`transfer`,
   `transferFrom`, `mint`, `burn`), the Solidity mock and the Rust precompile, and the
   existing tests. Find out what already exists before you add anything; reuse beats
   new surface.
4. Record which input and code snapshot you read in `inputs_ref`, using what the
   caller supplied or what the files show. Do not run git to find it, and do not
   invent snapshot data.

### 2. Choose the design

Pick the design that the perspective favors and that still meets every requirement.
Prefer reusing existing functions, roles, storage, errors and events. Check the design
against `G-INV-1` now: the precompile must not call a non-precompile contract while it
carries out the change. Calls between precompiles are allowed, and the rule does not
restrict who calls the precompile.

### 3. Write `.council/plan.md`

Read `references/plan-template.md` and write its structure into `.council/plan.md`
with the write tool; do not copy it with a shell command.

- Keep the front matter keys, all ten numbered headings, the five `### Changes`
  subheadings, every table header and their order exactly as written.
- Fill the front matter: `plan_id`, `perspective`, `inputs_ref`, `breaking`,
  `activation` and the six `surface` counts.
- Replace every placeholder; remove the instruction comment and sample rows. No `TBD`.
- A table with no rows keeps its header and gets a line `None: <reason>` under it.
- Keep the body under 4000 words. Be concrete; do not pad.

Section by section:

- **§1 Approach.** Two to five sentences: the design and why it meets the Motivation,
  the flows and the constraints.
- **§2 Requirement trace.** One row per requirement. The Source is either active FLOW-n
  IDs (`FLOW-1, FLOW-3`) or one complete Motivation sentence copied verbatim as
  `Motivation: "..."`. Never mix both forms in one row; never cite a retired flow.
  Escape a literal `|` as `\|`. Every requirement maps to at least one change and one
  test.
- **§3 Changes.** Stable, unique IDs: IF-n, ST-n, BEH-n, ERR-n, EVT-n.
  - Interface: full Solidity signatures with visibility, mutability and returns.
  - Storage: one row per field with slot or derivation, type and bit range, status,
    and whether the mock and Rust layouts match.
  - Behavior: before and after for the same inputs, including the role behind every
    privileged action, state changes, errors and events. Mark breaking changes and say
    why; keep `breaking` in the front matter consistent with this table.
  - New surface: additions only. Reused items count zero; fields packed into one new
    slot count as one storage slot. The rows must equal the front-matter counts.
- **§4 User flows.** One row per FLOW-n, in the order of the input. Walk each flow from
  start to finish as the template's Steps column describes, and name the change IDs and
  tests it relies on. Retired flows keep their row, marked as the template says.
- **§5 Hot-path cost.** Each affected path plus `transfer`, `transferFrom`, `mint` and
  `burn`, even when unchanged. Worst-case storage operations per call, signed deltas
  against the pre-change code, the condition behind each worst case, the slot behind
  each packing claim and the target of each external call.
- **§6 Invariants.** One row per CANT-n (retired ones marked retired), then `G-INV-1`,
  then any NEW-n this plan adds. Say how each holds, with change IDs and tests. For
  `G-INV-1`, name every call target or state that there are none.
- **§7 Interactions.** Every mechanism the change touches (policies, roles, pause,
  allowances, other precompiles, event consumers), and why the others do not apply.
- **§8 Edge cases and test plan.** Define every test named in §2, §4 and §6, with setup,
  action and observable expected result. Names follow
  `test_{function}_{outcome}_{variant}`. Include a test that would catch a call to an
  ordinary contract.
- **§9 What this plan gives up.** Deliberate tradeoffs and their cost. A tradeoff never
  drops a requirement.
- **§10 Open questions.** Genuine questions and their impact, or `None`. Do not hide
  unspecified behavior here.

### 4. Self-lint until clean

The linter runs standalone from this skill's `references/` directory. It needs only
Python 3 and its sibling `plan_inputs.py`; no package install or PYTHONPATH setup.
Its arguments, for reference only, are
`python3 references/lint.py <plan> --input <input>`.

During a designer pass, run exactly this command from the workspace root and
nothing else:

```sh
python3 -B .claude/skills/design-plan/references/lint.py .council/plan.md --input .council/input.md
```

- Always pass `--input`, so sources and FLOW/CANT coverage are checked.
- Exit 0 is lint-clean. Exit 1 lists problems as `§n RULE: message`: fix the plan only,
  with the edit or write tool, then rerun the same command. Repeat until exit 0.
- Exit 2, or a Python error, is not lint-clean. Report the problem; do not edit the
  linter and do not claim the plan is clean.

### 5. Review the content

The linter checks structure, not design quality. After it passes, check:

- Every FLOW-n, CANT-n and Motivation sentence is answered by a concrete change.
- Every claim about existing code matches the code you read.
- `G-INV-1` holds consistently in §3 behavior, §4 flows, §5 external calls, §6, §7 and §8.
- Surface counts, `breaking` and `activation` agree with §3.

Then stop. Report the plan path and the final lint result.
