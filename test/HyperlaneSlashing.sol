// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";
import "forge-std/console.sol";

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
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, depositTimestamp,     ""), 100_000e18);
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp,     ""), 100_000e18);

        vm.prank(HYPERLANE_NETWORK);
        uint256 slashIndex = slasher.requestSlash(subnetwork, OPERATOR, 10_000_000e18, captureTimestamp, "");

        assertEq(slasher.slashRequestsLength(), 1);

        ( ,, uint256 amount,,, bool completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    100_000e18);  // Can't request to slash more than the network limit (requested full 10m)
        assertEq(completed, false);

        // --- Step 3: Fast-forward past veto window and execute the slash

        skip(3 days + 1);

        assertEq(sSpk.activeBalanceOf(alice), 6_000_000e18);
        assertEq(sSpk.activeBalanceOf(bob),   4_000_000e18);
        assertEq(sSpk.totalStake(),           10_000_000e18);
        assertEq(sSpk.activeStake(),          10_000_000e18);

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""), 100_000e18);

        assertEq(spk.balanceOf(address(sSpk)), 10_000_000e18);
        assertEq(spk.balanceOf(BURNER_ROUTER), 0);

        assertEq(slasher.latestSlashedCaptureTimestamp(subnetwork, OPERATOR), 0);
        assertEq(slasher.cumulativeSlash(subnetwork, OPERATOR),               0);

        vm.prank(HYPERLANE_NETWORK);
        slasher.executeSlash(slashIndex, "");

        assertEq(sSpk.activeBalanceOf(alice), 6_000_000e18 - 60_000e18);  // Proportional slash
        assertEq(sSpk.activeBalanceOf(bob),   4_000_000e18 - 40_000e18);  // Proportional slash
        assertEq(sSpk.totalStake(),           9_900_000e18);
        assertEq(sSpk.activeStake(),          9_900_000e18);

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""), 0);

        assertEq(spk.balanceOf(address(sSpk)), 9_900_000e18);
        assertEq(spk.balanceOf(BURNER_ROUTER), 100_000e18);

        assertEq(slasher.latestSlashedCaptureTimestamp(subnetwork, OPERATOR), captureTimestamp);
        assertEq(slasher.cumulativeSlash(subnetwork, OPERATOR),               100_000e18);

        ( ,, amount,,, completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    100_000e18);
        assertEq(completed, true);

        uint256 governanceBalance = spk.balanceOf(SPARK_GOVERNANCE);

        // --- Step 4: Transfer funds from the burner router to Spark Governance
        //         NOTE: This can be called by anyone

        IBurnerRouter(BURNER_ROUTER).triggerTransfer(SPARK_GOVERNANCE);

        assertEq(spk.balanceOf(BURNER_ROUTER),    0);
        assertEq(spk.balanceOf(SPARK_GOVERNANCE), governanceBalance + 100_000e18);

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

        // --- Step 7: Demonstrate time-based slashing behavior

        // Current state: latestSlashedCaptureTimestamp = 1749938602 (the original capture timestamp)
        assertEq(slasher.latestSlashedCaptureTimestamp(subnetwork, OPERATOR), 1749938602);

        // Warp 1 second forward
        skip(1 seconds);

        // You CAN slash from a new capture timestamp that's greater than the latest slashed
        uint48 newCaptureTimestamp = uint48(block.timestamp - 1 seconds);  // This is > 1749938602
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, newCaptureTimestamp, ""), 100_000e18);

        vm.prank(HYPERLANE_NETWORK);
        uint256 newSlashIndex = slasher.requestSlash(subnetwork, OPERATOR, 50_000e18, newCaptureTimestamp, "");

        // Execute this new slash
        skip(3 days + 1);
        vm.prank(HYPERLANE_NETWORK);
        slasher.executeSlash(newSlashIndex, "");

        // Now latestSlashedCaptureTimestamp is updated to the new timestamp
        assertEq(slasher.latestSlashedCaptureTimestamp(subnetwork, OPERATOR), newCaptureTimestamp);

        // You CANNOT slash from the original capture timestamp anymore
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""), 0);

        // You CANNOT slash from the new capture timestamp anymore (it was just slashed)
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, newCaptureTimestamp, ""), 0);

        // But you CAN slash from an even newer capture timestamp
        skip(1 seconds);
        uint48 newerCaptureTimestamp = uint48(block.timestamp - 1 seconds);
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, newerCaptureTimestamp, ""), 100_000e18);
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

        assertEq(amount,    100_000e18);  // Can't request to slash more than the network limit (requested full 10m)
        assertEq(completed, false);

        // --- Step 3: Owner multisig vetos the slash request

        skip(3 days - 1 seconds);  // Demonstrate multisig has a full three days from request to veto

        vm.prank(OWNER_MULTISIG);
        slasher.vetoSlash(slashIndex, "");

        ( ,, amount,,, completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    100_000e18);
        assertEq(completed, true);  // Prevents execution of the slash

        // --- Step 4: Attempt to execute the slashing after veto (should fail)

        skip(1 seconds);  // Fast-forward to the next block to pass the check to show relevant error

        vm.prank(HYPERLANE_NETWORK);
        vm.expectRevert("SlashRequestCompleted()");
        slasher.executeSlash(slashIndex, "");
    }

    function test_continuousSlashingAttack() public {
        // This test demonstrates a critical flaw: a network can slash every second
        // at the full network limit, effectively bypassing the network limit entirely

        // --- Step 1: Setup - Deposit 10m SPK
        deal(address(spk), alice, 10_000_000e18);
        vm.startPrank(alice);
        spk.approve(address(sSpk), 10_000_000e18);
        sSpk.deposit(alice, 10_000_000e18);
        vm.stopPrank();

        uint48 depositTimestamp = uint48(block.timestamp);

        skip(24 hours);

        // --- Step 2: Demonstrate continuous slashing attack
        // Network limit is 100,000 SPK, but we the network can slash this amount every second

        uint256 totalSlashed = 0;
        uint256 slashCount   = 0;
        uint256[] memory slashIndices = new uint256[](100);

        // Request slashes every second for 10 seconds
        for (uint256 i = 0; i < 100; i++) {
            uint48 captureTimestamp = uint48(block.timestamp - 1 seconds);

            // Check that we can still slash the full network limit since nothing has been slashed yet
            uint256 slashableAmount = slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, "");
            assertEq(slashableAmount, 100_000e18, "Should be able to slash full network limit");

            // Request slash
            vm.prank(HYPERLANE_NETWORK);
            slashIndices[i] = slasher.requestSlash(subnetwork, OPERATOR, 10_000e18, captureTimestamp, "");

            // Move forward 1 second for next iteration
            skip(1 seconds);
        }

        // Wait 3 days + 11 seconds to pass all the veto windows
        skip(3 days + 11 seconds);

        // Execute all slashes at once
        for (uint256 i = 0; i < 10; i++) {
            // Get the capture timestamp for this slash request
            (,,, uint48 captureTimestamp,,) = slasher.slashRequests(slashIndices[i]);

            vm.prank(HYPERLANE_NETWORK);
            uint256 slashedAmount = slasher.executeSlash(slashIndices[i], "");

            totalSlashed += slashedAmount;

            assertEq(slasher.latestSlashedCaptureTimestamp(subnetwork, OPERATOR),        captureTimestamp);
            assertEq(slasher.cumulativeSlash(subnetwork, OPERATOR),                      totalSlashed);
            assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""), 100_000e18 - totalSlashed);
        }

        uint48 postSlashTimestamp = uint48(block.timestamp);

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, postSlashTimestamp, ""), 0);

        skip(1 seconds);

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, postSlashTimestamp, ""), 0);
    }

    function test_slashableStakeRechargesWithNewTimestamps() public {
        // This test demonstrates how slashableStake "recharges" by using different capture timestamps
        // for the same underlying stake deposits

        // --- Step 1: Setup - Deposit 10m SPK (this is the stake we'll slash multiple times)
        deal(address(spk), alice, 10_000_000e18);
        vm.startPrank(alice);
        spk.approve(address(sSpk), 10_000_000e18);
        sSpk.deposit(alice, 10_000_000e18);
        vm.stopPrank();

        uint48 depositTimestamp = uint48(block.timestamp);
        skip(24 hours);

        // --- Step 2: First slash at timestamp T1
        uint48 timestampT1 = uint48(block.timestamp - 1 seconds);

        // Check initial slashable stake
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, timestampT1, ""), 100_000e18);

        vm.prank(HYPERLANE_NETWORK);
        uint256 slashIndex1 = slasher.requestSlash(subnetwork, OPERATOR, 50_000e18, timestampT1, "");

        skip(3 days + 1);
        vm.prank(HYPERLANE_NETWORK);
        uint256 slashedAmount1 = slasher.executeSlash(slashIndex1, "");

        assertEq(slashedAmount1, 50_000e18);
        assertEq(slasher.cumulativeSlash(subnetwork, OPERATOR), 50_000e18);
        assertEq(sSpk.activeBalanceOf(alice), 9_950_000e18);

        // --- Step 3: Move forward in time and slash the SAME stake at timestamp T2
        skip(1 hours); // Move forward 1 hour
        uint48 timestampT2 = uint48(block.timestamp - 1 seconds);

        // The slashable stake has "recharged" because we're using a new timestamp!
        uint256 slashableAtT2 = slasher.slashableStake(subnetwork, OPERATOR, timestampT2, "");
        assertGt(slashableAtT2, 0, "Slashable stake should have recharged at new timestamp");

        vm.prank(HYPERLANE_NETWORK);
        uint256 slashIndex2 = slasher.requestSlash(subnetwork, OPERATOR, 30_000e18, timestampT2, "");

        skip(3 days + 1);
        vm.prank(HYPERLANE_NETWORK);
        uint256 slashedAmount2 = slasher.executeSlash(slashIndex2, "");

        assertEq(slashedAmount2, 30_000e18);
        assertEq(slasher.cumulativeSlash(subnetwork, OPERATOR), 80_000e18);
        assertEq(sSpk.activeBalanceOf(alice), 9_920_000e18);

        // --- Step 4: Move forward again and slash the SAME stake at timestamp T3
        skip(1 hours); // Move forward another hour
        uint48 timestampT3 = uint48(block.timestamp - 1 seconds);

        uint256 slashableAtT3 = slasher.slashableStake(subnetwork, OPERATOR, timestampT3, "");
        assertGt(slashableAtT3, 0, "Slashable stake should have recharged at new timestamp");

        vm.prank(HYPERLANE_NETWORK);
        uint256 slashIndex3 = slasher.requestSlash(subnetwork, OPERATOR, 20_000e18, timestampT3, "");

        skip(3 days + 1);
        vm.prank(HYPERLANE_NETWORK);
        uint256 slashedAmount3 = slasher.executeSlash(slashIndex3, "");

        assertEq(slashedAmount3, 20_000e18);
        assertEq(slasher.cumulativeSlash(subnetwork, OPERATOR), 100_000e18);
        assertEq(sSpk.activeBalanceOf(alice), 9_900_000e18);

        // --- Step 5: Demonstrate the key insight
        uint256 totalSlashed = slashedAmount1 + slashedAmount2 + slashedAmount3;
        assertEq(totalSlashed, 100_000e18, "Total slashed should equal 100k");
        assertEq(totalSlashed, 100_000e18, "Should have slashed 100% of network limit");

        // Show that we can't slash from the same timestamp twice
        uint256 slashableAtT1Again = slasher.slashableStake(subnetwork, OPERATOR, timestampT1, "");
        assertEq(slashableAtT1Again, 0, "Should not be able to slash from same timestamp twice");

        // But we can still slash from new timestamps
        skip(1 hours);
        uint48 timestampT4 = uint48(block.timestamp - 1 seconds);
        uint256 slashableAtT4 = slasher.slashableStake(subnetwork, OPERATOR, timestampT4, "");
        assertGt(slashableAtT4, 0, "Should be able to slash from new timestamp");

        // Verify that the same underlying stake was slashed multiple times
        assertEq(sSpk.activeBalanceOf(alice), 9_900_000e18, "Alice's stake should be reduced by total slashed amount");
        assertEq(slasher.cumulativeSlash(subnetwork, OPERATOR), 100_000e18, "Cumulative slash should equal total slashed");
    }

}
