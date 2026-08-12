# Changelog

Per-hardfork, per-feature migration notes for the Base precompile standard. Each entry is a focused,
code-forward changelog for **one scoped feature change crossing a hardfork boundary** — the
API / function / event / error deltas behind a single line item in a hardfork's release notes (e.g.
Cobalt's "Schedule Multiplier Updates").

This complements the product references under [`docs/`](../docs): `docs/` describes how a product
works *today*; `changelog/` describes what changes *at a hardfork* and how to migrate across it.

## Layout

```
changelog/
  <ordinal>_<Hardfork>_<Product>_<feature>.md    # one scoped feature change
```

- **One file per scoped feature change**, named `<ordinal>_<Hardfork>_<Product>_<feature>.md`:
  - `<ordinal>` — 2-digit, zero-padded hardfork activation sequence number, assigned once per
    hardfork (never per file). See [Hardfork ordinals](#hardfork-ordinals) below. This makes sort
    order correct by construction — a flat directory listing always groups and orders by activation
    order, independent of whether codenames happen to be alphabetical.
  - `<Hardfork>` — PascalCase codename (e.g. `Cobalt`).
  - `<Product>` — PascalCase token matching the same product's directory under
    [`docs/`](../docs) and [`test/unit/`](../test/unit) (e.g. `B20Asset`, `PolicyRegistry`). For a
    change spanning both B20 variants, use the shared-surface token `B20`.
  - `<feature>` — short, lowercase snake_case slug mapping to a release-notes line item (e.g.
    `multiplier`, `seize`, `composite_policy`).
- Never rename or renumber a shipped entry. New hardforks get the next ordinal; new features get a
  new file under an existing ordinal.

### Hardfork ordinals

| Ordinal | Hardfork | Status |
| --- | --- | --- |
| `01` | Beryl | live |
| `02` | Cobalt | upcoming |

Assign the next ordinal here before naming the first entry for a new hardfork.

## What each entry contains

Keep it **minimal and migration-focused** — do not restate unchanged behavior. A good entry has:

1. **Audience + one-paragraph summary**, leading with the compatibility promise: what still works,
   what is deprecated-but-still-dialable, and what is new. State plainly whether the fork is live yet.
2. **A mapping table** — old symbol → new symbol → status (`deprecated-dialable` / `renamed` / `new`)
   → one-line why. Cover functions, events, and errors, with **real** signatures and selectors.
3. **"New at `<hardfork>` (adopt these)"** — the new surface and its lifecycle.
4. **Guarantees / edge cases** — a short Q&A a careful integrator would ask, each answered with the
   precise on-chain behavior.

Verify every function signature, event signature/topic0, error selector, 4-byte function selector,
and ERC-165 interface id against the source (`src/interfaces/**` and the base/base ABIs) **before
citing it** — do not rely on memory. Selectors can be checked with `cast sig` / `cast keccak`.

## Index

| Hardfork | Feature | Product | Entry |
| --- | --- | --- | --- |
| Cobalt (upcoming) | Schedule Multiplier Updates (ERC-8056) | B20 Asset | [02_Cobalt_B20Asset_multiplier](02_Cobalt_B20Asset_multiplier.md) |
| Cobalt (upcoming) | Seize + `burnBlocked` deprecation | B20 (Asset + Stablecoin) | [02_Cobalt_B20_seize](02_Cobalt_B20_seize.md) |
| Cobalt (upcoming) | Composite Policies (UNION/INTERSECT) | PolicyRegistry | [02_Cobalt_PolicyRegistry_composite_policy](02_Cobalt_PolicyRegistry_composite_policy.md) |
