# base-std

Standard library for Base-native protocols. Defines the Solidity interfaces
and reference implementations for protocol primitives that are (or are
proposed to be) enshrined as precompiles on Base.

## Scope

This repo holds:

- Solidity **interfaces** for Base precompiles, suitable for integrators to
  import when calling them from their own contracts.
- Solidity **reference implementations** of those precompiles, useful as
  guidance for Rust precompile work, for local testing and CI, and as a
  forcing function for thinking about behavior, gas, and storage shape
  before committing to a chain-level surface.

## Constraints

- **No third-party dependencies.** Reference implementations are written
  from scratch. We can read OpenZeppelin, Tempo, and other prior art for
  inspiration, but we do not import them. The point is for the interfaces
  and behavior to reflect our own opinions, not someone else's defaults.
- **EVM backward compatibility.** Base is an existing chain with an
  existing ecosystem. New token primitives must coexist with deployed
  ERC-20 tokens and the addresses that hold them. We do not reserve or
  reformat any address space that conflicts with existing usage.

## Layout

```
src/
├── interfaces/     # Solidity interfaces for precompiles
└── impls/          # Reference Solidity implementations
test/               # Foundry tests for the reference implementations
```

## Development

```bash
forge build
forge test
```

Solidity version: `0.8.30` for reference implementations. Interfaces are
written for broader compatibility (`>=0.8.20 <0.9.0`) so consumers can
import them without forcing a specific compiler.

## License

MIT
