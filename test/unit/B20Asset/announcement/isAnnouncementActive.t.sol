// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "test/lib/B20AssetTest.sol";

contract B20AssetIsAnnouncementActiveTest is B20AssetTest {
    /// @notice Verifies isAnnouncementActive is false before any announce
    /// @dev Default transient value is false; readback on a freshly bootstrapped token
    ///      with no announce call yet must report false. Fuzz parameter would add
    ///      no value here — the view takes no input.
    function test_isAnnouncementActive_success_falseBeforeAnnounce() public view {
        assertFalse(asset().isAnnouncementActive(), "must read false before any announce");
    }

    /// @notice Verifies isAnnouncementActive resets to false after a completed announce
    /// @dev The bracket flips the flag true at open and false at close. After a
    ///      successful announce returns, the next external view call must observe false.
    ///      Fuzz over `id` to exercise the flag-reset path independently of the consumed-id
    ///      bookkeeping that `isAnnouncementIdUsed` already covers.
    function test_isAnnouncementActive_success_falseAfterAnnounce(string calldata id) public {
        _announce(id);
        assertFalse(asset().isAnnouncementActive(), "must read false after announce closes");
    }

    /// @notice Verifies the flag also resets when announce reverts mid-bracket
    /// @dev Per EIP-1153, transient storage is cleared at transaction end regardless of
    ///      whether the top-level call succeeds. A revert inside `internalCalls` therefore
    ///      cannot leave the flag stuck `true` across transactions. We trigger the
    ///      revert path via the existing recursion guard (inner call re-invoking `announce`
    ///      reverts AnnouncementInProgress), then in a *separate* transaction observe the
    ///      view reads false.
    function test_isAnnouncementActive_success_falseAfterRevertedAnnounce() public {
        _grantOperator();

        // Inner call that the recursion guard will reject — forces the outer
        // announce to revert AFTER the flag has been set true at the top of the body.
        bytes[] memory inner = _singletonBytes(
            abi.encodeWithSelector(
                bytes4(keccak256("announce(bytes[],string,string,string)")),
                new bytes[](0),
                "inner",
                "desc",
                "uri"
            )
        );

        vm.prank(operator);
        // Don't care about the specific revert selector here; any revert during the
        // bracket exercises the "did the flag survive the abort?" property.
        try asset().announce(inner, "id-revert", "desc", "uri") {
            revert("announce was expected to revert");
        } catch {}

        // New top-level call — transient storage from the prior reverted tx is gone.
        assertFalse(asset().isAnnouncementActive(), "transient flag must reset after a reverted announce");
    }
}
