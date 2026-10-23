# Global invariant

One invariant applies to every plan, for every case. Plans cite it as `G-INV-1` in the
Invariants section. Constraints specific to one change are `CANT-*` items in that case's
`input.md`; see [`README.md`](README.md).

**Designer-visible.**

## G-INV-1: no calls to non-precompile contracts

The precompile never calls a non-precompile contract to implement the change.

- Calls between precompiles are allowed.
- The rule covers calls the precompile makes while carrying out the change. It does not
  restrict who may call the precompile.

### What a judge checks

A claim that the plan holds the invariant is not enough. The judge compares the claim
with the call path the plan describes, in these sections:

- Changes: the behavior subsections and every call target they name.
- User flows: each step that reaches another contract.
- Hot-path cost: the external-calls column.
- Invariants: whether the plan states how it holds `G-INV-1`.
- Interactions: every other component the change touches.

The plan fails the invariant if any of these describes a call from the precompile to a
non-precompile contract, even when the Invariants section says otherwise.

### Violation

A plan adds a hook: during the new behavior, the precompile calls an ordinary deployed
contract, such as an admin-supplied checker, and uses its answer to decide whether the
operation succeeds. The decision now depends on code the precompile does not control.

### Non-example

A plan has one precompile read state that another precompile owns, or call that
precompile, and use the result. Both sides are precompiles, so the invariant holds.

## Not listed here

Repository rules that the rubric already grades are not listed here. This file holds only
the invariant a judge checks separately.
