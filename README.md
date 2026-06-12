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

## Products

- [**ActivationRegistry**](docs/ActivationRegistry/README.md) — Feature flags controlled by Base team to activate/deactivate features.
- [**PolicyRegistry**](docs/PolicyRegistry/README.md) — Membership sets controlled by custom admins, initially providing allow and block lists for B20 token operations.
- [**B20**](docs/B20/README.md) — Standard ERC-20 implementation with extensions for roles, policies, memos, pausing, ERC-2612 permits, and a variant system.

## Source Integration

These source files are imported by production contracts to interact with Base precompiles.

```bash
forge install base/base-std
```

<pre>
src
├── <a href="./src/StdPrecompiles.sol">StdPrecompiles.sol</a>: Precompile addresses with interface wrapper handles
├── interfaces
│   ├── <a href="./src/interfaces/IB20.sol">IB20.sol</a>: Core token standard
│   ├── <a href="./src/interfaces/IB20Asset.sol">IB20Asset.sol</a>: Asset variant of B20
│   ├── <a href="./src/interfaces/IB20Stablecoin.sol">IB20Stablecoin.sol</a>: Stablecoin variant of B20
│   ├── <a href="./src/interfaces/IB20Factory.sol">IB20Factory.sol</a>: B20 factory precompile
│   ├── <a href="./src/interfaces/IPolicyRegistry.sol">IPolicyRegistry.sol</a>: Policy registry precompile
│   └── <a href="./src/interfaces/IActivationRegistry.sol">IActivationRegistry.sol</a>: Activation registry precompile
└── lib
    ├── <a href="./src/lib/B20Constants.sol">B20Constants.sol</a>: B20 role and policy-type identifier constants
    └── <a href="./src/lib/B20FactoryLib.sol">B20FactoryLib.sol</a>: Pure encoders for B20 factory params and initCalls
</pre>

## Test Integration

These mock contracts replace the live precompiles in unit tests, allowing tests to run without a fork.

<pre>
test/lib/mocks
├── <a href="./test/lib/mocks/MockActivationRegistry.sol">MockActivationRegistry.sol</a>: Mock implementation of the activation registry precompile
├── <a href="./test/lib/mocks/MockPolicyRegistry.sol">MockPolicyRegistry.sol</a>: Mock implementation of the policy registry precompile
└── <a href="./test/lib/mocks/MockB20Factory.sol">MockB20Factory.sol</a>: Mock implementation of the B20 factory precompile
</pre>

## Contributing

### Development

```bash
forge build
forge test
```

Solidity version: `0.8.30` for reference implementations. Interfaces are
written for broader compatibility (`>=0.8.20 <0.9.0`) so consumers can
import them without forcing a specific compiler.

### Live precompile testing

The same unit suite runs against the live Rust precompiles to verify they
match the Solidity reference's behavior and storage layout — only the backend
changes. The simplest way is `base-forge` (from
[base-anvil](https://github.com/base/base-anvil)), which hosts the precompiles
in-process; `BaseTest` auto-detects them, so no flags are needed:

```bash
base-forge test
```

Stock `forge test` runs the same suite against the Solidity mocks instead
(reference mode); `setUp` logs which mode ran. See
[LIVE_PRECOMPILE_TESTING.md](./LIVE_PRECOMPILE_TESTING.md) for the full
workflow, including running against a real base-anvil node.

To run against a forked chain that already hosts the precompiles:

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
