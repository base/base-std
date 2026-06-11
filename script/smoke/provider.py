"""Read-your-writes HTTP provider for a load-balanced node pool.

A live RPC endpoint is usually a load balancer in front of many nodes at slightly different
heights. The journeys are serial — write, then immediately read the result — so a write confirmed
on one backend can have its follow-up read routed to a backend that has not imported that block yet,
observing pre-write state (the canonical `isB20Initialized == false` right after a successful
`createB20`). `ConsistentHTTPProvider` presents the whole run a single, monotonic, read-your-writes
view over the pool so the journeys never see that staleness. See the class docstring for the
mechanism. Against a single node it is a no-op (the high-water block is always present).
"""

from __future__ import annotations

import time

import requests
from web3 import HTTPProvider

# Methods whose block-tag parameter we pin to the consistency high-water mark, mapped to the
# positional index of that block tag in the JSON-RPC params array. These are *state* reads, where the
# guarantee we want is "never observe state older than a write we've confirmed".
#
# `eth_getTransactionCount` is deliberately NOT here: the nonce must reflect the account's *latest*
# head, not a historical snapshot. Pinning it backwards returns a stale-low nonce (the count as of an
# older block), which the broadcast backend then rejects as "nonce too low". The sticky connection
# keeps the nonce read and the broadcast on one backend, and `Chain` tracks a local monotonic nonce
# on top, so the nonce stays correct without pinning.
_PINNED_BLOCK_PARAM_INDEX = {
    "eth_call": 1,
    "eth_estimateGas": 1,
    "eth_getBalance": 1,
    "eth_getCode": 1,
    "eth_getStorageAt": 2,
}

# Block tags meaning "newest state", safe to re-point at the high-water mark. `safe`/`finalized`
# deliberately ask for older agreed state, so we leave those (and explicit numbers/hashes) alone.
_PINNABLE_TAGS = (None, "latest", "pending")

# JSON-RPC error a backend returns when it has not yet imported the block we pinned to (it lags the
# node that produced the high-water mark). Geth/reth answer with code -32001 / a "not found" message
# rather than silently serving stale state, which is exactly what lets us detect-and-retry.
_STALE_BLOCK_CODE = -32001
_STALE_BLOCK_MARKERS = (
    "block not found",
    "header not found",
    "missing trie node",
    "missing header",
    "unknown block",
    "header for hash not found",
    "state not available",
    "no state available",
    "missing state",
)

# Read-pin retry budget: how long to wait for a lagging backend to import the pinned block (block
# time on the target chains is ~2s, observed head spread ~1-2 blocks, so a few seconds is plenty).
_SYNC_TIMEOUT_SECONDS = 30.0


def _make_sticky_session() -> requests.Session:
    """A single-connection keep-alive session, so the whole run pins to one backend in the pool.

    The pool fronting a live endpoint is sticky *per connection* but routes *new* connections to
    arbitrary backends. Holding one connection open for the run keeps every request on the same
    backend — trivially consistent with its own writes — so the high-water safety net below only has
    to engage on the rare occasion the connection drops and the pool re-pins us to a lagging backend.
    """
    session = requests.Session()
    adapter = requests.adapters.HTTPAdapter(pool_connections=1, pool_maxsize=1, max_retries=0)
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    session.headers["Connection"] = "keep-alive"
    return session


