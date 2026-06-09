// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ForceFeeder
///
/// @notice Smoke-test helper that force-credits ether to an arbitrary address via SELFDESTRUCT — the
///         one ether transfer the receiver cannot observe or refuse. Used by the `precompile_invariants`
///         journey to push wei into a b20 precompile / token address that exposes no payable entrypoint,
///         reproducing the force-fed-ether conditions audited in `b20-precompile-selfdestruct-audit.md`.
///
/// @dev Test-only; never part of any production deployment. The contract is created and self-destructed
///      within the same transaction, so under EIP-6780 the account is both emptied and removed while its
///      balance is still forwarded to `target`. Deploy with a non-zero `value` equal to the wei to feed;
///      no code remains at the deployed address afterward.
contract ForceFeeder {
    /// @param target Recipient force-fed this contract's entire balance.
    constructor(address target) payable {
        assembly {
            // SELFDESTRUCT: forward the full balance to `target`, unconditionally and uninterceptably.
            selfdestruct(target)
        }
    }
}
