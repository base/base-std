---
name: design-plan
description: "Run one designer pass from a given perspective: read .council/input.md, the global invariant and the current code, then write .council/plan.md in the plan template with every requirement traced to a FLOW-n or a Motivation sentence, every FLOW-n and CANT-n covered, and the plan lint-clean. Use when asked for a single design plan for a precompile change."
version: 2.0.0
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
  impact on the design, in §6 Open questions. Do not invent facts.

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

Two decisions need explicit reasoning under every perspective. A lens never excuses
skipping them, and a design that adds no limit or no new object does not invent one.

**Limits.** When the design adds a bound (a maximum count, size, depth, length or
similar), size it from the user flows:

1. Name the active flows that consume the bounded resource and what each needs in
   practice (for example how many entries a typical caller needs).
2. Pick the value that serves those needs, citing the input or code that shows them.
3. Say what a lower value would cost: which supported uses fail or need extra calls.
4. Say what a higher value would cost: extra storage, loop iterations, gas or attack
   surface on the affected paths.

Do not choose the smallest value that works only because it keeps the surface or the
code small. A small value is fine when the flows show it is enough; equally, do not add
headroom no flow asks for. If a usage fact is unknown, handle it as the mode says
instead of inventing numbers.

**Who can change a new object.** For every new on-chain object (a record, entry,
configuration or similar that lives in storage after it is created), decide who may
modify it afterwards and what they may modify. The options are:

- an owner or admin role;
- the creator of the object;
- nobody: the object is immutable once created.

Weigh each option against the flows: who needs to update the object, who should be
trusted to, and what new authority each option brings. Creator control and admin
control are different trust models; do not treat them as interchangeable. For an
immutable object, count the cost of change: a replacement must be created and every
consumer that references the old one must be re-pointed, which takes one call per
consumer by whoever controls it, and some consumers may not be re-pointable at all.
Choose on fit with the flows and constraints, not on a general preference for
mutable or immutable data. Add a setter or role only when the chosen option needs it.

Carry both decisions into the plan: state the chosen value and authority with their
reasons in §1, enforce them in the numbered steps of §3, show their effect in the
affected §4 flows, record the lower/higher and rejected authority options with their
costs in §5, and reflect the resulting costs and consumers in §9 and §11.

### 3. Write `.council/plan.md`

Read `references/plan-template.md` and write its structure into `.council/plan.md`
with the write tool; do not copy it with a shell command.

- Keep the front matter keys, the title, all eleven numbered headings, the `# Reference`
  heading between §6 and §7, the `### Storage` subheading, every table header and their
  order exactly as written.
- Fill the front matter: `plan_id`, `perspective`, `inputs_ref`, `breaking`,
  `activation` and the six `surface` counts.
- Replace every placeholder; remove the instruction comments and sample rows. No `TBD`.
- A table with no rows keeps its header and gets a line `None: <reason>` under it. The
  requirement trace, hot-path and invariant tables always have rows.
- Keep the body at or under 3500 words. Be concrete; do not pad.

#### How to write it

The plan has two parts. Sections 1 to 6 are read by people who want to understand the
design quickly. Sections 7 to 11 are the reference part, checked line by line.

- Use concise technical English: short sentences, one idea each, active voice, the
  same term for the same thing throughout.
