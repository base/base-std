"""ABI encoding for the one place the contract API is opaque bytes.

`createB20` takes `bytes params` (an abi-encoded B20*CreateParams struct) and a
`bytes[]` of bootstrap calls. The structs never appear in any external
signature, so no ABI can describe them — this is the single encode that stays
hand-written. We localize it here behind typed dataclasses and eth_abi, and
build the bootstrap calldata from the token ABI so the init-calls reference real
function names rather than stringly selectors.
"""

from __future__ import annotations

from dataclasses import dataclass

from eth_abi import encode as abi_encode
from eth_typing import ChecksumAddress
from hexbytes import HexBytes
from web3 import Web3

# Current B20*CreateParams encoding version (leading struct field).
PARAMS_VERSION = 1

_ASSET_PARAMS_TYPE = "(uint8,string,string,address,uint8)"
_STABLECOIN_PARAMS_TYPE = "(uint8,string,string,address,string)"


@dataclass(frozen=True)
class AssetCreateParams:
    """IB20Factory.B20AssetCreateParams."""

    name: str
    symbol: str
    initial_admin: ChecksumAddress
    decimals: int

    def encode(self) -> bytes:
        return abi_encode(
            [_ASSET_PARAMS_TYPE],
            [(PARAMS_VERSION, self.name, self.symbol, self.initial_admin, self.decimals)],
        )


@dataclass(frozen=True)
class StablecoinCreateParams:
    """IB20Factory.B20StablecoinCreateParams."""

    name: str
    symbol: str
    initial_admin: ChecksumAddress
    currency: str

    def encode(self) -> bytes:
        return abi_encode(
            [_STABLECOIN_PARAMS_TYPE],
            [(PARAMS_VERSION, self.name, self.symbol, self.initial_admin, self.currency)],
        )


def init_call(token_contract, fn_name: str, *args) -> bytes:
    """Encode a single bootstrap call (selector + args) for createB20's initCalls.

    `token_contract` is any IB20Asset/IB20Stablecoin web3 contract — used only for
    its ABI, so it need not be bound to a deployed address.
    """
    return bytes(HexBytes(token_contract.encode_abi(fn_name, args=list(args))))


def topic0(signature: str) -> HexBytes:
    """topic[0] (event signature hash) for a canonical event signature string."""
    return HexBytes(Web3.keccak(text=signature))
