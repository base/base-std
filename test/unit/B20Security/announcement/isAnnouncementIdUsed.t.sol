// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

import {MockB20SecurityStorage} from "test/lib/mocks/MockB20Storage.sol";

contract B20SecurityIsAnnouncementIdUsedTest is B20SecurityTest {
    /// @notice Verifies isAnnouncementIdUsed returns false for an unseen id
    /// @dev Default mapping value is false; readback for any id never passed to announce
    ///      must be false. Fuzz over arbitrary strings.
    function test_isAnnouncementIdUsed_success_falseForUnseen(string calldata id) public view {
        assertFalse(security().isAnnouncementIdUsed(id), "unseen id must read as not used");
    }

    /// @notice Verifies isAnnouncementIdUsed returns true after announce consumes the id
    /// @dev Property: announce(id, ...) marks `usedAnnouncementIds[id]` true; subsequent
    ///      reads must return true. Paired slot assertion verifies the storage flag flipped.
    function test_isAnnouncementIdUsed_success_trueAfterAnnounce(string calldata id) public {
        _announce(id);

        assertTrue(security().isAnnouncementIdUsed(id), "consumed id must read as used");
        assertEq(
            uint256(vm.load(address(token), MockB20SecurityStorage.usedAnnouncementIdSlot(id))),
            uint256(1),
            "usedAnnouncementIds[id] slot must be set after announce"
        );
    }
}