- Explain with prose, code and numbered steps. Add a mermaid diagram (```mermaid)
  when a flow between callers, the precompile and storage is easier to see than to
  read; the diagram supplements the numbered steps, it does not replace them.
- Avoid large tables in sections 1 to 6. A table there has at most six body rows; the
  Storage table is the only exception.
- There is no edge-case or test-plan section. Do not add one, and do not name tests in
  the trace or invariant tables.

#### Readable part (§1 to §6)

- **§1 Approach.** A few short paragraphs: what the design does, and why it meets the
  Motivation, the user flows and the must-not-break items. Name the main mechanism
  and the main thing it reuses.
- **§2 Interface.** Exactly one fenced block tagged `solidity` holding every new or
  changed function, type, error and event with its full signature (visibility,
  mutability, returns). Each declaration line ends with `// new` or `// changed`; a
  short note may follow the marker, and a brief comment may sit on the line above.
  Do not put unchanged declarations in the block. Write the explanation in full
  sentences after the block. If the interface does not change, the block contains
  only the line `// No interface change.`
- **§3 Changes.** One `###` subsection per behaviour change, titled in plain words
  and ending with its ID, for example `### Reject unknown policy types (BEH-1)`.
  The first line under the title has this exact shape, with real names and one flag:

  ```text
  Functions: `name`, `name`; changes existing behaviour: yes|no
  ```

  Then give the logic as numbered steps in execution order: each check and the error
  it raises, the role that authorizes each privileged action, each state change and
  each event. If the change is breaking, say which inputs now give a different
  outcome and why; keep `breaking` in the front matter consistent.
- **§3 Storage.** One row per field with an `ST-n` ID: slot or derivation, type and
  bit range, status (`new`, `changed`, `unchanged`) and whether the Solidity mock and
  the Rust precompile use the same layout. Existing slots keep their meaning, type
  and position; describe any packing into free bits explicitly.
- **§4 User flows.** One `###` subsection per FLOW-n, in input order, titled in plain
  words and ending with its ID, for example `### Issuer combines two policies
  (FLOW-1)`. Walk it as numbered steps: setup, the call, state changes and events,
  and what the caller observes. A retired flow keeps its subsection and starts with
  `retired: not applicable`.
- **§5 What this plan gives up.** The deliberate tradeoffs and what each costs. A
  tradeoff never drops a requirement, flow or must-not-break item.
- **§6 Open questions.** Real open questions and their impact on the design, or
  `None`. Do not use this section to hide behaviour the plan should specify.

#### Reference part (§7 to §11)

- **§7 Requirement trace.** One row per requirement, in your own words. The Source is
  either active FLOW-n IDs (`FLOW-1, FLOW-3`) or one complete Motivation sentence
  copied verbatim as `Motivation: "..."`. Never mix both forms in one row; never
  cite a retired flow. Escape a literal `|` as `\|`. Change IDs are the `BEH-n` and
  `ST-n` IDs from §3; every one must exist there.
- **§8 New surface.** Additions only, one row per item counted in the front-matter
  `surface`, with Kind one of the six surface keys. Every new function, error and
  event is declared `// new` in §2 and has its own row here. Reused or changed items
  count zero. A new storage slot cites its new ST row; several fields packed into one
  new slot count as one slot. The rows equal the front-matter counts.
- **§9 Hot-path cost.** Each affected path plus `transfer`, `transferFrom`, `mint` and
  `burn`, even when unchanged. Worst-case storage operations per call, signed deltas
  against the pre-change code, the condition behind each worst case, the slot behind
  each packing claim and the target of each external call.
- **§10 Invariants.** One row per CANT-n in input order (retired ones start How it
  holds with `retired:`), then `G-INV-1`, then any NEW-n this plan adds. Status is
  `holds` or `at risk`; say how each holds and cite the change IDs. For `G-INV-1`,
  name every call target or state that there are none.
- **§11 Interactions.** Every mechanism the change touches (policies, roles, pause,
  allowances, other precompiles, event consumers) and how; for the others, say why
  they do not apply.

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
- `G-INV-1` holds consistently in §3 changes, §4 flows, §9 external calls, §10 and §11.
- Surface counts, `breaking` and `activation` agree with §2, §3 and §8.
- Every limit the design adds has a value derived from the flows, with the cost of a
  lower and a higher value stated; none is the minimum by default.
- Every new on-chain object states who can change it after creation, compares owner or
  admin, creator and nobody against the flows, and for immutability counts the cost of
  re-pointing every consumer.
- The readable part reads well on its own: a reviewer who stops after §6 understands
  the design, its interface, its behaviour and its costs.

Then stop. Report the plan path and the final lint result.
