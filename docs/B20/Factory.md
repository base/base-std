# B20 Factory

The B20 Factory is the singleton precompile that creates B20 tokens of every variant. Anyone can call its single entry point, `createB20`. See [`IB20Factory`](../../src/interfaces/IB20Factory.sol) for the full Solidity interface.

## `createB20` parameters

`createB20` takes four arguments:

### `variant`

Selects which variant of B20 to deploy — currently `ASSET` or `STABLECOIN`. See the [variant overview](README.md#variant-overview) for what each one bundles.

### `params`

Variant-specific creation arguments, ABI-encoded as a versioned struct (one struct per variant; the leading byte selects the encoding version). Required and optional fields differ per variant — see [`IB20Factory`](../../src/interfaces/IB20Factory.sol) for each variant's struct spec.

### `initCalls`

An optional array of ABI-encoded calls dispatched on the new token immediately after creation. These let you configure anything beyond the variant's defined `params` — role grants, mint operations, policy scopes, contract URI, and so on. They execute on the new token as if the factory were the admin, so admin-gated operations are permitted within this window. The factory itself receives no official roles and has no persisted access to the token.

Build the array with [`B20FactoryLib`](../../src/lib/B20FactoryLib.sol) helpers (or encode manually):

```solidity
// Configure the new token: cap supply and gate minting on an allowlist.
bytes[] memory initCalls = new bytes[](2);
initCalls[0] = B20FactoryLib.encodeUpdateSupplyCap(1_000_000e18);
initCalls[1] = B20FactoryLib.encodeUpdatePolicy(B20Constants.MINT_RECEIVER_POLICY, mintPolicyId);
```

### `salt`

Caller-chosen entropy that influences the deployed token's address — see [B20 Address Derivation](#b20-address-derivation).

## B20 Address Derivation

B20 addresses are deterministic: `[B20 prefix (10 bytes)][variant byte (1 byte)][bytes9(keccak256(deployer, salt))]`. The variant byte being recoverable from the address means off-chain tooling can identify the variant without an RPC call.

`getB20Address(variant, deployer, salt)` predicts the address before deployment. `isB20(address)` matches against the prefix pattern (recovered from the address with no storage read), and `isB20Initialized(address)` flips true exactly once when `createB20` completes at that address.

## Composing with the factory

The factory is callable from any account, including from your own contract. Wrapping the factory is the standard path for layering access control on top of permissionless creation, bundling defaults into a higher-level builder, or defining a custom salting scheme.
