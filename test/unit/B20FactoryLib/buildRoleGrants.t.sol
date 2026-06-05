// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {B20Constants} from "base-std/lib/B20Constants.sol";
import {IB20} from "base-std/interfaces/IB20.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibBuildRoleGrantsTest is B20FactoryLibTest {
    /// @notice External wrapper that re-exposes
    ///         `buildRoleGrants(bytes32[], address[])` for revert-path
    ///         tests. Internal library calls inline into the test
    ///         contract; `vm.expectRevert` requires the revert one
    ///         CALL frame deeper, so revert tests must dispatch through
    ///         an external entry point via `this.callBuildRoleGrants`.
    function callBuildRoleGrants(bytes32[] memory roles, address[] memory accounts)
        external
        pure
        returns (bytes[] memory)
    {
        return B20FactoryLib.buildRoleGrants(roles, accounts);
    }

    /*//////////////////////////////////////////////////////////////
                REVERTS — buildRoleGrants(bytes32[], address[])
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies the parallel-arrays overload reverts when
    ///         `roles` and `accounts` differ in length.
    /// @dev    The typed-bundle overloads bypass this check by
    ///         construction; the raw overload is the only public
    ///         entry point that can hit it.
    function test_buildRoleGrants_revert_lengthMismatch(uint8 rolesLenSeed, uint8 accountsLenSeed) public {
        uint256 rolesLen = bound(uint256(rolesLenSeed), 0, 32);
        uint256 accountsLen = bound(uint256(accountsLenSeed), 0, 32);
        vm.assume(rolesLen != accountsLen);
        bytes32[] memory roles = new bytes32[](rolesLen);
        address[] memory accounts = new address[](accountsLen);

        vm.expectRevert(abi.encodeWithSelector(B20FactoryLib.LengthMismatch.selector, rolesLen, accountsLen));
        this.callBuildRoleGrants(roles, accounts);
    }

    /*//////////////////////////////////////////////////////////////
                SUCCESS — buildRoleGrants(bytes32[], address[])
    //////////////////////////////////////////////////////////////*/

    /// @notice Empty parallel arrays produce an empty result.
    /// @dev    Boundary case for the length-zero allocation path.
    function test_buildRoleGrants_rawArrays_success_emptyInputProducesEmpty() public pure {
        bytes[] memory result = B20FactoryLib.buildRoleGrants(new bytes32[](0), new address[](0));
        assertEq(result.length, 0, "empty inputs must produce an empty result");
    }

    /// @notice All-zero accounts produce no grants regardless of role count.
    /// @dev    Pins the "leave a role unassigned at bootstrap" semantics
    ///         that the typed overloads inherit from this primitive.
    function test_buildRoleGrants_rawArrays_success_allZeroAccountsProducesEmpty(uint8 lenSeed) public pure {
        uint256 len = bound(uint256(lenSeed), 0, 16);
        bytes32[] memory roles = new bytes32[](len);
        address[] memory accounts = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            roles[i] = keccak256(abi.encode("role", i));
        }

        bytes[] memory result = B20FactoryLib.buildRoleGrants(roles, accounts);
        assertEq(result.length, 0, "all-zero accounts must produce no grants");
    }

    /// @notice Output preserves input order for the kept entries and skips
    ///         the zero-address slots.
    /// @dev    Mixed-pattern coverage: alternating zero / non-zero accounts.
    ///         The result must contain exactly the non-zero pairs, in input
    ///         order, each encoded as `grantRole(role, account)`.
    function test_buildRoleGrants_rawArrays_success_skipsZeroAddressesAndPreservesOrder(
        bytes32 r0,
        bytes32 r1,
        bytes32 r2,
        address a0,
        address a2
    ) public pure {
        vm.assume(a0 != address(0));
        vm.assume(a2 != address(0));

        bytes32[] memory roles = new bytes32[](3);
        roles[0] = r0;
        roles[1] = r1;
        roles[2] = r2;

        address[] memory accounts = new address[](3);
        accounts[0] = a0;
        accounts[1] = address(0);
        accounts[2] = a2;

        bytes[] memory result = B20FactoryLib.buildRoleGrants(roles, accounts);

        assertEq(result.length, 2, "exactly two non-zero entries must survive");
        assertEq(result[0], abi.encodeCall(IB20.grantRole, (r0, a0)), "first kept entry must use roles[0]/accounts[0]");
        assertEq(result[1], abi.encodeCall(IB20.grantRole, (r2, a2)), "second kept entry must use roles[2]/accounts[2]");
    }

    /// @notice Every non-zero slot produces exactly one grant in array order.
    /// @dev    Density boundary opposite the all-zero case.
    function test_buildRoleGrants_rawArrays_success_allNonZeroProducesFullSet(uint8 lenSeed) public pure {
        uint256 len = bound(uint256(lenSeed), 1, 16);
        bytes32[] memory roles = new bytes32[](len);
        address[] memory accounts = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            roles[i] = keccak256(abi.encode("role", i));
            accounts[i] = address(uint160(uint256(keccak256(abi.encode("acc", i)))));
        }

        bytes[] memory result = B20FactoryLib.buildRoleGrants(roles, accounts);

        assertEq(result.length, len, "every non-zero entry must produce a grant");
        for (uint256 i = 0; i < len; i++) {
            assertEq(result[i], abi.encodeCall(IB20.grantRole, (roles[i], accounts[i])), "ordering must follow input");
        }
    }

    /*//////////////////////////////////////////////////////////////
            SUCCESS — buildRoleGrants(B20RoleHolders memory)
    //////////////////////////////////////////////////////////////*/

    /// @notice An all-zero `B20RoleHolders` bundle produces an empty result.
    /// @dev    Pins the zero-skip semantics for the IB20 typed overload.
    function test_buildRoleGrants_b20Bundle_success_allZeroProducesEmpty() public pure {
        B20FactoryLib.B20RoleHolders memory holders;
        bytes[] memory result = B20FactoryLib.buildRoleGrants(holders);
        assertEq(result.length, 0, "zeroed bundle must produce no grants");
    }

    /// @notice A fully-populated `B20RoleHolders` bundle emits the six
    ///         grants in struct-field order.
    /// @dev    Pins both the canonical role ordering and the field-to-role
    ///         mapping (e.g. `minter` MUST map to `MINT_ROLE`, not
    ///         `BURN_ROLE`). A swap of any two fields/roles would surface
    ///         as a per-index mismatch below.
    function test_buildRoleGrants_b20Bundle_success_emitsAllSixInStructOrder(
        address minter_,
        address burner_,
        address burnBlocker_,
        address pauser_,
        address unpauser_,
        address metadataAdmin_
    ) public pure {
        vm.assume(minter_ != address(0));
        vm.assume(burner_ != address(0));
        vm.assume(burnBlocker_ != address(0));
        vm.assume(pauser_ != address(0));
        vm.assume(unpauser_ != address(0));
        vm.assume(metadataAdmin_ != address(0));

        B20FactoryLib.B20RoleHolders memory holders = B20FactoryLib.B20RoleHolders({
            minter: minter_,
            burner: burner_,
            burnBlocker: burnBlocker_,
            pauser: pauser_,
            unpauser: unpauser_,
            metadataAdmin: metadataAdmin_
        });

        bytes[] memory result = B20FactoryLib.buildRoleGrants(holders);

        assertEq(result.length, 6, "fully-populated bundle must emit six grants");
        assertEq(result[0], abi.encodeCall(IB20.grantRole, (B20Constants.MINT_ROLE, minter_)), "0: MINT_ROLE");
        assertEq(result[1], abi.encodeCall(IB20.grantRole, (B20Constants.BURN_ROLE, burner_)), "1: BURN_ROLE");
        assertEq(
            result[2],
            abi.encodeCall(IB20.grantRole, (B20Constants.BURN_BLOCKED_ROLE, burnBlocker_)),
            "2: BURN_BLOCKED_ROLE"
        );
        assertEq(result[3], abi.encodeCall(IB20.grantRole, (B20Constants.PAUSE_ROLE, pauser_)), "3: PAUSE_ROLE");
        assertEq(result[4], abi.encodeCall(IB20.grantRole, (B20Constants.UNPAUSE_ROLE, unpauser_)), "4: UNPAUSE_ROLE");
        assertEq(
            result[5], abi.encodeCall(IB20.grantRole, (B20Constants.METADATA_ROLE, metadataAdmin_)), "5: METADATA_ROLE"
        );
    }

    /// @notice A `B20RoleHolders` bundle with mixed zero / non-zero holders
    ///         emits only the non-zero entries in struct-field order.
    /// @dev    Pins the mixed-skip behavior. Populates minter, pauser,
    ///         metadataAdmin; leaves burner, burnBlocker, unpauser zero.
    function test_buildRoleGrants_b20Bundle_success_skipsZeroSlots(
        address minter_,
        address pauser_,
        address metadataAdmin_
    ) public pure {
        vm.assume(minter_ != address(0));
        vm.assume(pauser_ != address(0));
        vm.assume(metadataAdmin_ != address(0));

        B20FactoryLib.B20RoleHolders memory holders = B20FactoryLib.B20RoleHolders({
            minter: minter_,
            burner: address(0),
            burnBlocker: address(0),
            pauser: pauser_,
            unpauser: address(0),
            metadataAdmin: metadataAdmin_
        });

        bytes[] memory result = B20FactoryLib.buildRoleGrants(holders);

        assertEq(result.length, 3, "exactly the three non-zero entries must survive");
        assertEq(result[0], abi.encodeCall(IB20.grantRole, (B20Constants.MINT_ROLE, minter_)), "minter first");
        assertEq(result[1], abi.encodeCall(IB20.grantRole, (B20Constants.PAUSE_ROLE, pauser_)), "pauser second");
        assertEq(
            result[2],
            abi.encodeCall(IB20.grantRole, (B20Constants.METADATA_ROLE, metadataAdmin_)),
            "metadataAdmin third"
        );
    }

    /*//////////////////////////////////////////////////////////////
        SUCCESS — buildRoleGrants(B20AssetRoleHolders memory)
    //////////////////////////////////////////////////////////////*/

    /// @notice An all-zero `B20AssetRoleHolders` bundle produces an empty result.
    /// @dev    Pins the zero-skip semantics for the asset typed overload.
    function test_buildRoleGrants_assetBundle_success_allZeroProducesEmpty() public pure {
        B20FactoryLib.B20AssetRoleHolders memory holders;
        bytes[] memory result = B20FactoryLib.buildRoleGrants(holders);
        assertEq(result.length, 0, "zeroed bundle must produce no grants");
    }

    /// @notice A fully-populated `B20AssetRoleHolders` bundle emits the
    ///         seven grants in struct-field order.
    /// @dev    Same field-to-role pinning as the IB20 bundle, extended to
    ///         the asset-only `operator` slot. Catches any swap
    ///         among the seven role IDs.
    function test_buildRoleGrants_assetBundle_success_emitsAllSevenInStructOrder(
        address minter_,
        address burner_,
        address burnBlocker_,
        address pauser_,
        address unpauser_,
        address metadataAdmin_,
        address operator_
    ) public pure {
        vm.assume(minter_ != address(0));
        vm.assume(burner_ != address(0));
        vm.assume(burnBlocker_ != address(0));
        vm.assume(pauser_ != address(0));
        vm.assume(unpauser_ != address(0));
        vm.assume(metadataAdmin_ != address(0));
        vm.assume(operator_ != address(0));

        B20FactoryLib.B20AssetRoleHolders memory holders = B20FactoryLib.B20AssetRoleHolders({
            minter: minter_,
            burner: burner_,
            burnBlocker: burnBlocker_,
            pauser: pauser_,
            unpauser: unpauser_,
            metadataAdmin: metadataAdmin_,
            operator: operator_
        });

        bytes[] memory result = B20FactoryLib.buildRoleGrants(holders);

        assertEq(result.length, 7, "fully-populated asset bundle must emit seven grants");
        assertEq(result[0], abi.encodeCall(IB20.grantRole, (B20Constants.MINT_ROLE, minter_)), "0: MINT_ROLE");
        assertEq(result[1], abi.encodeCall(IB20.grantRole, (B20Constants.BURN_ROLE, burner_)), "1: BURN_ROLE");
        assertEq(
            result[2],
            abi.encodeCall(IB20.grantRole, (B20Constants.BURN_BLOCKED_ROLE, burnBlocker_)),
            "2: BURN_BLOCKED_ROLE"
        );
        assertEq(result[3], abi.encodeCall(IB20.grantRole, (B20Constants.PAUSE_ROLE, pauser_)), "3: PAUSE_ROLE");
        assertEq(result[4], abi.encodeCall(IB20.grantRole, (B20Constants.UNPAUSE_ROLE, unpauser_)), "4: UNPAUSE_ROLE");
        assertEq(
            result[5], abi.encodeCall(IB20.grantRole, (B20Constants.METADATA_ROLE, metadataAdmin_)), "5: METADATA_ROLE"
        );
        assertEq(result[6], abi.encodeCall(IB20.grantRole, (B20Constants.OPERATOR_ROLE, operator_)), "6: OPERATOR_ROLE");
    }

    /// @notice A `B20AssetRoleHolders` bundle with only the
    ///         asset-only slot populated emits exactly that one
    ///         grant.
    /// @dev    Pins that `OPERATOR_ROLE` picks up its slot position
    ///         and the IB20 slots are skipped when zero.
    function test_buildRoleGrants_assetBundle_success_emitsOnlyAssetOnlySlot(address operator_) public pure {
        vm.assume(operator_ != address(0));

        B20FactoryLib.B20AssetRoleHolders memory holders = B20FactoryLib.B20AssetRoleHolders({
            minter: address(0),
            burner: address(0),
            burnBlocker: address(0),
            pauser: address(0),
            unpauser: address(0),
            metadataAdmin: address(0),
            operator: operator_
        });

        bytes[] memory result = B20FactoryLib.buildRoleGrants(holders);

        assertEq(result.length, 1, "exactly the asset-only entry must survive");
        assertEq(result[0], abi.encodeCall(IB20.grantRole, (B20Constants.OPERATOR_ROLE, operator_)), "operator only");
    }
}
