# How B20 Works

*The canonical explanation of the B20 system. Every serious B20 consumer — integrator, indexer, or implementer — should read this document. Audience guides link back here instead of re-explaining these mechanics.*

## Execution model

```text
Application
    ↓
B20 ABI
    ↓
Precompile dispatcher
    ↓
Version resolution
    ↓
Asset logic
    ↓
Policies / authorization
    ↓
State mutation
    ↓
Events
```

_TODO — narrative walkthrough of the pipeline above._

## Lifecycle of an asset

_TODO — creation via the factory through to end-of-life states._

## State model

_TODO_

## Policy model

_TODO — see [Policies](concepts/policies.md) for the full model._

## Permissions / roles

_TODO — see [Roles](concepts/roles.md) for the full model._

## Events

_TODO — see [Events reference](reference/events.md) for the exhaustive list._

## Upgrades / versioning

_TODO — see [Versioning](concepts/versioning.md) for the full model._

## Invariants

_TODO_

## Full transaction walkthrough

_TODO — trace one transaction end-to-end through every layer above._
