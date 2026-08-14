# Agent instructions — changelog/

Read [README.md](README.md) first for the index of what's already documented. This file covers how
to name, write, and index a new entry.

## Naming a new entry

```
changelog/
  <ordinal>_<Hardfork>_<Product>_<feature>.md    # one scoped feature change
```

Each file name has four parts:

- `<ordinal>`: a 2-digit, zero-padded hardfork activation sequence number, assigned once per
  hardfork, never per file. Check README's [Hardfork ordinals](README.md#hardfork-ordinals) table
  and reuse the ordinal if the hardfork already has one. Assign the next unused number only for a
  hardfork with no prior entry, and add a row for it in that table. Because filenames sort lexically,
  this keeps the directory listing in activation order.
- `<Hardfork>`: the PascalCase codename, for example `Cobalt`.
- `<Product>`: a PascalCase token matching the same product's directory under
  [`docs/`](../docs) and [`test/unit/`](../test/unit), for example `B20Asset` or `PolicyRegistry`.
  For a change that spans both B20 variants, use the shared-surface token `B20`.
- `<feature>`: a short, lowercase snake_case slug that maps to a release-notes line item, for
  example `multiplier`, `seize`, or `composite_policy`. Don't repeat the product or hardfork in the
  slug — those are already separate filename components.

Never rename or renumber a shipped entry. Once a hardfork activates on-chain, its entries are
frozen; only add new files for new hardforks or features.

## Writing an entry

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
base/base ABIs). Don't rely on memory, and don't trust a prior entry's numbers even for a symbol
you believe is unchanged. Check selectors with `cast sig` or `cast keccak`.

If you can't verify a value, flag it in the entry or ask, rather than shipping a plausible-looking
but unverified selector.

## Indexing a new entry

Add a row to the current hardfork's table in README's [Index](README.md#index). Sort each
hardfork's table by `Product(s)`, then by change. A change that touches more than one product
because it lives on a shared interface gets one row, not one row per product: list everything it
touches in the `Product(s)` and `Affected interfaces` columns.

Never edit a shipped hardfork's rows except to append a new one, and never renumber or reorder
existing rows. To add the first entry for a new hardfork, copy the most recent `<details>` block,
set its `<summary>` to the new codename and ordinal, and add it above the existing blocks — don't
touch prior blocks.
