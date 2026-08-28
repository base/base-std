# Roles

*The B20 role-based access control model.*

## Role taxonomy

B20 follows [OpenZeppelin AccessControl](https://docs.openzeppelin.com/contracts/5.x/access-control) with a fixed set of built-in roles. The admin uses `grantRole`, `revokeRole`, `renounceRole`, and `setRoleAdmin`. See [`B20Constants`](../../src/lib/B20Constants.sol) for the identifier values.

| Role | Gates |
| --- | --- |
| `DEFAULT_ADMIN_ROLE` | `grantRole`, `revokeRole`, `setRoleAdmin`, `updatePolicy`, `updateSupplyCap` |
| `MINT_ROLE` | `mint`, `mintWithMemo` |
| `BURN_ROLE` | `burn`, `burnWithMemo` |
| `BURN_BLOCKED_ROLE` | `burnBlocked` (deprecated) |
| `SEIZE_ROLE` | `seizeWithMemo` |
| `PAUSE_ROLE` | `pause` |
| `UNPAUSE_ROLE` | `unpause` |
| `METADATA_ROLE` | `updateName`, `updateSymbol`, `updateContractURI` |
| `OPERATOR_ROLE` | Asset-only: `announce`, multiplier updates |

Pause is per feature, not global. `PAUSE_ROLE` can pause any of `TRANSFER`, `MINT`, `BURN`, and `SEIZE`. `UNPAUSE_ROLE` is a separate role. `approve` is not pause-gated. Holder `transfer` is not role-gated.

## Custom roles

_TODO — `setRoleAdmin` / `grantRole` for user-defined roles._

## Admin lifecycle

_TODO — `renounceLastAdmin` and the admin-less end state._
