# Policies

*The B20 authorization model: policy scopes and their relationship to the PolicyRegistry.*

## Policy scopes

Each movement path consults its own scopes. The token stores a policy ID per scope and asks the Policy Registry `isAuthorized(policyId, account)`.

| Scope | Consulted on | Account |
| --- | --- | --- |
| `TRANSFER_SENDER_POLICY` | `transfer`, `transferFrom` | `from` |
| `TRANSFER_RECEIVER_POLICY` | `transfer`, `transferFrom` | `to` |
| `TRANSFER_EXECUTOR_POLICY` | `transferFrom` only | `msg.sender` |
| `MINT_RECEIVER_POLICY` | `mint` | `to` |
| `SEIZE_HOLDER_POLICY` | `seizeWithMemo` | `from` (seizable when unauthorized) |
| `SEIZE_RECEIVER_POLICY` | `seizeWithMemo` | `to` |

A denied check reverts with `PolicyForbids`. `approve` is not policy-gated.

## The PolicyRegistry

_TODO — see [`IPolicyRegistry`](../../src/interfaces/IPolicyRegistry.sol)._

## Defaults

_TODO — every scope defaults to `ALWAYS_ALLOW` at token creation unless overridden._

## Configuring policies

_TODO_
