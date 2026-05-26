// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "../interfaces/IB20.sol";
import {IB20Factory} from "../interfaces/IB20Factory.sol";
import {IB20Security} from "../interfaces/IB20Security.sol";

/// @title  B20FactoryLib
/// @author Coinbase
/// @notice Helpers for constructing the calldata an integrator passes to
///         `StdPrecompiles.B20_FACTORY.createB20(...)`. Two layers:
///
///         1. Per-variant `encode*CreateParams` helpers that produce the
///            `params` blob (a leading version byte plus the
///            variant-specific struct fields, ABI-encoded). The factory
///            decodes this with `abi.decode(params, (<Variant>CreateParams))`,
///            so the library and the factory use the same struct layouts
///            from `IB20Factory`.
///
///         2. `encode*` helpers that produce a single bootstrap
///            `initCall` (an ABI-encoded function call against `IB20` or
///            `IB20Security`), plus `build*` helpers that assemble
///            common multi-entry init-call arrays (role grants,
///            security-identifier updates) from parallel arrays. The
///            `bytes[] initCalls` argument to `createB20` is the
///            concatenation of however many of these the integrator
///            needs.
///
/// @dev    Pure encoder library: no precompile dispatch, no storage
///         reads, no role/policy checks. Authorization happens inside
///         the factory's bootstrap window (see `IB20Factory`) when the
///         resulting calldata is actually invoked. The library deals in
///         `bytes` and `bytes[]` only.
///
///         Init-call shape: each entry in `initCalls` is the ABI-encoded
///         function call (selector + args) that the factory will invoke
///         on the freshly-deployed token during the privileged bootstrap
///         window. Every `encode*` helper here produces exactly one such
///         entry; integrators concatenate them in whatever order they
///         need.
library B20FactoryLib {
    /// @notice Current encoding version for every variant's
    ///         `*CreateParams` struct. Carried as the leading `version`
    ///         field so the factory can route between encodings as the
    ///         schema evolves; today only `1` exists.
    uint8 internal constant CREATE_PARAMS_VERSION = 1;

    /// @notice Two parallel arrays passed to a `build*` helper had
    ///         different lengths.
    /// @param  leftLen  Length of the first array argument.
    /// @param  rightLen Length of the second array argument.
    error LengthMismatch(uint256 leftLen, uint256 rightLen);

    /*//////////////////////////////////////////////////////////////
                          CREATE-PARAMS ENCODERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Encodes a `B20CreateParams` (default variant) as the
    ///         `params` blob expected by `IB20Factory.createB20` when
    ///         `variant == B20Variant.DEFAULT`. The leading byte is
    ///         `CREATE_PARAMS_VERSION`.
    ///
    /// @param  name         ERC-20 token name.
    /// @param  symbol       ERC-20 token symbol.
    /// @param  initialAdmin Initial holder of `DEFAULT_ADMIN_ROLE`, or
    ///                      `address(0)` for the demonstrate-no-owner
    ///                      path.
    ///
    /// @return The ABI-encoded `B20CreateParams` blob.
    function encodeDefaultCreateParams(string memory name, string memory symbol, address initialAdmin)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            IB20Factory.B20CreateParams({
                version: CREATE_PARAMS_VERSION,
                name: name,
                symbol: symbol,
                initialAdmin: initialAdmin
            })
        );
    }

    /// @notice Encodes a `B20StablecoinCreateParams` as the `params`
    ///         blob expected by `IB20Factory.createB20` when
    ///         `variant == B20Variant.STABLECOIN`. The leading byte is
    ///         `CREATE_PARAMS_VERSION`.
    ///
    /// @param  name         ERC-20 token name.
    /// @param  symbol       ERC-20 token symbol.
    /// @param  initialAdmin Initial holder of `DEFAULT_ADMIN_ROLE`, or
    ///                      `address(0)`.
    /// @param  currency     ISO 4217 fiat code this stablecoin tracks.
    ///                      Validated against `ISO4217.sol` by the
    ///                      factory.
    ///
    /// @return The ABI-encoded `B20StablecoinCreateParams` blob.
    function encodeStablecoinCreateParams(
        string memory name,
        string memory symbol,
        address initialAdmin,
        string memory currency
    ) internal pure returns (bytes memory) {
        return abi.encode(
            IB20Factory.B20StablecoinCreateParams({
                version: CREATE_PARAMS_VERSION,
                name: name,
                symbol: symbol,
                initialAdmin: initialAdmin,
                currency: currency
            })
        );
    }

    /// @notice Encodes a `B20SecurityCreateParams` as the `params` blob
    ///         expected by `IB20Factory.createB20` when
    ///         `variant == B20Variant.SECURITY`. The leading byte is
    ///         `CREATE_PARAMS_VERSION`.
    ///
    /// @param  name              ERC-20 token name.
    /// @param  symbol            ERC-20 token symbol.
    /// @param  initialAdmin      Initial holder of `DEFAULT_ADMIN_ROLE`,
    ///                           or `address(0)`.
    /// @param  isin              International Securities Identification
    ///                           Number; required. Empty string is
    ///                           rejected by the factory with
    ///                           `MissingRequiredField`.
    /// @param  minimumRedeemable Initial `minimumRedeemable` (shares).
    ///
    /// @return The ABI-encoded `B20SecurityCreateParams` blob.
    function encodeSecurityCreateParams(
        string memory name,
        string memory symbol,
        address initialAdmin,
        string memory isin,
        uint256 minimumRedeemable
    ) internal pure returns (bytes memory) {
        return abi.encode(
            IB20Factory.B20SecurityCreateParams({
                version: CREATE_PARAMS_VERSION,
                name: name,
                symbol: symbol,
                initialAdmin: initialAdmin,
                isin: isin,
                minimumRedeemable: minimumRedeemable
            })
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INIT-CALL SETTER ENCODERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Encodes a call to `IB20.updateSupplyCap(newSupplyCap)`
    ///         as a bootstrap initCall.
    ///
    /// @param  newSupplyCap New supply cap (use `type(uint256).max` for
    ///                      no cap).
    ///
    /// @return The ABI-encoded initCall blob.
    function encodeUpdateSupplyCap(uint256 newSupplyCap) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20.updateSupplyCap, (newSupplyCap));
    }

    /// @notice Encodes a call to `IB20.updateContractURI(newURI)` as a
    ///         bootstrap initCall.
    ///
    /// @param  newURI New contract URI (ERC-7572).
    ///
    /// @return The ABI-encoded initCall blob.
    function encodeUpdateContractURI(string memory newURI) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20.updateContractURI, (newURI));
    }

    /// @notice Encodes a call to `IB20.updateName(newName)` as a
    ///         bootstrap initCall.
    ///
    /// @param  newName New ERC-20 token name. Also updates the EIP-712
    ///                 domain separator's `name` field.
    ///
    /// @return The ABI-encoded initCall blob.
    function encodeUpdateName(string memory newName) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20.updateName, (newName));
    }

    /// @notice Encodes a call to
    ///         `IB20.updatePolicy(policyScope, newPolicyId)` as a
    ///         bootstrap initCall. Use the policy-scope constants from
    ///         `B20Constants` (`TRANSFER_SENDER_POLICY`,
    ///         `TRANSFER_RECEIVER_POLICY`, `TRANSFER_EXECUTOR_POLICY`,
    ///         `MINT_RECEIVER_POLICY`) and from `IB20Security`
    ///         (`REDEEM_SENDER_POLICY()`).
    ///
    /// @param  policyScope The policy-slot identifier.
    /// @param  newPolicyId The new policy registry ID (`0` for
    ///                     always-allow, `1` for always-reject).
    ///
    /// @return The ABI-encoded initCall blob.
    function encodeUpdatePolicy(bytes32 policyScope, uint64 newPolicyId) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20.updatePolicy, (policyScope, newPolicyId));
    }

    /// @notice Encodes a call to `IB20.grantRole(role, account)` as a
    ///         bootstrap initCall. Use the role constants from
    ///         `B20Constants` (`MINT_ROLE`, `BURN_ROLE`,
    ///         `BURN_BLOCKED_ROLE`, `BURN_FROM_ROLE`, `PAUSE_ROLE`,
    ///         `UNPAUSE_ROLE`, `METADATA_ROLE`,
    ///         `SECURITY_OPERATOR_ROLE`).
    ///
    /// @param  role    The role identifier.
    /// @param  account The account to grant the role to.
    ///
    /// @return The ABI-encoded initCall blob.
    function encodeGrantRole(bytes32 role, address account) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20.grantRole, (role, account));
    }

    /// @notice Encodes a call to `IB20.revokeRole(role, account)` as a
    ///         bootstrap initCall. Rare during bootstrap; useful when
    ///         pairing with `setRoleAdmin` to lock down a role.
    ///
    /// @param  role    The role identifier.
    /// @param  account The account to revoke the role from.
    ///
    /// @return The ABI-encoded initCall blob.
    function encodeRevokeRole(bytes32 role, address account) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20.revokeRole, (role, account));
    }

    /// @notice Encodes a call to `IB20.setRoleAdmin(role, newAdminRole)`
    ///         as a bootstrap initCall.
    ///
    /// @param  role         The role whose admin is being changed.
    /// @param  newAdminRole The new admin role for `role`.
    ///
    /// @return The ABI-encoded initCall blob.
    function encodeSetRoleAdmin(bytes32 role, bytes32 newAdminRole) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20.setRoleAdmin, (role, newAdminRole));
    }

    /// @notice Encodes a call to
    ///         `IB20Security.batchMint(recipients, amounts)` as a
    ///         bootstrap initCall. Parallel-array semantics; the
    ///         token reverts on malformed inputs.
    ///
    /// @param  recipients Accounts receiving the minted tokens.
    /// @param  amounts    Per-recipient amounts, parallel to
    ///                    `recipients`.
    ///
    /// @return The ABI-encoded initCall blob.
    function encodeBatchMint(address[] memory recipients, uint256[] memory amounts)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(IB20Security.batchMint, (recipients, amounts));
    }

    /// @notice Encodes a call to
    ///         `IB20Security.updateSecurityIdentifier(identifierType, value)`
    ///         as a bootstrap initCall. Use to attach additional
    ///         identifiers (CUSIP, FIGI, SEDOL, etc.) alongside the
    ///         ISIN set via `B20SecurityCreateParams`.
    ///
    /// @param  identifierType Identifier category (e.g. `"CUSIP"`).
    ///                        Empty string is rejected by the token.
    /// @param  value          New value, or empty string to remove.
    ///
    /// @return The ABI-encoded initCall blob.
    function encodeUpdateSecurityIdentifier(string memory identifierType, string memory value)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(IB20Security.updateSecurityIdentifier, (identifierType, value));
    }

    /*//////////////////////////////////////////////////////////////
                       INIT-CALL ARRAY BUILDERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Builds the `grantRole` initCalls implied by parallel
    ///         `roles` / `accounts` arrays. Entry `k` produces
    ///         `encodeGrantRole(roles[k], accounts[k])`; entries whose
    ///         `accounts[k] == address(0)` are skipped, so callers can
    ///         leave a role unassigned at bootstrap and grant it later.
    ///         Output ordering matches input ordering for the kept
    ///         entries; the returned array is sized exactly to the
    ///         number of grants (no trailing empty slots).
    ///
    /// @dev    Reverts with `LengthMismatch` if `roles` and `accounts`
    ///         differ in length.
    ///
    /// @param  roles    Role identifiers; parallel to `accounts`.
    /// @param  accounts Role holders; parallel to `roles`. `address(0)`
    ///                  entries are skipped.
    ///
    /// @return initCalls The ABI-encoded `grantRole` initCalls.
    function buildRoleGrants(bytes32[] memory roles, address[] memory accounts)
        internal
        pure
        returns (bytes[] memory initCalls)
    {
        if (roles.length != accounts.length) revert LengthMismatch(roles.length, accounts.length);

        uint256 grantCount;
        for (uint256 k = 0; k < accounts.length; k++) {
            if (accounts[k] != address(0)) grantCount++;
        }

        initCalls = new bytes[](grantCount);
        uint256 i;
        for (uint256 k = 0; k < accounts.length; k++) {
            if (accounts[k] != address(0)) {
                initCalls[i++] = encodeGrantRole(roles[k], accounts[k]);
            }
        }
    }

    /// @notice Builds the `updateSecurityIdentifier` initCalls implied
    ///         by parallel `identifierTypes` / `identifierValues`
    ///         arrays. Entry `k` produces
    ///         `encodeUpdateSecurityIdentifier(identifierTypes[k], identifierValues[k])`
    ///         in array order. All entries are emitted; empty types or
    ///         values are passed through to the token, which validates
    ///         them at runtime.
    ///
    /// @dev    Reverts with `LengthMismatch` if `identifierTypes` and
    ///         `identifierValues` differ in length.
    ///
    /// @param  identifierTypes  Identifier categories (e.g. `"CUSIP"`).
    /// @param  identifierValues Values parallel to `identifierTypes`.
    ///
    /// @return initCalls The ABI-encoded `updateSecurityIdentifier`
    ///                   initCalls.
    function buildSecurityIdentifierUpdates(string[] memory identifierTypes, string[] memory identifierValues)
        internal
        pure
        returns (bytes[] memory initCalls)
    {
        if (identifierTypes.length != identifierValues.length) {
            revert LengthMismatch(identifierTypes.length, identifierValues.length);
        }

        initCalls = new bytes[](identifierTypes.length);
        for (uint256 k = 0; k < identifierTypes.length; k++) {
            initCalls[k] = encodeUpdateSecurityIdentifier(identifierTypes[k], identifierValues[k]);
        }
    }

    /// @notice Concatenates two init-call arrays into a single array.
    ///         Useful for stitching a typed-core initCall bundle (e.g.
    ///         the output of `buildRoleGrants`) together with a
    ///         caller-supplied tail of bespoke entries before passing
    ///         the combined array to `createB20`.
    ///
    /// @param  head Init calls to place at the start of the result.
    /// @param  tail Init calls to place after `head`.
    ///
    /// @return initCalls The concatenated array (`head` followed by
    ///                   `tail`), sized exactly to the sum of the
    ///                   input lengths.
    function concat(bytes[] memory head, bytes[] memory tail) internal pure returns (bytes[] memory initCalls) {
        initCalls = new bytes[](head.length + tail.length);
        uint256 i;
        for (uint256 k = 0; k < head.length; k++) {
            initCalls[i++] = head[k];
        }
        for (uint256 k = 0; k < tail.length; k++) {
            initCalls[i++] = tail[k];
        }
    }
}
