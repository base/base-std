“B20 in 10 Minutes.” Very readable, probably 5–10 minutes.

It answers:

What is B20?
Why does it exist?
What problems does it solve?
Where does it sit in Base?
What is a B20 Asset?
What are policies?
What does a basic transaction look like?
Where should I go next?

Someone should be able to read just this and explain B20 at a high level.


# B20 Overview

B20 is Base's native token standard for issuing and managing programmable assets onchain.

This document provides a high-level introduction to B20: what it is, why it exists, the core primitives it exposes, and how those pieces fit together.

For a deeper technical explanation, see [How B20 Works](./architecture.md).

---

## What is B20?

B20 is Base's native token standard for issuing and managing programmable assets onchain. Base created it to standardize real-world asset (RWA) and stablecoin issuance. B20 is an ERC-20 superset: balances, transfers, and approvals work like ERC-20, and every B20 asset shares the same additional interfaces and protocol logic rather than each issuer deploying a custom token implementation.

The standard also includes compliance and administrative controls. Issuers can configure roles and permissions, attach policies, mint and burn supply, pause operations, and perform other administrative actions that regulated-asset workflows typically require.

B20 runs as precompiles in the Base node, not as per-token Solidity. Applications call ERC-20-style interfaces; the execution layer runs the shared B20 logic natively. Base upgrades that logic through hardforks, so issuers and holders get consistent behavior and native execution across all B20 assets.

### At a Glance

Optional small diagram:

Application
    |
    v
B20 Interfaces
    |
    v
B20 Precompiles
    |
    v
Base Execution Layer

One sentence explaining that applications interact with familiar contract-style interfaces while execution happens through native B20 functionality.

---

## Why B20?

Explain the problem B20 is trying to solve.

Potential themes:

- Tokenized assets repeatedly need the same primitives.
- Implementing these independently creates inconsistency and duplicated engineering effort.
- Assets may require richer controls than basic token transfers.
- Native primitives can provide standardized behavior and stronger ecosystem interoperability.

Avoid going deep into implementation rationale here.

The goal is to answer:

> Why would someone use B20 instead of building everything themselves?

---

## Core Mental Model

Introduce the main B20 concepts at the highest level.

### Assets

A B20 Asset represents an issued onchain asset.

Explain in a few sentences:

- balances
- supply
- asset configuration
- administrative capabilities

Do not describe every method.

### Roles

Roles determine who is authorized to perform privileged operations.

Examples might include:

- issuing
- administrative changes
- seizing
- managing policies

Link to deeper documentation.

### Policies

Policies define conditions that must be satisfied for certain operations.

Example mental model:

Transfer
   |
   v
Policy Evaluation
   |
   +--> Allowed
   |
   +--> Rejected

Explain that policies allow asset behavior to encode eligibility or transfer requirements without explaining every policy type yet.

### Native Functionality

Explain briefly that B20 functionality is implemented through Base precompiles and exposed through contract-compatible interfaces.

Do not explain dispatcher/version resolution yet.

Link to architecture.md.

---

## The Lifecycle of a B20 Asset

Give readers one simple end-to-end sequence.

Create Asset
    |
    v
Configure Roles / Policies
    |
    v
Issue Units
    |
    v
Transfer / Manage
    |
    v
Administrative Actions

Then describe each step in one sentence.

For example:

1. An issuer creates an asset.
2. The issuer configures who can administer it and what policies govern it.
3. Units are issued to holders.
4. Holders interact with the asset subject to its configured rules.
5. Authorized parties can perform administrative operations when required.

This section should establish the lifecycle without teaching the API.

---

## How a B20 Operation Works

Show one extremely simple transaction path.

Example:

User / Application
       |
       | transfer(...)
       v
   B20 Asset
       |
       v
Authorization / Policy Checks
       |
       v
State Transition
       |
       v
Events

Then explain:

- applications submit a B20 operation
- B20 evaluates the relevant authorization and policy rules
- if valid, canonical state changes
- events expose the resulting transition to downstream systems

This prepares readers for architecture.md.

---

## Example: Issuing and Transferring an Asset

Use one example throughout the documentation.

For example:

> ACME creates `ACME-TBILL`, a token representing units of a treasury product.

Walk through:

1. ACME creates the asset.
2. ACME configures the appropriate permissions.
3. ACME attaches a holder eligibility policy.
4. ACME issues 1,000 units to Alice.
5. Alice transfers 100 units to Bob.
6. B20 evaluates whether Bob satisfies the required policy.
7. If allowed, balances are updated and the relevant events are emitted.

The point isn't to show code.

The point is to connect all the concepts introduced above.

---

## B20 in the Base Stack

Show where B20 sits.

Application / Wallet / Backend
            |
            v
       B20 Interface
            |
            v
      B20 Precompiles
            |
            v
      Base Execution
            |
            v
      Canonical State

Explain the separation between:

- application-facing interface
- B20 protocol functionality
- underlying Base execution

This should be enough context for readers before they enter architecture.md.

---

## Who Builds Against B20?

Very briefly introduce your three audiences.

### Integrators

Applications, issuers, wallets, backends, or other systems that interact with B20 assets.

→ [Integrator Guide](./guides/integrators.md)

### Indexers

Systems that ingest B20 events and state to provide APIs, analytics, explorers, portfolio views, or other derived data.

→ [Indexer Guide](./guides/indexers.md)

### Implementers

Engineers working on B20 execution, client support, precompiles, testing, upgrades, or protocol behavior.

→ [Implementer Guide](./guides/implementers.md)

---

## Where to Go Next

If you want to understand how B20 works internally:

→ [B20 Architecture](./architecture.md)

If you are integrating B20:

→ [Integrator Guide](./guides/integrators.md)

If you are indexing B20:

→ [Indexer Guide](./guides/indexers.md)

If you are implementing B20:

→ [Implementer Guide](./guides/implementers.md)

For exact interfaces and protocol definitions:

→ [Reference](./reference/)
→ [Specifications](./specs/)