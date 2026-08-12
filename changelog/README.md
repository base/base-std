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
  <hardfork>_<feature>.md    # one scoped feature change
```

- **One file per scoped feature change**, named `<hardfork>_<feature>.md` — lowercase hardfork name
  (e.g. `cobalt`), an underscore, and a short snake_case feature name (e.g. `multiplier`, `seize`,
  `composite_policy`).
- Files sort together by hardfork prefix, so the directory listing reads as a per-fork list of that
  fork's line items, in activation order.
- Keep the feature name short — it maps to a release-notes line item, not the full feature title.

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
| Cobalt (upcoming) | Schedule Multiplier Updates (ERC-8056) | B20 Asset | [cobalt_multiplier](cobalt_multiplier.md) |
| Cobalt (upcoming) | Seize + `burnBlocked` deprecation | B20 (Asset + Stablecoin) | [cobalt_seize](cobalt_seize.md) |
| Cobalt (upcoming) | Composite Policies (UNION/INTERSECT) | PolicyRegistry | [cobalt_composite_policy](cobalt_composite_policy.md) |
