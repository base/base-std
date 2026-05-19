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

Base Standard Library is a collection of Solidity interfaces, libraries, and mock implementations for Base precompiles.

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

## License

MIT
