// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Constants} from "./B20Constants.sol";
import {IB20} from "../interfaces/IB20.sol";
import {IB20Asset} from "../interfaces/IB20Asset.sol";
import {IB20Factory} from "../interfaces/IB20Factory.sol";

/// @title  B20FactoryLib
/// @author Coinbase
/// @notice Pure encoder helpers for the `params` blob and `initCalls` array consumed by
///         `IB20Factory.createB20`. No precompile dispatch, no storage reads, no auth checks.
library B20FactoryLib {
    /// @notice Encoding version carried as the leading byte of a `B20StablecoinCreateParams` blob.
    uint8 internal constant B20_STABLECOIN_CREATE_PARAMS_VERSION = 1;

    /// @notice Encoding version carried as the leading byte of a `B20AssetCreateParams` blob.
    uint8 internal constant B20_ASSET_CREATE_PARAMS_VERSION = 1;

    /// @notice Encoding version carried as the leading byte of a `B20StablecoinEventParams` blob.
    uint8 internal constant B20_STABLECOIN_EVENT_PARAMS_VERSION = 1;

    /// @notice Two parallel arrays passed to a `build*` helper had different lengths.
    ///
    /// @param  leftLen  Length of the first array argument.
    /// @param  rightLen Length of the second array argument.
    error LengthMismatch(uint256 leftLen, uint256 rightLen);

    /*//////////////////////////////////////////////////////////////
                          ROLE-HOLDER BUNDLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Bootstrap role-grant bundle for `B20Variant.STABLECOIN`.
    ///         `address(0)` fields are skipped at bootstrap.
    ///
    /// @dev    `DEFAULT_ADMIN_ROLE` is assigned via `B20StablecoinCreateParams.initialAdmin`, not this struct.
    struct B20RoleHolders {
        /// @dev Account granted `MINT_ROLE`.
        address minter;
        /// @dev Account granted `BURN_ROLE`.
        address burner;
        /// @dev Account granted `BURN_BLOCKED_ROLE`.
        address burnBlocker;
        /// @dev Account granted `PAUSE_ROLE`.
        address pauser;
        /// @dev Account granted `UNPAUSE_ROLE`.
        address unpauser;
        /// @dev Account granted `METADATA_ROLE`.
        address metadataAdmin;
    }

    /// @notice Bootstrap role-grant bundle for `B20Variant.ASSET`. Superset of `B20RoleHolders`
    ///         with an `OPERATOR_ROLE` slot.
    ///
    /// @dev    `DEFAULT_ADMIN_ROLE` is assigned via `B20AssetCreateParams.initialAdmin`, not this struct.
    struct B20AssetRoleHolders {
        /// @dev Account granted `MINT_ROLE`.
        address minter;
        /// @dev Account granted `BURN_ROLE`.
        address burner;
        /// @dev Account granted `BURN_BLOCKED_ROLE`.
        address burnBlocker;
        /// @dev Account granted `PAUSE_ROLE`.
        address pauser;
        /// @dev Account granted `UNPAUSE_ROLE`.
        address unpauser;
        /// @dev Account granted `METADATA_ROLE`.
        address metadataAdmin;
        /// @dev Account granted `OPERATOR_ROLE`.
        address operator;
    }

    /*//////////////////////////////////////////////////////////////
                          CREATE-PARAMS ENCODERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Encodes a `B20StablecoinCreateParams` blob tagged with `B20_STABLECOIN_CREATE_PARAMS_VERSION`.
    ///
    /// @param name         ERC-20 token name.
    /// @param symbol       ERC-20 token symbol.
    /// @param initialAdmin Initial holder of `DEFAULT_ADMIN_ROLE`, or `address(0)` to deploy admin-less.
    /// @param currency     Self-declared currency code (uppercase ASCII).
    function encodeStablecoinCreateParams(
        string memory name,
        string memory symbol,
        address initialAdmin,
        string memory currency
    ) internal pure returns (bytes memory) {
        return abi.encode(
            IB20Factory.B20StablecoinCreateParams({
                version: B20_STABLECOIN_CREATE_PARAMS_VERSION,
                name: name,
                symbol: symbol,
                initialAdmin: initialAdmin,
                currency: currency
            })
        );
    }

    /// @notice Encodes a `B20AssetCreateParams` blob tagged with `B20_ASSET_CREATE_PARAMS_VERSION`.
    ///
    /// @param name         ERC-20 token name.
    /// @param symbol       ERC-20 token symbol.
    /// @param initialAdmin Initial holder of `DEFAULT_ADMIN_ROLE`, or `address(0)` to deploy admin-less.
    /// @param decimals     ERC-20 `decimals` value. Must be in `[B20Constants.MIN_ASSET_DECIMALS, B20Constants.MAX_ASSET_DECIMALS]`;
    ///                     out-of-range values cause the factory to revert with `InvalidDecimals`.
    function encodeAssetCreateParams(string memory name, string memory symbol, address initialAdmin, uint8 decimals)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            IB20Factory.B20AssetCreateParams({
                version: B20_ASSET_CREATE_PARAMS_VERSION,
                name: name,
                symbol: symbol,
                initialAdmin: initialAdmin,
                decimals: decimals
            })
        );
    }

    /// @notice Encodes a `B20StablecoinEventParams` as the `variantEventParams` blob the factory
    ///         emits in the `B20Created` event for `B20Variant.STABLECOIN`.
    ///
    /// @param currency ISO 4217 fiat code this stablecoin tracks.
    function encodeStablecoinEventParams(string memory currency) internal pure returns (bytes memory) {
        return abi.encode(
            IB20Factory.B20StablecoinEventParams({version: B20_STABLECOIN_EVENT_PARAMS_VERSION, currency: currency})
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INIT-CALL SETTER ENCODERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Encodes a bootstrap initCall to `IB20.updateSupplyCap`.
    /// @param newSupplyCap New supply cap (`type(uint128).max` for no cap).
    function encodeUpdateSupplyCap(uint256 newSupplyCap) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20.updateSupplyCap, (newSupplyCap));
    }

    /// @notice Encodes a bootstrap initCall to `IB20.updateContractURI`.
    /// @param newURI New contract URI (ERC-7572).
    function encodeUpdateContractURI(string memory newURI) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20.updateContractURI, (newURI));
    }

    /// @notice Encodes a bootstrap initCall to `IB20.updateName`.
    /// @param newName New ERC-20 token name.
    function encodeUpdateName(string memory newName) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20.updateName, (newName));
    }

    /// @notice Encodes a bootstrap initCall to `IB20.updatePolicy`.
    ///
    /// @param policyScope The policy-slot scope.
    /// @param newPolicyId The new policy registry ID.
    function encodeUpdatePolicy(bytes32 policyScope, uint64 newPolicyId) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20.updatePolicy, (policyScope, newPolicyId));
    }

    /// @notice Encodes a bootstrap initCall to `IB20.grantRole`.
    ///
    /// @param role    Role to grant.
    /// @param account Account to grant the role to.
    function encodeGrantRole(bytes32 role, address account) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20.grantRole, (role, account));
    }

    /// @notice Encodes a bootstrap initCall to `IB20.revokeRole`.
    ///
    /// @param role    Role to revoke.
    /// @param account Account to revoke the role from.
    function encodeRevokeRole(bytes32 role, address account) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20.revokeRole, (role, account));
    }

    /// @notice Encodes a bootstrap initCall to `IB20.setRoleAdmin`.
    ///
    /// @param role         Role whose admin is being changed.
    /// @param newAdminRole New admin role for `role`.
    function encodeSetRoleAdmin(bytes32 role, bytes32 newAdminRole) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20.setRoleAdmin, (role, newAdminRole));
    }

    /// @notice Encodes a bootstrap initCall to `IB20Asset.batchMint`.
    ///
    /// @param recipients Accounts receiving the minted tokens.
    /// @param amounts    Per-recipient amounts, parallel to `recipients`.
    function encodeBatchMint(address[] memory recipients, uint256[] memory amounts)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(IB20Asset.batchMint, (recipients, amounts));
    }

    /// @notice Encodes a bootstrap initCall to `IB20Asset.updateExtraMetadata`.
    ///
    /// @param key   Metadata entry key (e.g. `"category"`).
    /// @param value New value, or empty string to remove.
    function encodeUpdateExtraMetadata(string memory key, string memory value) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20Asset.updateExtraMetadata, (key, value));
    }

    /// @notice Encodes a bootstrap initCall to `IB20Asset.updateMultiplier`.
    /// @param newMultiplier New multiplier, scaled to `WAD_PRECISION`.
    function encodeUpdateMultiplier(uint256 newMultiplier) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20Asset.updateMultiplier, (newMultiplier));
    }

    /*//////////////////////////////////////////////////////////////
                       INIT-CALL ARRAY BUILDERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Builds the `grantRole` initCalls implied by a `B20RoleHolders` bundle, in struct-field
    ///         order. `address(0)` fields are skipped; the result is sized exactly to the kept entries.
    ///
    /// @param holders Role-holder bundle.
    /// @return initCalls ABI-encoded `grantRole` initCalls.
    function buildRoleGrants(B20RoleHolders memory holders) internal pure returns (bytes[] memory initCalls) {
        bytes32[] memory roles = new bytes32[](6);
        roles[0] = B20Constants.MINT_ROLE;
        roles[1] = B20Constants.BURN_ROLE;
        roles[2] = B20Constants.BURN_BLOCKED_ROLE;
        roles[3] = B20Constants.PAUSE_ROLE;
        roles[4] = B20Constants.UNPAUSE_ROLE;
        roles[5] = B20Constants.METADATA_ROLE;

        address[] memory accounts = new address[](6);
        accounts[0] = holders.minter;
        accounts[1] = holders.burner;
        accounts[2] = holders.burnBlocker;
        accounts[3] = holders.pauser;
        accounts[4] = holders.unpauser;
        accounts[5] = holders.metadataAdmin;

        return buildRoleGrants(roles, accounts);
    }

    /// @notice Same as `buildRoleGrants(B20RoleHolders)`, but for the asset role set.
    ///
    /// @param holders Asset role-holder bundle.
    /// @return initCalls ABI-encoded `grantRole` initCalls.
    function buildRoleGrants(B20AssetRoleHolders memory holders) internal pure returns (bytes[] memory initCalls) {
        bytes32[] memory roles = new bytes32[](7);
        roles[0] = B20Constants.MINT_ROLE;
        roles[1] = B20Constants.BURN_ROLE;
        roles[2] = B20Constants.BURN_BLOCKED_ROLE;
        roles[3] = B20Constants.PAUSE_ROLE;
        roles[4] = B20Constants.UNPAUSE_ROLE;
        roles[5] = B20Constants.METADATA_ROLE;
        roles[6] = B20Constants.OPERATOR_ROLE;

        address[] memory accounts = new address[](7);
        accounts[0] = holders.minter;
        accounts[1] = holders.burner;
        accounts[2] = holders.burnBlocker;
        accounts[3] = holders.pauser;
        accounts[4] = holders.unpauser;
        accounts[5] = holders.metadataAdmin;
        accounts[6] = holders.operator;

        return buildRoleGrants(roles, accounts);
    }

    /// @notice Builds the `grantRole` initCalls implied by parallel `roles` / `accounts` arrays.
    ///         Entries where `accounts[k] == address(0)` are skipped; the result preserves input order
    ///         and is sized exactly to the kept entries.
    ///
    /// @dev Reverts with `LengthMismatch` when `roles.length != accounts.length`.
    ///
    /// @param roles    Roles to grant, parallel to `accounts`.
    /// @param accounts Role holders, parallel to `roles`.
    /// @return initCalls ABI-encoded `grantRole` initCalls.
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

    /// @notice Builds the `updateExtraMetadata` initCalls implied by parallel
    ///         `keys` / `values` arrays. All entries are emitted in input order.
    ///
    /// @dev Reverts with `LengthMismatch` when `keys.length != values.length`.
    ///
    /// @param keys   Metadata entry keys (e.g. `"category"`).
    /// @param values Values parallel to `keys`.
    /// @return initCalls ABI-encoded `updateExtraMetadata` initCalls.
    function buildExtraMetadataUpdates(string[] memory keys, string[] memory values)
        internal
        pure
        returns (bytes[] memory initCalls)
    {
        if (keys.length != values.length) {
            revert LengthMismatch(keys.length, values.length);
        }

        initCalls = new bytes[](keys.length);
        for (uint256 k = 0; k < keys.length; k++) {
            initCalls[k] = encodeUpdateExtraMetadata(keys[k], values[k]);
        }
    }

    /// @notice Concatenates `head` and `tail` into a single init-call array, preserving order.
    ///
    /// @param head Init calls placed first.
    /// @param tail Init calls placed after `head`. May be empty.
    /// @return initCalls Concatenated array, sized `head.length + tail.length`.
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
