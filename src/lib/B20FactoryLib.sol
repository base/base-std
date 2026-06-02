// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Constants} from "./B20Constants.sol";
import {IB20} from "../interfaces/IB20.sol";
import {IB20Factory} from "../interfaces/IB20Factory.sol";
import {IB20Security} from "../interfaces/IB20Security.sol";

/// @title  B20FactoryLib
/// @author Coinbase
/// @notice Pure encoder helpers for the `params` blob and `initCalls` array consumed by
///         `IB20Factory.createB20`. No precompile dispatch, no storage reads, no auth checks.
library B20FactoryLib {
    /// @notice Encoding version carried as the leading byte of a `B20StablecoinCreateParams` blob.
    uint8 internal constant B20_STABLECOIN_CREATE_PARAMS_VERSION = 1;

    /// @notice Encoding version carried as the leading byte of a `B20SecurityCreateParams` blob.
    uint8 internal constant B20_SECURITY_CREATE_PARAMS_VERSION = 1;

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

    /// @notice Bootstrap role-grant bundle for `B20Variant.SECURITY`. Superset of `B20RoleHolders`
    ///         with `BURN_FROM_ROLE` and `SECURITY_OPERATOR_ROLE` slots.
    ///
    /// @dev    `DEFAULT_ADMIN_ROLE` is assigned via `B20SecurityCreateParams.initialAdmin`, not this struct.
    struct B20SecurityRoleHolders {
        /// @dev Account granted `MINT_ROLE`.
        address minter;
        /// @dev Account granted `BURN_ROLE`.
        address burner;
        /// @dev Account granted `BURN_BLOCKED_ROLE`.
        address burnBlocker;
        /// @dev Account granted `BURN_FROM_ROLE`.
        address burnFromOperator;
        /// @dev Account granted `PAUSE_ROLE`.
        address pauser;
        /// @dev Account granted `UNPAUSE_ROLE`.
        address unpauser;
        /// @dev Account granted `METADATA_ROLE`.
        address metadataAdmin;
        /// @dev Account granted `SECURITY_OPERATOR_ROLE`.
        address securityOperator;
    }

    /*//////////////////////////////////////////////////////////////
                          CREATE-PARAMS ENCODERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Encodes a `B20StablecoinCreateParams` blob tagged with `B20_STABLECOIN_CREATE_PARAMS_VERSION`.
    ///
    /// @param name         ERC-20 token name.
    /// @param symbol       ERC-20 token symbol.
    /// @param initialAdmin Initial holder of `DEFAULT_ADMIN_ROLE`, or `address(0)` to deploy admin-less.
    /// @param currency     Self-declared currency identifier (uppercase ASCII).
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

    /// @notice Encodes a `B20SecurityCreateParams` blob tagged with `B20_SECURITY_CREATE_PARAMS_VERSION`.
    ///
    /// @param name         ERC-20 token name.
    /// @param symbol       ERC-20 token symbol.
    /// @param initialAdmin Initial holder of `DEFAULT_ADMIN_ROLE`, or `address(0)` to deploy admin-less.
    function encodeSecurityCreateParams(string memory name, string memory symbol, address initialAdmin)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            IB20Factory.B20SecurityCreateParams({
                version: B20_SECURITY_CREATE_PARAMS_VERSION, name: name, symbol: symbol, initialAdmin: initialAdmin
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
    /// @param newSupplyCap New supply cap (`type(uint256).max` for no cap).
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
    /// @param policyScope The policy-slot identifier.
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

    /// @notice Encodes a bootstrap initCall to `IB20Security.batchMint`.
    ///
    /// @param recipients Accounts receiving the minted tokens.
    /// @param amounts    Per-recipient amounts, parallel to `recipients`.
    function encodeBatchMint(address[] memory recipients, uint256[] memory amounts)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(IB20Security.batchMint, (recipients, amounts));
    }

    /// @notice Encodes a bootstrap initCall to `IB20Security.updateSecurityIdentifier`.
    ///
    /// @param identifierType Identifier category (e.g. `"CUSIP"`).
    /// @param value          New value, or empty string to remove.
    function encodeUpdateSecurityIdentifier(string memory identifierType, string memory value)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(IB20Security.updateSecurityIdentifier, (identifierType, value));
    }

    /// @notice Encodes a bootstrap initCall to `IB20Security.updateShareRatio`.
    /// @param newShareRatio New shares-to-tokens ratio, scaled to `WAD_PRECISION`.
    function encodeUpdateShareRatio(uint256 newShareRatio) internal pure returns (bytes memory) {
        return abi.encodeCall(IB20Security.updateShareRatio, (newShareRatio));
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

    /// @notice Same as `buildRoleGrants(B20RoleHolders)`, but for the security role set.
    ///
    /// @param holders Security role-holder bundle.
    /// @return initCalls ABI-encoded `grantRole` initCalls.
    function buildRoleGrants(B20SecurityRoleHolders memory holders) internal pure returns (bytes[] memory initCalls) {
        bytes32[] memory roles = new bytes32[](8);
        roles[0] = B20Constants.MINT_ROLE;
        roles[1] = B20Constants.BURN_ROLE;
        roles[2] = B20Constants.BURN_BLOCKED_ROLE;
        roles[3] = B20Constants.BURN_FROM_ROLE;
        roles[4] = B20Constants.PAUSE_ROLE;
        roles[5] = B20Constants.UNPAUSE_ROLE;
        roles[6] = B20Constants.METADATA_ROLE;
        roles[7] = B20Constants.SECURITY_OPERATOR_ROLE;

        address[] memory accounts = new address[](8);
        accounts[0] = holders.minter;
        accounts[1] = holders.burner;
        accounts[2] = holders.burnBlocker;
        accounts[3] = holders.burnFromOperator;
        accounts[4] = holders.pauser;
        accounts[5] = holders.unpauser;
        accounts[6] = holders.metadataAdmin;
        accounts[7] = holders.securityOperator;

        return buildRoleGrants(roles, accounts);
    }

    /// @notice Builds the `grantRole` initCalls implied by parallel `roles` / `accounts` arrays.
    ///         Entries where `accounts[k] == address(0)` are skipped; the result preserves input order
    ///         and is sized exactly to the kept entries.
    ///
    /// @dev Reverts with `LengthMismatch` when `roles.length != accounts.length`.
    ///
    /// @param roles    Role identifiers, parallel to `accounts`.
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

    /// @notice Builds the `updateSecurityIdentifier` initCalls implied by parallel
    ///         `identifierTypes` / `identifierValues` arrays. All entries are emitted in input order.
    ///
    /// @dev Reverts with `LengthMismatch` when `identifierTypes.length != identifierValues.length`.
    ///
    /// @param identifierTypes  Identifier categories (e.g. `"CUSIP"`).
    /// @param identifierValues Values parallel to `identifierTypes`.
    /// @return initCalls ABI-encoded `updateSecurityIdentifier` initCalls.
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
