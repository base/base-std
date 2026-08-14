# Changelog

This directory holds per-hardfork, per-feature migration notes for the Base precompile standard.
Each entry is a focused, code-forward changelog for one scoped feature change that crosses a
hardfork boundary: the API, function, event, and error deltas behind a single line item in a
hardfork's release notes (for example, Cobalt's "Schedule Multiplier Updates").

This complements the product references in [`docs/`](../docs). `docs/` describes how a product
works today. `changelog/` describes what changes at a hardfork and how to migrate across it.

See [AGENTS.md](AGENTS.md) for how to name and write a new entry.

## Hardfork ordinals

| Ordinal | Hardfork | Status |
| --- | --- | --- |
| `01` | Beryl | Live |
| `02` | Cobalt | Upcoming |

## Index

Grouped by hardfork, one collapsible section per hardfork, newest first.

<details open>
<summary><strong>Cobalt (upcoming)</strong> — ordinal <code>02</code></summary>

| Product(s) | Change | Affected interfaces | Entry |
| --- | --- | --- | --- |
| B20 Asset | Schedule Multiplier Updates (ERC-8056) | `src/interfaces/IB20Asset.sol` | [02_Cobalt_B20Asset_multiplier](02_Cobalt_B20Asset_multiplier.md) |
| B20 Asset, B20 Stablecoin | Seize surface + `burnBlocked` deprecation | `src/interfaces/IB20.sol` (shared surface) → inherited by `src/interfaces/IB20Asset.sol`, `src/interfaces/IB20Stablecoin.sol` | [02_Cobalt_B20_seize](02_Cobalt_B20_seize.md) |
| PolicyRegistry | Composite Policies (UNION/INTERSECT) | `src/interfaces/IPolicyRegistry.sol` | [02_Cobalt_PolicyRegistry_composite_policy](02_Cobalt_PolicyRegistry_composite_policy.md) |

</details>
