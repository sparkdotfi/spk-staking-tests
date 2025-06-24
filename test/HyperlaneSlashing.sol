// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";
import "forge-std/console.sol";

interface INetworkDelegator is IAccessControl {}

contract GovernanceSlashingTest is BaseTest {

function test_hyperlaneCanSlashUpToNetworkLimit() public {

        // --- Step 1: Deposit 10m SPK to stSPK as two users

        deal(address(spk), alice, 6_000_000e18);
        deal(address(spk), bob,   4_000_000e18);

        vm.startPrank(alice);
        spk.approve(address(sSpk), 6_000_000e18);
        sSpk.deposit(alice, 6_000_000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        spk.approve(address(sSpk), 4_000_000e18);
        sSpk.deposit(bob, 4_000_000e18);
        vm.stopPrank();

        uint48 depositTimestamp = uint48(block.timestamp);

        skip(24 hours);  // Warp 24 hours

        // --- Step 2: Request a slash of all staked SPK (show that network limit is hit)

        uint48 captureTimestamp = uint48(block.timestamp - 1 seconds);  // Can't capture current timestamp and above

        // Demonstrate that the slashable stake is 100k SPK at the deposit and capture timestamps, and 0 before deposit
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, depositTimestamp - 1, ""), 0);
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, depositTimestamp,     ""), 2_000_000e18);
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp,     ""), 2_000_000e18);

        vm.prank(HYPERLANE_NETWORK);
        uint256 slashIndex = slasher.requestSlash(subnetwork, OPERATOR, 10_000_000e18, captureTimestamp, "");

        assertEq(slasher.slashRequestsLength(), 1);

        ( ,, uint256 amount,,, bool completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    2_000_000e18);  // Can't request to slash more than the network limit (requested full 10m)
        assertEq(completed, false);

        // --- Step 3: Fast-forward past veto window and execute the slash

        skip(3 days + 1);

        assertEq(sSpk.activeBalanceOf(alice), 6_000_000e18);
        assertEq(sSpk.activeBalanceOf(bob),   4_000_000e18);
        assertEq(sSpk.totalStake(),           TOTAL_STAKE + 10_000_000e18);

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""), 2_000_000e18);

        assertEq(spk.balanceOf(address(sSpk)), TOTAL_STAKE + 10_000_000e18);
        assertEq(spk.balanceOf(BURNER_ROUTER), 0);

        assertEq(slasher.latestSlashedCaptureTimestamp(subnetwork, OPERATOR), 0);
        assertEq(slasher.cumulativeSlash(subnetwork, OPERATOR),               0);

        assertEq(delegator.operatorNetworkShares(subnetwork, OPERATOR), 1e18);

        vm.prank(HYPERLANE_NETWORK);
        slasher.executeSlash(slashIndex, "");

        assertEq(delegator.operatorNetworkShares(subnetwork, OPERATOR), 0);

        // Show that active stake is reduced proportionally with withdrawals
        assertEq(sSpk.activeStake(), ACTIVE_STAKE + 10_000_000e18 - 2_000_000e18 * sSpk.activeStake() / sSpk.totalStake());

        // Show that active balance is reduced proportionally with withdrawals
        assertEq(sSpk.activeBalanceOf(alice), 6_000_000e18 * sSpk.activeStake() / sSpk.activeShares());
        assertEq(sSpk.activeBalanceOf(bob),   4_000_000e18 * sSpk.activeStake() / sSpk.activeShares());

        assertEq(sSpk.activeBalanceOf(alice), 5_758_950.300616223287308507e18);
        assertEq(sSpk.activeBalanceOf(bob),   3_839_300.200410815524872338e18);

        assertEq(sSpk.totalStake(), TOTAL_STAKE + 10_000_000e18 - 2_000_000e18);

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""), 0);

        assertEq(spk.balanceOf(address(sSpk)), TOTAL_STAKE + 10_000_000e18 - 2_000_000e18);
        assertEq(spk.balanceOf(BURNER_ROUTER), 2_000_000e18);

        assertEq(slasher.latestSlashedCaptureTimestamp(subnetwork, OPERATOR), captureTimestamp);
        assertEq(slasher.cumulativeSlash(subnetwork, OPERATOR),               2_000_000e18);

        ( ,, amount,,, completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    2_000_000e18);
        assertEq(completed, true);

        uint256 governanceBalance = spk.balanceOf(SPARK_GOVERNANCE);

        // --- Step 4: Transfer funds from the burner router to Spark Governance
        //         NOTE: This can be called by anyone

        IBurnerRouter(BURNER_ROUTER).triggerTransfer(SPARK_GOVERNANCE);

        assertEq(spk.balanceOf(BURNER_ROUTER),    0);
        assertEq(spk.balanceOf(SPARK_GOVERNANCE), governanceBalance + 2_000_000e18);

        // --- Step 5: Show that slasher cannot slash anymore with the same request

        // Can't execute the same slash again
        vm.prank(HYPERLANE_NETWORK);
        vm.expectRevert("InsufficientSlash()");
        slasher.executeSlash(slashIndex, "");

        // --- Step 6: Show that slasher also cannot request new slashes because the network limit has been hit

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""), 0);

        // Try to slash from the same capture timestamp that was already slashed
        vm.prank(HYPERLANE_NETWORK);
        vm.expectRevert("InsufficientSlash()");
        slashIndex = slasher.requestSlash(subnetwork, OPERATOR, 100e18, captureTimestamp, "");  // Use the same capture timestamp

        // --- Step 7: Demonstrate that the slashable stake never increases again

        skip(100 days);

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, uint48(block.timestamp - 1), ""), 0);

        // Try to slash from a new capture timestamp that is long after the last slash was completed
        vm.prank(HYPERLANE_NETWORK);
        vm.expectRevert("InsufficientSlash()");
        slasher.requestSlash(subnetwork, OPERATOR, 100e18, uint48(block.timestamp - 1), "");  // Use the same capture timestamp
    }

    function test_ownerMultisigCanVetoSlash() public {

        // --- Step 1: Deposit 10m SPK to stSPK as two users

        deal(address(spk), alice, 6_000_000e18);
        deal(address(spk), bob,   4_000_000e18);

        vm.startPrank(alice);
        spk.approve(address(sSpk), 6_000_000e18);
        sSpk.deposit(alice, 6_000_000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        spk.approve(address(sSpk), 4_000_000e18);
        sSpk.deposit(bob, 4_000_000e18);
        vm.stopPrank();

        skip(24 hours);  // Warp 24 hours

        // --- Step 2: Request a slash of 10% of staked SPK (500)

        uint48 captureTimestamp = uint48(block.timestamp - 1 hours);

        vm.prank(HYPERLANE_NETWORK);
        uint256 slashIndex = slasher.requestSlash(subnetwork, OPERATOR, 10_000_000e18, captureTimestamp, "");

        assertEq(slasher.slashRequestsLength(), 1);

        ( ,, uint256 amount,,, bool completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    2_000_000e18);  // Can't request to slash more than the network limit (requested full 10m)
        assertEq(completed, false);

        // --- Step 3: Owner multisig vetos the slash request

        skip(3 days - 1 seconds);  // Demonstrate multisig has a full three days from request to veto

        vm.prank(OWNER_MULTISIG);
        slasher.vetoSlash(slashIndex, "");

        ( ,, amount,,, completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    2_000_000e18);
        assertEq(completed, true);  // Prevents execution of the slash

        // --- Step 4: Attempt to execute the slashing after veto (should fail)

        skip(1 seconds);  // Fast-forward to the next block to pass the check to show relevant error

        vm.prank(HYPERLANE_NETWORK);
        vm.expectRevert("SlashRequestCompleted()");
        slasher.executeSlash(slashIndex, "");
    }

    function test_slashableStakeRechargingAfterSlashing() public {
        deal(address(spk), alice, 10_000_000e18);
        vm.startPrank(alice);
        spk.approve(address(sSpk), 10_000_000e18);
        sSpk.deposit(alice, 10_000_000e18);
        vm.stopPrank();

        skip(24 hours);

        uint256 totalSlashed = 0;
        uint256[] memory slashIndices = new uint256[](100);

        // Request slashes every second for 100 seconds
        for (uint256 i = 0; i < 100; i++) {
            uint48 captureTimestamp = uint48(block.timestamp - 1 seconds);

            // Check that we can still slash the full network limit since nothing has been slashed yet
            uint256 slashableAmount = slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, "");
            assertEq(slashableAmount, 2_000_000e18, "Should be able to slash full network limit");

            // Request slash
            vm.prank(HYPERLANE_NETWORK);
            slashIndices[i] = slasher.requestSlash(subnetwork, OPERATOR, 25_000e18, captureTimestamp, "");

            // Move forward 1 second for next iteration
            skip(1 seconds);
        }

        // Wait 3 days + 5 seconds to pass all the veto windows for four successful slashes
        skip(3 days + 4 seconds + 1 seconds);

        uint48 firstSlashTimestamp = uint48(block.timestamp);

        // Execute all slashes at once
        for (uint256 i = 0; i < 80; i++) {
            // Get the capture timestamp for this slash request
            (,,, uint48 captureTimestamp,,) = slasher.slashRequests(slashIndices[i]);

            vm.prank(HYPERLANE_NETWORK);
            uint256 slashedAmount = slasher.executeSlash(slashIndices[i], "");

            skip(10 seconds);

            totalSlashed += slashedAmount;

            assertEq(slasher.latestSlashedCaptureTimestamp(subnetwork, OPERATOR),                  captureTimestamp);
            assertEq(slasher.cumulativeSlash(subnetwork, OPERATOR),                                totalSlashed);
            assertEq(slasher.cumulativeSlashAt(subnetwork, OPERATOR, captureTimestamp, ""),        0);
            assertEq(slasher.cumulativeSlashAt(subnetwork, OPERATOR, uint48(block.timestamp), ""), totalSlashed);
            assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""),           2_000_000e18 - totalSlashed);
        }

        // Try to execute the 81th slash (should fail because slashable stake is 0)
        vm.prank(HYPERLANE_NETWORK);
        vm.expectRevert("InsufficientSlash()");
        slasher.executeSlash(slashIndices[80], "");

        // Show that future timestamps are always 0
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, firstSlashTimestamp + 40, ""), 0);

        skip(1 hours);  // Warp 1 hour so time is ahead of all of these timestamps

        assertEq(slasher.cumulativeSlash(subnetwork, OPERATOR), 2_000_000e18);

        // As soon as the first slash is executed, the slashable stake goes back up to 25k
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, firstSlashTimestamp - 1, ""), 0);
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, firstSlashTimestamp,     ""), 25_000e18);

        assertEq(slasher.cumulativeSlashAt(subnetwork, OPERATOR, firstSlashTimestamp - 1, ""), 0);
        assertEq(slasher.cumulativeSlashAt(subnetwork, OPERATOR, firstSlashTimestamp,     ""), 25_000e18);

        // As soon as the second slash is executed, the slashable stake goes back up to 50k
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, firstSlashTimestamp + 9,  ""), 25_000e18);
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, firstSlashTimestamp + 10, ""), 50_000e18);

        assertEq(slasher.cumulativeSlashAt(subnetwork, OPERATOR, firstSlashTimestamp + 9,  ""), 25_000e18);
        assertEq(slasher.cumulativeSlashAt(subnetwork, OPERATOR, firstSlashTimestamp + 10, ""), 50_000e18);

        // As soon as the third slash is executed, the slashable stake goes back up to 75k
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, firstSlashTimestamp + 19, ""), 50_000e18);
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, firstSlashTimestamp + 20, ""), 75_000e18);

        assertEq(slasher.cumulativeSlashAt(subnetwork, OPERATOR, firstSlashTimestamp + 19, ""), 50_000e18);
        assertEq(slasher.cumulativeSlashAt(subnetwork, OPERATOR, firstSlashTimestamp + 20, ""), 75_000e18);

        // As soon as the fourth slash is executed, the slashable stake goes back up to 100k
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, firstSlashTimestamp + 29, ""), 75_000e18);
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, firstSlashTimestamp + 30, ""), 100_000e18);

        assertEq(slasher.cumulativeSlashAt(subnetwork, OPERATOR, firstSlashTimestamp + 29, ""), 75_000e18);
        assertEq(slasher.cumulativeSlashAt(subnetwork, OPERATOR, firstSlashTimestamp + 30, ""), 100_000e18);

        // As soon as the fifth slash is executed, the slashable stake stays at 100k
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, firstSlashTimestamp + 39, ""), 100_000e18);
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, firstSlashTimestamp + 40, ""), 100_000e18);

        assertEq(slasher.cumulativeSlashAt(subnetwork, OPERATOR, firstSlashTimestamp + 39, ""), 100_000e18);
        assertEq(slasher.cumulativeSlashAt(subnetwork, OPERATOR, firstSlashTimestamp + 40, ""), 100_000e18);
    }

}
