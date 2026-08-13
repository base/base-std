# Changelog

This directory holds per-hardfork, per-feature migration notes for the Base precompile standard.
Each entry is a focused, code-forward changelog for one scoped feature change that crosses a
hardfork boundary: the API, function, event, and error deltas behind a single line item in a
hardfork's release notes (for example, Cobalt's "Schedule Multiplier Updates").

This complements the product references in [`docs/`](../docs). `docs/` describes how a product
works today. `changelog/` describes what changes at a hardfork and how to migrate across it.

## Layout

```
changelog/
  <ordinal>_<Hardfork>_<Product>_<feature>.md    # one scoped feature change
```

Each file name has four parts:

- `<ordinal>`: a 2-digit, zero-padded hardfork activation sequence number, assigned once per
  hardfork, never per file. See [Hardfork ordinals](#hardfork-ordinals). This keeps sort order
  correct by construction: a flat directory listing always groups and orders files by activation
  order, regardless of whether the codenames happen to be alphabetical.
- `<Hardfork>`: the PascalCase codename, for example `Cobalt`.
- `<Product>`: a PascalCase token matching the same product's directory under
  [`docs/`](../docs) and [`test/unit/`](../test/unit), for example `B20Asset` or `PolicyRegistry`.
  For a change that spans both B20 variants, use the shared-surface token `B20`.
- `<feature>`: a short, lowercase snake_case slug that maps to a release-notes line item, for
  example `multiplier`, `seize`, or `composite_policy`.

Never rename or renumber a shipped entry. When a new hardfork ships, give it the next ordinal. When
a new feature ships within an existing hardfork, add a new file under that hardfork's ordinal.

### Hardfork ordinals

| Ordinal | Hardfork | Status |
| --- | --- | --- |
| `01` | Beryl | Live |
| `02` | Cobalt | Upcoming |

Assign the next ordinal here before you name the first entry for a new hardfork.

## What an entry contains

Keep entries minimal and migration-focused. Don't restate unchanged behavior. A good entry has:

1. An audience statement and a one-paragraph summary that leads with the compatibility promise:
   what still works, what's deprecated but still dialable, and what's new. State plainly whether
   the fork is live yet.
2. A mapping table: old symbol, new symbol, status (`deprecated-dialable`, `renamed`, or `new`), and
   a one-line reason. Cover functions, events, and errors, with real signatures and selectors.
3. A "New at `<hardfork>` (adopt these)" section describing the new surface and its lifecycle.
4. A guarantees and edge cases section: a short Q&A covering what a careful integrator would ask,
   each answered with the precise on-chain behavior.

Before you cite a function signature, event signature or topic0, error selector, 4-byte function
selector, or ERC-165 interface ID, verify it against the source (`src/interfaces/**` and the
base/base ABIs). Don't rely on memory. You can check selectors with `cast sig` or `cast keccak`.

## Index

Entries are grouped by hardfork, one collapsible section per hardfork, newest first. Each
hardfork's table is sorted by `Product(s)`, then by change. A change that touches more than one
product because it lives on a shared interface gets one row, not one row per product: its
`Product(s)` and `Affected interfaces` columns list everything it touches. Never edit a shipped
hardfork's rows except to append a new one, and never renumber or reorder existing rows.

<details open>
<summary><strong>Cobalt (upcoming)</strong> — ordinal <code>02</code></summary>

| Product(s) | Change | Affected interfaces | Entry |
| --- | --- | --- | --- |
| B20 Asset | Schedule Multiplier Updates (ERC-8056) | `src/interfaces/IB20Asset.sol` | [02_Cobalt_B20Asset_multiplier](02_Cobalt_B20Asset_multiplier.md) |
| B20 Asset, B20 Stablecoin | Seize surface + `burnBlocked` deprecation | `src/interfaces/IB20.sol` (shared surface) → inherited by `src/interfaces/IB20Asset.sol`, `src/interfaces/IB20Stablecoin.sol` | [02_Cobalt_B20_seize](02_Cobalt_B20_seize.md) |
| PolicyRegistry | Composite Policies (UNION/INTERSECT) | `src/interfaces/IPolicyRegistry.sol` | [02_Cobalt_PolicyRegistry_composite_policy](02_Cobalt_PolicyRegistry_composite_policy.md) |

</details>

<!--
Adding the next hardfork: copy the <details> block above, set <summary> to the new codename and
ordinal, and fill in its own table. Don't touch prior <details> blocks — this file only grows by
appending new blocks above this comment and, within the current hardfork's block, by appending new
rows.
-->
