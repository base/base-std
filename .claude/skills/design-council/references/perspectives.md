# Design perspectives

Each block below is one design lens for a single designer pass. A caller may hand a
designer just one block, so every block stands on its own and repeats the rules that
bind every lens. A lens decides which trade-offs to favour. It never adds requirements,
drops a user flow or relaxes a must-not-break item. If the evidence leads two lenses to
the same design, say so; do not invent differences.

## minimal-change

Objective: the smallest change that fully serves every requirement and user flow and
keeps every must-not-break item.

- Binding for this lens: meet every requirement, cover every FLOW-n and CANT-n in the
  input, and respect the global invariant.
- Prefer mechanisms that already exist in the code (storage, roles, errors, events,
  dispatch paths) over new ones. New public surface needs a requirement or flow that
  cannot be served well without it.
- Measure size as added public functions, storage slots, errors, events and touched
  files, plus churn in existing callers.
- Limits: if the design introduces a count, size, depth or similar bound, take its value
  from what the flows need, and state what a lower and a higher value would cost. Small
  is not a reason to pick the minimum.
- New on-chain objects: weigh an owner or admin, the creator, or nobody as the party who
  may change the object after creation. Do not pick immutability just to avoid a setter
  or a role; count the cost of replacing the object and re-pointing every consumer.
- Evidence to examine: what the current interfaces and storage already support, and
  which gaps no existing mechanism can close.
- Trade-offs accepted: may leave some inefficiency or awkwardness in place if fixing it
  is not required; must say where a slightly larger change would give a flow a concrete
  benefit or remove a real risk.
- Not acceptable: meeting a requirement or serving a flow only partly to keep the diff
  small.

## hot-path-efficiency

Objective: keep the recurring cost of the most frequent operations as low as possible in
the worst case, without making the user flows harder to carry out.

- Binding for this lens: meet every requirement, cover every FLOW-n and CANT-n in the
  input, and respect the global invariant.
- Count storage reads and writes, external or cross-contract calls and loops on each hot
  path, before and after the change, and name the worst case (for example the deepest
  nesting or the longest list a caller can create).
- Prefer bounded, constant-cost checks on the hot path; move work to rarer
  administrative paths when that keeps semantics intact. Count the setup and update
  cost those paths then carry, not only the frequent call.
- Limits: size every bound from what the flows need, backed by evidence, and state the
  cost of a lower value (flows that no longer fit) and a higher value (worst-case cost).
  Do not invent usage numbers or add headroom nobody asked for.
- New on-chain objects: state who may change each one after creation (owner or admin,
  creator, or nobody) and what each option costs the flows, including replacing an
  immutable object and re-pointing every consumer.
- Evidence to examine: the code of the hot paths as they are today and how often each
  path runs relative to configuration paths.
- Trade-offs accepted: more implementation complexity, extra bookkeeping on write paths
  or explicit limits, when the code shows they lower the recurring cost. Every cost claim
  must be traced to code, not guessed.
- Not acceptable: unbounded work that any caller can trigger on a frequent path.

## compatibility-first

Objective: the least disruption to existing callers, stored data, integrations and the
way the change is activated, while fully serving the new user flows.

- Binding for this lens: meet every requirement, cover every FLOW-n and CANT-n in the
  input, and respect the global invariant.
- Keep existing function signatures, return values, errors, events and storage layout
  unchanged where possible; add rather than alter.
- Check every existing caller, mock and test that depends on current behaviour, and
  state how already-stored data is read after the change.
- Describe activation: what happens before and after the change takes effect, and
  whether any caller must act.
- Limits: derive any new bound from the flows' needs and state what a lower and a higher
  value would cost, including whether raising it later would disrupt callers.
- New on-chain objects: compare an owner or admin, the creator, or nobody as the party
  who may change the object after creation. Treat creator and admin as different trust
  models, and count the burden on existing consumers if an immutable object has to be
  replaced and every reference re-pointed.
- Evidence to examine: public interfaces, storage slot derivation, existing tests and
  any documented behaviour callers rely on.
- Trade-offs accepted: extra code paths, adapters or duplicated entry points when they
  keep existing users working without changes.
- Not acceptable: silent behaviour changes for existing callers or stored data.

## auditability-first

Objective: make state transitions, authority boundaries and invariant reasoning easy to
inspect, while fully serving the user flows.

- Binding for this lens: meet every requirement, cover every FLOW-n and CANT-n in the
  input, and respect the global invariant.
- Make each state change explicit and single-purpose, with clear authorization checks
  and an event for every change an observer needs to follow.
- Prefer designs where each invariant can be checked locally (one function, one slot)
  over designs that need whole-system reasoning.
- Give every failure a specific error, and explain from the code why each invariant and
  each must-not-break item holds. Read existing tests for evidence; the plan itself
  proposes no tests.
- Limits: state each new bound, why the flows need that value, and what a lower and a
  higher value would cost.
- New on-chain objects: compare an owner or admin, the creator, or nobody as the party
  who may change the object after creation, and state exactly who may change what.
  Immutability is not automatically the safest choice: weigh it against the flows and
  the cost of replacing the object and re-pointing every consumer.
- Evidence to examine: role and permission checks, error and event definitions, and how
  existing tests express invariants.
- Trade-offs accepted: some additional code, events or validation when they reduce the
  reasoning needed to trust the change.
- Not acceptable: hidden side effects, implicit authority, or state reachable only
  through undocumented paths.
