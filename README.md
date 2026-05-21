<br>
<br>
<p align="center">
  <a href="https://base.org" target="_blank" rel="noopener noreferrer">
    <img width="400" alt="Base_lockup_white" src="https://github.com/user-attachments/assets/5f399085-b0ad-46e5-8f2b-93de337342d4" />
  </a>
</p>
<br>
<br>

# Base Standard Library

A collection of Solidity interfaces, libraries, and mock implementations for Base precompiles.

## Installation

```bash
forge install base/base-std
```

## Standard Precompiles

<pre>
src
├── <a href="./src/StdPrecompiles.sol">StdPrecompiles.sol</a>: Collection of precompiles and their interfaces
└── interfaces
    ├── <a href="./src/interfaces/IB20.sol">IB20.sol</a>: Core Token Standard
    ├── <a href="./src/interfaces/IB20Stablecoin.sol">IB20Stablecoin.sol</a>: Stablecoin variant of B20
    ├── <a href="./src/interfaces/IB20Security.sol">IB20Security.sol</a>: Security variant of B20
    ├── <a href="./src/interfaces/IPolicyRegistry.sol">IPolicyRegistry.sol</a>: Policy registry shared across B20s
    └── <a href="./src/interfaces/ITokenFactory.sol">ITokenFactory.sol</a>: B20 factory contract
</pre>

## Development

```bash
forge build
forge test
```

Solidity version: `0.8.30` for reference implementations. Interfaces are
written for broader compatibility (`>=0.8.20 <0.9.0`) so consumers can
import them without forcing a specific compiler.

## Fork testing against live precompiles

The unit suite can run against a chain hosting the live Rust precompile
implementations to verify the Rust impls match the Solidity reference's
behavior and storage layout. The same test bodies are reused — only the
backend changes.

```bash
LIVE_PRECOMPILES=true FOUNDRY_PROFILE=fork forge test --fork-url vibenet
```

What each flag does:

- `--fork-url vibenet` — selects the RPC endpoint defined in
  `foundry.toml` under `[rpc_endpoints]` (currently `https://rpc.vibes.base.org/`).
  Foundry forks the chain in a sandboxed copy-on-write state; tests
  mutate the fork without touching the real chain.
- `LIVE_PRECOMPILES=true` — tells `BaseTest.setUp` to skip the
  mock-etching step. Without it, `vm.etch` would clobber the live
  precompile addresses with the mock bytecode, silently routing every
  call back through the Solidity reference and producing false-pass
  results.
- `FOUNDRY_PROFILE=fork` — switches to a reduced-fuzz-runs profile
  (10 instead of 256). Each fuzz iteration may trigger RPC round-trips
  against the live precompiles; the goal at this stage is "does the
  layout / behavior match" rather than fuzz coverage. Drop this flag
  to use the default fuzz runs.

A test failure under this command means one of three things, in
diagnostic order: (1) the feature isn't activated yet in the
ActivationRegistry, (2) the precompile isn't deployed at its canonical
address on the forked chain, or (3) the Rust impl's storage layout /
behavior diverges from the Solidity reference at the asserted slot.

## License

MIT
