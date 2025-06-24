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

}
