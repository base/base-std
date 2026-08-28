# B20 Execution Architecture

*How B20 actually executes: how its precompiles differ from ordinary contracts, how calls get routed to them, and how the protocol evolves without breaking history. For what each primitive means and how to use it (assets, roles, policies), see [Concepts](concepts/). For the "B20 in 10 minutes" tour, see [Overview](overview.md).*

## 1. How B20 Uses Precompiles

### 1.1 Normal Contracts vs Precompiles
- On every `CALL`/`STATICCALL` (etc.), the EVM checks a precompile registry *before* it ever loads bytecode at the target address.
- If the address matches an entry in that registry, native code runs directly — bytecode is never loaded or interpreted.
- Only a registry miss falls through to normal contract execution (load bytecode → interpret). An address with no bytecode and no registry entry behaves like an empty account: the call stops immediately with no output — this is what a precompile address looks like *before* the hardfork that introduces it.
- Classic Ethereum precompiles (`ecrecover`, `sha256`, `ripemd160`, `modexp`, `ecadd`/`ecmul`/`ecpairing`, `blake2f`, etc.) are looked up through this exact same registry. B20 doesn't bypass or extend the EVM's dispatch path — it plugs into it.

### 1.2 B20's Native Contract Model
- B20 tokens, the Factory, the Policy Registry, and the Activation Registry are all precompiles: native logic hosted by the execution client at a fixed or derived address, not deployed EVM bytecode.
- Unlike classic precompiles — pure, stateless functions — B20's precompiles are stateful: they hold persistent storage (balances, roles, policy IDs, pause state, ...) and emit real events. They behave as system contracts, not one-shot pure functions.
- Because they're stateful, they aren't cacheable the way a pure function's result would be — every call re-reads live storage.
- From the outside, calling a B20 precompile looks identical to calling a normal ERC-20 contract: same ABI encoding, same `CALL` semantics. The precompile nature is invisible above the EVM.

### 1.3 B20 Address Space
- Fixed-address precompiles (Factory, Policy Registry, Activation Registry) sit at known, hardcoded addresses (`StdPrecompiles`).
- B20 token addresses are different — derived, not fixed, and self-describing: `0xB2` prefix + variant byte + `keccak256(sender, salt)` suffix, computed at creation time.
- The address alone answers "is this a B20 token" and "which variant" (`isB20`, `getB20Address`) — no external registry lookup needed to recognize one.

### 1.4 How Calls Are Routed
- Fixed-address precompiles are matched directly in a static registry table.
- B20 token addresses can't be pre-registered individually — they're created at runtime, so there's no fixed list to check against. They're resolved through a dynamic fallback lookup that decodes the variant straight out of the address itself and builds the right dispatcher (Asset vs Stablecoin) on the fly.
- This is exactly why the address encoding in §1.3 exists — it's what makes dynamic routing possible without a token registry.

### 1.5 Where State Lives
- State backing a B20 precompile lives in the execution client's own state — the same storage substrate as contract storage — not inside "fake bytecode." Reads and writes are metered with the same gas costs as native `SLOAD`/`SSTORE`.
- Each precompile (Factory, Policy Registry, each token) owns its own storage. There's no shared global state between tokens beyond what's explicitly referenced — e.g. a policy ID pointing at a shared entry in the Policy Registry.

### 1.6 How a B20 Call Executes
- Once a call is routed to a precompile: reject an unexpected value transfer (nonpayable) → charge calldata gas → resolve the active logic version for the current hardfork → decode the call against that version's frozen ABI → run the operation's checks (role, pause, policy) → mutate state → emit events.
- Gas isn't a single flat fee: a calldata cost plus metered storage/log costs, charged on the same schedule as native opcodes (warm/cold access, refunds included). A precompile that reports using more gas than the call's limit halts the call — the same outcome as running out of gas mid-execution.
- Activation gating happens inside this step, not by hiding the address: once a hardfork introduces a precompile, the address always exists from then on. An inactive feature makes specific write operations revert rather than removing the address from the registry — and deactivating a feature blocks *new* creation, it doesn't retroactively disable assets that already exist.

## 2. How B20 Evolves

### 2.1 Protocol Upgrades
- B20 changes ship as part of hardforks (e.g. Beryl → Cobalt) — the same mechanism that gates any other protocol-level change.
- A hardfork can introduce an entirely new precompile (the Activation Registry itself only exists from Beryl onward) or a new logic version for an existing one.

### 2.2 Logic Versions
- Each precompile's logic is versioned. Once a version ships, it's frozen forever — self-contained, with no shared mutable state or traits across versions.
- Why: editing logic in place at a fixed address would change execution for historical blocks too, breaking replay from genesis. Freezing is what preserves consensus.

### 2.3 Fork / Version Resolution
- A hardfork resolves to a specific logic version (fork → version enum → frozen implementation) — resolved once per call, never "whatever is current."
- A call reverts if no version is resolved for the active fork (calling logic that doesn't exist yet), rather than silently falling back to a default.

### 2.4 Adding New Functions
- New functionality ships as a new frozen version alongside the old ones — never by editing an existing version in place.
- Additive-only guarantee: a hardfork can add selectors, events, and errors; it never removes or changes ones that already shipped.

### 2.5 ABI Evolution
- The logic interface itself is append-only: new versions may add methods, never remove or change existing signatures.
- Deprecated symbols are kept, not deleted (e.g. `burnBlocked`, the instant `updateMultiplier`) — old callers keep working unchanged.

### 2.6 Historical Execution
- Old transactions replay deterministically: the dispatcher resolves the version that was active *at that block's fork*, not "current" logic — so replaying history always re-executes the version that was live at the time.

### 2.7 Backwards Compatibility
- Nothing that already shipped changes meaning — existing selectors, events, and errors keep their exact semantics across every later fork.
- Consumers integrated against an old version keep working after a new version ships alongside it. They simply don't get new capabilities until they adopt the new ABI surface.
