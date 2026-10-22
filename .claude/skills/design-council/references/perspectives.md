# Design perspectives

Each block below is one design lens for a single designer pass. A caller may hand a
designer just one block, so every block stands on its own.

Rules shared by every lens (repeated here so a single block is never read without them):
every lens must meet every requirement, cover every FLOW-n and CANT-n in the input, and
respect the global invariant. A lens decides which trade-offs to favour. It never adds
requirements, drops a user flow or relaxes a must-not-break item. If the evidence leads
two lenses to the same design, say so; do not invent differences.

## minimal-change

Objective: the smallest change that meets every requirement and every must-not-break
item.

- Prefer mechanisms that already exist in the code (storage, roles, errors, events,
  dispatch paths) over new ones. New public surface needs a requirement that cannot be
  met without it.
- Measure size as added public functions, storage slots, errors, events and touched
  files, plus churn in existing tests and callers.
- Evidence to examine: what the current interfaces and storage already support, and
  which gaps no existing mechanism can close.
- Trade-offs accepted: may leave some inefficiency or awkwardness in place if fixing it
  is not required; must say where a slightly larger change would remove a real risk.
- Not acceptable: meeting a requirement only partly to keep the diff small.

## hot-path-efficiency

Objective: keep the recurring cost of the most frequent operations as low as possible in
the worst case.

- Count storage reads and writes, external or cross-contract calls and loops on each hot
  path, before and after the change, and name the worst case (for example the deepest
  nesting or the longest list a caller can create).
- Prefer bounded, constant-cost checks on the hot path; move work to rarer
  administrative paths when that keeps semantics intact.
- Evidence to examine: the code of the hot paths as they are today and how often each
  path runs relative to configuration paths.
- Trade-offs accepted: more implementation complexity, extra bookkeeping on write paths
  or explicit limits, when the code shows they lower the recurring cost. Every cost claim
  must be traced to code, not guessed.
- Not acceptable: unbounded work that any caller can trigger on a frequent path.

## compatibility-first

Objective: the least disruption to existing callers, stored data, integrations and the
way the change is activated.

- Keep existing function signatures, return values, errors, events and storage layout
  unchanged where possible; add rather than alter.
- Check every existing caller, mock and test that depends on current behaviour, and
  state how already-stored data is read after the change.
- Describe activation: what happens before and after the change takes effect, and
  whether any caller must act.
- Evidence to examine: public interfaces, storage slot derivation, existing tests and
  any documented behaviour callers rely on.
- Trade-offs accepted: extra code paths, adapters or duplicated entry points when they
  keep existing users working without changes.
- Not acceptable: silent behaviour changes for existing callers or stored data.

## auditability-first

Objective: make state transitions, authority boundaries and invariant reasoning easy to
inspect and test.

- Make each state change explicit and single-purpose, with clear authorization checks
  and an event for every change an observer needs to follow.
- Prefer designs where each invariant can be checked locally (one function, one slot)
  over designs that need whole-system reasoning.
- Give every failure a specific error, and list the tests that would prove each
  invariant and each must-not-break item.
- Evidence to examine: role and permission checks, error and event definitions, and how
  existing tests express invariants.
- Trade-offs accepted: some additional code, events or validation when they reduce the
  reasoning needed to trust the change.
- Not acceptable: hidden side effects, implicit authority, or state reachable only
  through undocumented paths.
