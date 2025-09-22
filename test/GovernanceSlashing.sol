// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";

interface INetworkDelegator is IAccessControl {}

contract GovernanceSlashingTest is BaseTest {

    address MIDDLEWARE = makeAddr("middleware");

    function test_slashingIsDisabledUnlessMiddlewareIsSet() public {
        // --- Step 1: Deposit 10m SPK to stSPK as two users

        deal(address(spk), alice, 6_000_000e18);
        deal(address(spk), bob,   4_000_000e18);

        vm.startPrank(alice);
        spk.approve(address(stSpk), 6_000_000e18);
        stSpk.deposit(alice, 6_000_000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        spk.approve(address(stSpk), 4_000_000e18);
        stSpk.deposit(bob, 4_000_000e18);
        vm.stopPrank();

        uint48 depositTimestamp = uint48(block.timestamp);

        skip(24 hours);  // Warp 24 hours

        // --- Step 2: Request a slash of all staked SPK (show that network limit is hit)

        uint48 captureTimestamp = uint48(block.timestamp - 1 seconds);  // Can't capture current timestamp and above

        // Demonstrate that the slashable stake increases with new deposits
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, depositTimestamp - 1, ""), 0);
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, depositTimestamp,     ""), ACTIVE_STAKE + 10_000_000e18);
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp,     ""), ACTIVE_STAKE + 10_000_000e18);

        // There is no middleware, so slashing is impossible
        assertEq(middlewareService.middleware(NETWORK), address(0));

        vm.prank(NETWORK);
        vm.expectRevert("NotNetworkMiddleware()");
        slasher.requestSlash(subnetwork, OPERATOR, 10_000_000e18, captureTimestamp, "");

        // Show how it would work if middleware was set
        vm.prank(NETWORK);
        middlewareService.setMiddleware(MIDDLEWARE);

        // Its now possible
        assertEq(middlewareService.middleware(NETWORK), MIDDLEWARE);

        vm.prank(MIDDLEWARE);
        uint256 slashIndex = slasher.requestSlash(subnetwork, OPERATOR, 10_000_000e18, captureTimestamp, "");

        skip(3 days + 1);

        vm.prank(MIDDLEWARE);
        slasher.executeSlash(slashIndex, "");
    }

    function test_governanceCanSlashUpToActiveStake_withMiddlewareConfigured() public {
        // Show how it would work if middleware was set
        vm.prank(NETWORK);
        middlewareService.setMiddleware(MIDDLEWARE);

        uint256 SPK_BALANCE = spk.balanceOf(address(stSpk));

        // --- Step 1: Deposit 10m SPK to stSPK as two users

        deal(address(spk), alice, 6_000_000e18);
        deal(address(spk), bob,   4_000_000e18);

        vm.startPrank(alice);
        spk.approve(address(stSpk), 6_000_000e18);
        stSpk.deposit(alice, 6_000_000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        spk.approve(address(stSpk), 4_000_000e18);
        stSpk.deposit(bob, 4_000_000e18);
        vm.stopPrank();

        uint48 depositTimestamp = uint48(block.timestamp);

        skip(24 hours);  // Warp 24 hours

        // --- Step 2: Request a slash of all staked SPK (show that network limit is hit)

        uint48 captureTimestamp = uint48(block.timestamp - 1 seconds);  // Can't capture current timestamp and above

        uint256 slashAmount    = 100_000_000_000e18;  // Slash above active stake to show that only staked funds can be slashed
        uint256 slashableStake = ACTIVE_STAKE + 10_000_000e18;  // Includes new deposits

        // Demonstrate that the slashable stake increases with new deposits (these are the first deposits made after new config setup)
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, depositTimestamp - 1, ""), 0);
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, depositTimestamp,     ""), slashableStake);  // Entire stake is slashable
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp,     ""), slashableStake);

        vm.prank(MIDDLEWARE);
        uint256 slashIndex = slasher.requestSlash(subnetwork, OPERATOR, slashAmount, captureTimestamp, "");

        assertEq(slasher.slashRequestsLength(), 1);

        ( ,, uint256 amount,,, bool completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    slashableStake);  // Can't request to slash more than the active stake
        assertEq(completed, false);

        // --- Step 3: Fast-forward past veto window and execute the slash

        skip(3 days + 1);

        // Overwrite totalStake because of epochs possibly changing from warp
        TOTAL_STAKE = stSpk.totalStake();

        assertEq(stSpk.activeBalanceOf(alice), 6_000_000e18);
        assertEq(stSpk.activeBalanceOf(bob),   4_000_000e18);
        assertEq(stSpk.totalStake(),           TOTAL_STAKE);  // 10m captured in above query

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""), slashableStake);

        assertEq(spk.balanceOf(address(stSpk)), SPK_BALANCE + 10_000_000e18);
        assertEq(spk.balanceOf(BURNER_ROUTER),  0);

        assertEq(slasher.latestSlashedCaptureTimestamp(subnetwork, OPERATOR), 0);
        assertEq(slasher.cumulativeSlash(subnetwork, OPERATOR),               0);

        assertEq(delegator.operatorNetworkShares(subnetwork, OPERATOR), 1e18);

        vm.prank(MIDDLEWARE);
        slasher.executeSlash(slashIndex, "");

        assertEq(delegator.operatorNetworkShares(subnetwork, OPERATOR), 0);

        // Show that active stake is reduced proportionally with withdrawals
        assertApproxEqAbs(
            stSpk.activeStake(),
            slashableStake - slashableStake * stSpk.activeStake() / stSpk.totalStake(),
            10
        );

        // Show that active balance is reduced proportionally with withdrawals
        assertEq(stSpk.activeBalanceOf(alice), 6_000_000e18 * stSpk.activeStake() / stSpk.activeShares());
        assertEq(stSpk.activeBalanceOf(bob),   4_000_000e18 * stSpk.activeStake() / stSpk.activeShares());

        assertEq(stSpk.activeBalanceOf(alice), 529_471.960385890527024221e18);
        assertEq(stSpk.activeBalanceOf(bob),   352_981.306923927018016147e18);

        assertEq(stSpk.totalStake(), TOTAL_STAKE - slashableStake);

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""), 0);

        assertEq(spk.balanceOf(address(stSpk)), SPK_BALANCE + 10_000_000e18 - slashableStake);
        assertEq(spk.balanceOf(BURNER_ROUTER),  slashableStake);

        assertEq(slasher.latestSlashedCaptureTimestamp(subnetwork, OPERATOR), captureTimestamp);
        assertEq(slasher.cumulativeSlash(subnetwork, OPERATOR),               slashableStake);

        ( ,, amount,,, completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    slashableStake);
        assertEq(completed, true);

        uint256 governanceBalance = spk.balanceOf(SPARK_GOVERNANCE);

        // --- Step 4: Transfer funds from the burner router to Spark Governance
        //         NOTE: This can be called by anyone

        IBurnerRouter(BURNER_ROUTER).triggerTransfer(SPARK_GOVERNANCE);

        assertEq(spk.balanceOf(BURNER_ROUTER),    0);
        assertEq(spk.balanceOf(SPARK_GOVERNANCE), governanceBalance + slashableStake);

        // --- Step 5: Show that slasher cannot slash anymore with the same request

        // Can't execute the same slash again
        vm.prank(MIDDLEWARE);
        vm.expectRevert("InsufficientSlash()");
        slasher.executeSlash(slashIndex, "");

        // --- Step 6: Show that slasher also cannot request new slashes because the network limit has been hit

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""), 0);

        // Try to slash from the same capture timestamp that was already slashed
        vm.prank(MIDDLEWARE);
        vm.expectRevert("InsufficientSlash()");
        slashIndex = slasher.requestSlash(subnetwork, OPERATOR, 100e18, captureTimestamp, "");  // Use the same capture timestamp

        // --- Step 7: Demonstrate that the slashable stake never increases again

        skip(100 days);

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, uint48(block.timestamp - 1), ""), 0);

        // Try to slash from a new capture timestamp that is long after the last slash was completed
        vm.prank(MIDDLEWARE);
        vm.expectRevert("InsufficientSlash()");
        slasher.requestSlash(subnetwork, OPERATOR, 100e18, uint48(block.timestamp - 1), "");  // Use the same capture timestamp
    }

    function test_ownerMultisigCanVetoSlash_withMiddlewareConfigured() public {
        // Show how it would work if middleware was set
        vm.prank(NETWORK);
        middlewareService.setMiddleware(MIDDLEWARE);

        // --- Step 1: Deposit 10m SPK to stSPK as two users

        deal(address(spk), alice, 6_000_000e18);
        deal(address(spk), bob,   4_000_000e18);

        vm.startPrank(alice);
        spk.approve(address(stSpk), 6_000_000e18);
        stSpk.deposit(alice, 6_000_000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        spk.approve(address(stSpk), 4_000_000e18);
        stSpk.deposit(bob, 4_000_000e18);
        vm.stopPrank();

        skip(24 hours);  // Warp 24 hours

        // --- Step 2: Request a slash of 10% of staked SPK (500)

        uint48 captureTimestamp = uint48(block.timestamp - 1 hours);

        vm.prank(MIDDLEWARE);
        uint256 slashIndex = slasher.requestSlash(subnetwork, OPERATOR, 10_000_000e18, captureTimestamp, "");

        assertEq(slasher.slashRequestsLength(), 1);

        ( ,, uint256 amount,,, bool completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    10_000_000e18);  // Can't request to slash more than the network limit (requested full 10m)
        assertEq(completed, false);

        // --- Step 3: Owner multisig vetos the slash request

        skip(3 days - 1 seconds);  // Demonstrate multisig has a full three days from request to veto

        vm.prank(SPARK_GOVERNANCE);
        slasher.vetoSlash(slashIndex, "");

        ( ,, amount,,, completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    10_000_000e18);
        assertEq(completed, true);  // Prevents execution of the slash

        // --- Step 4: Attempt to execute the slashing after veto (should fail)

        skip(1 seconds);  // Fast-forward to the next block to pass the check to show relevant error

        vm.prank(MIDDLEWARE);
        vm.expectRevert("SlashRequestCompleted()");
        slasher.executeSlash(slashIndex, "");
    }

}
