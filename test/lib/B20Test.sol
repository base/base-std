// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {IB20} from "src/interfaces/IB20.sol";

/// @notice Base test contract for `IB20` unit tests.
///
/// `setUp` is mock-vs-live aware: in mock mode the test factory + token
/// implementation are etched and a default-variant token is deployed via
/// the factory's `createToken` path so the token's identity bytes
/// (variant byte at address `[10]`, decimals byte at `[11]`) match the
/// real address schema. In live mode under `--fork-url`, the same flow
/// hits the real precompile factory.
///
/// The mock contracts are added in a follow-up PR; until then, `token`
/// is the zero address and the unit stubs in this spec PR are not yet
/// implemented, so this is intentional.
contract B20Test is Test {
    // -- Actors --
    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal burner = makeAddr("burner");
    address internal pauser = makeAddr("pauser");
    address internal unpauser = makeAddr("unpauser");
    address internal burnBlocker = makeAddr("burnBlocker");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    // -- Token under test --
    /// @notice Default-variant `IB20` token deployed in `setUp`.
    IB20 internal token;

    // -- Setup --
    function setUp() public virtual {
        vm.label(admin, "admin");
        vm.label(minter, "minter");
        vm.label(burner, "burner");
        vm.label(pauser, "pauser");
        vm.label(unpauser, "unpauser");
        vm.label(burnBlocker, "burnBlocker");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(attacker, "attacker");

        // TODO(mock PR): etch MockTokenFactory at StdPrecompiles.TOKEN_FACTORY_ADDRESS
        // (mock-mode only) and deploy a default-variant token here via the factory
        // with initCalls that grant MINT_ROLE / BURN_ROLE / PAUSE_ROLE / UNPAUSE_ROLE /
        // BURN_BLOCKED_ROLE to the corresponding actors. Assign the returned address
        // to `token` and `vm.label` it. Live mode under --fork-url skips the etch.
    }

    // -- ERC-20 action wrappers --

    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transfer(to, amount);
    }

    function _transfer() internal {
        _transfer(alice, bob, 100);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        token.approve(spender, amount);
    }

    function _approve() internal {
        _approve(alice, bob, type(uint256).max);
    }

    function _transferFrom(address caller, address from, address to, uint256 amount) internal {
        vm.prank(caller);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transferFrom(from, to, amount);
    }

    function _transferFrom() internal {
        _transferFrom(bob, alice, bob, 100);
    }

    // -- Memo variants --

    function _transferWithMemo(address from, address to, uint256 amount, bytes32 memo) internal {
        vm.prank(from);
        token.transferWithMemo(to, amount, memo);
    }

    function _transferFromWithMemo(address caller, address from, address to, uint256 amount, bytes32 memo) internal {
        vm.prank(caller);
        token.transferFromWithMemo(from, to, amount, memo);
    }

    function _mintWithMemo(address caller, address to, uint256 amount, bytes32 memo) internal {
        vm.prank(caller);
        token.mintWithMemo(to, amount, memo);
    }

    function _burnWithMemo(address caller, uint256 amount, bytes32 memo) internal {
        vm.prank(caller);
        token.burnWithMemo(amount, memo);
    }

    // -- Mint / burn --

    function _mint(address caller, address to, uint256 amount) internal {
        vm.prank(caller);
        token.mint(to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        _mint(minter, to, amount);
    }

    function _mint() internal {
        _mint(minter, alice, 1_000e18);
    }

    function _burn(address caller, uint256 amount) internal {
        vm.prank(caller);
        token.burn(amount);
    }

    function _burn() internal {
        _burn(burner, 100e18);
    }

    function _burnBlocked(address caller, address from, uint256 amount) internal {
        vm.prank(caller);
        token.burnBlocked(from, amount);
    }

    // -- Roles --

    function _grantRole(address caller, bytes32 role, address account) internal {
        vm.prank(caller);
        token.grantRole(role, account);
    }

    function _grantRole(bytes32 role, address account) internal {
        _grantRole(admin, role, account);
    }

    function _revokeRole(address caller, bytes32 role, address account) internal {
        vm.prank(caller);
        token.revokeRole(role, account);
    }

    function _renounceRole(address caller, bytes32 role) internal {
        vm.prank(caller);
        token.renounceRole(role, caller);
    }

    function _setRoleAdmin(address caller, bytes32 role, bytes32 newAdminRole) internal {
        vm.prank(caller);
        token.setRoleAdmin(role, newAdminRole);
    }

    // -- Pause --

    function _pause(address caller, IB20.PausableFeature[] memory features) internal {
        vm.prank(caller);
        token.pause(features);
    }

    function _pause(IB20.PausableFeature[] memory features) internal {
        _pause(pauser, features);
    }

    function _pause(IB20.PausableFeature feature) internal {
        IB20.PausableFeature[] memory features = new IB20.PausableFeature[](1);
        features[0] = feature;
        _pause(features);
    }

    function _unpause(address caller, IB20.PausableFeature[] memory features) internal {
        vm.prank(caller);
        token.unpause(features);
    }

    function _unpause(IB20.PausableFeature[] memory features) internal {
        _unpause(unpauser, features);
    }

    function _unpause(IB20.PausableFeature feature) internal {
        IB20.PausableFeature[] memory features = new IB20.PausableFeature[](1);
        features[0] = feature;
        _unpause(features);
    }

    // -- Policy --

    function _updatePolicy(address caller, bytes32 policyType, uint64 policyId_) internal {
        vm.prank(caller);
        token.updatePolicy(policyType, policyId_);
    }

    function _updatePolicy(bytes32 policyType, uint64 policyId_) internal {
        _updatePolicy(admin, policyType, policyId_);
    }

    // -- Supply cap / metadata --

    function _setSupplyCap(address caller, uint256 newCap) internal {
        vm.prank(caller);
        token.setSupplyCap(newCap);
    }

    function _setName(address caller, string memory newName) internal {
        vm.prank(caller);
        token.setName(newName);
    }

    function _setSymbol(address caller, string memory newSymbol) internal {
        vm.prank(caller);
        token.setSymbol(newSymbol);
    }

    function _setContractURI(address caller, string memory newURI) internal {
        vm.prank(caller);
        token.setContractURI(newURI);
    }
}