def _as_block_int(value: object) -> int | None:
    """Coerce a JSON-RPC block number (hex string, int, or decimal string) to int; None if unparseable."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value, 16) if value.lower().startswith("0x") else int(value)
        except ValueError:
            return None
    return None


class ConsistentHTTPProvider(HTTPProvider):
    """HTTP provider giving the suite one read-your-writes view over a load-balanced node pool.

    A live RPC endpoint usually fronts many nodes at slightly different heights (we measured ~1-2
    blocks of spread). A write confirmed on one backend is not instantly visible on another, so a
    follow-up read routed to a lagging backend sees pre-write state — the canonical
    `isB20Initialized == false` immediately after a successful `createB20` flake.

    Two mechanisms, layered:

      1. Stickiness (the steady state): a single keep-alive connection (`_make_sticky_session`) pins
         the whole run to one backend, which is consistent with its own writes — no waiting, no retries.
      2. A high-water safety net (when the connection drops and the pool re-pins us to a lagging
         backend): we ratchet the highest block any confirmed receipt / head query revealed, pin every
         state read to that block, and — because a backend that has not imported it answers
         `block not found` instead of silently serving stale state — drop the connection to force a
         re-route and retry until a synced backend answers (or we exceed the sync timeout). The nonce
         lookup is *not* pinned (see `_PINNED_BLOCK_PARAM_INDEX`); `Chain` tracks it monotonically.

    The net effect: reads never observe a state older than a write the suite has already confirmed,
    regardless of which backend the pool happens to route any individual request to.
    """

    def __init__(self, endpoint_uri: str, *, sync_timeout: float = _SYNC_TIMEOUT_SECONDS) -> None:
        self._sticky_session = _make_sticky_session()
        super().__init__(endpoint_uri, session=self._sticky_session)
        self._read_block: int | None = None
        self._sync_timeout = sync_timeout

    @property
    def read_block(self) -> int | None:
        """The current consistency high-water mark (highest block observed), or None before any."""
        return self._read_block

    def _ratchet(self, block: int | None) -> None:
        if block is not None and (self._read_block is None or block > self._read_block):
            self._read_block = block

    def _observe(self, method: str, response: dict) -> None:
        """Ratchet the high-water mark from anything a response reveals about chain progress."""
        result = response.get("result")
        if result is None:
            return
        if method == "eth_blockNumber":
            self._ratchet(_as_block_int(result))
        elif method == "eth_getTransactionReceipt" and isinstance(result, dict):
            self._ratchet(_as_block_int(result.get("blockNumber")))
        elif method in ("eth_getBlockByNumber", "eth_getBlockByHash") and isinstance(result, dict):
            self._ratchet(_as_block_int(result.get("number")))

    def _pin(self, method: str, params: object) -> tuple[object, bool]:
        """Re-point a `latest`/`pending`/absent block tag at the high-water mark. Returns (params, pinned)."""
        idx = _PINNED_BLOCK_PARAM_INDEX.get(method)
        if idx is None or self._read_block is None:
            return params, False
        pinned = list(params) if isinstance(params, (list, tuple)) else [params]
        tag = hex(self._read_block)
        if len(pinned) <= idx:
            pinned.extend([None] * (idx - len(pinned)))
            pinned.append(tag)
            return pinned, True
        if pinned[idx] in _PINNABLE_TAGS:
            pinned[idx] = tag
            return pinned, True
        return params, False  # explicit block number / hash / safe / finalized — leave it

    @staticmethod
    def _is_stale_block_error(error: object) -> bool:
        if not error:
            return False
        if isinstance(error, dict):
            if error.get("code") == _STALE_BLOCK_CODE:
                return True
            message = str(error.get("message", ""))
        else:
            message = str(error)
        message = message.lower()
        return any(marker in message for marker in _STALE_BLOCK_MARKERS)

    def make_request(self, method, params):
        pinned_params, pinned = self._pin(method, params)
        if not pinned:
            response = super().make_request(method, params)
            self._observe(method, response)
            return response
        deadline = time.monotonic() + self._sync_timeout
        delay = 0.1
        while True:
            response = super().make_request(method, pinned_params)
            if not self._is_stale_block_error(response.get("error")):
                self._observe(method, response)
                return response
            if time.monotonic() >= deadline:
                return response  # surface the node's error rather than hang forever
            # The sticky connection is parked on a backend that lags the pinned block. Drop it so the
            # pool re-routes us, and give backends a moment to import the block, then retry.
            self._sticky_session.close()
            time.sleep(min(delay, 1.0))
            delay *= 1.5
