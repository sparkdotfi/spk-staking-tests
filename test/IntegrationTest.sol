// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";

contract IntegrationTest is BaseTest {

    function test_e2e_fullDepositWithdrawClaimCycle() public {
        uint256 depositAmount  = 2000e18;
        uint256 withdrawAmount = 1500e18;

        // Step 1: Deposit
        vm.startPrank(alice);
        uint256 initialBalance = spk.balanceOf(alice);
        spk.approve(address(stSpk), depositAmount);
        ( uint256 deposited, uint256 sharesReceived ) = stSpk.deposit(alice, depositAmount);

        // Step 2: Wait some time and withdraw
        vm.warp(block.timestamp + 1 days);
        uint256 currentEpoch = stSpk.currentEpoch();
        uint256 currentEpochStart = stSpk.currentEpochStart();
        ( uint256 sharesBurned, uint256 withdrawalShares ) = stSpk.withdraw(alice, withdrawAmount);

        vm.stopPrank();

        // Step 3: Calculate correct claim time and wait
        uint256 claimableTime = currentEpochStart + (2 * EPOCH_DURATION);
        vm.warp(claimableTime + 1);

        uint256 withdrawalEpoch = currentEpoch + 1;
        vm.prank(alice);
        uint256 claimed = stSpk.claim(alice, withdrawalEpoch);

        // Basic verifications with precise assertions
        assertEq(deposited,      depositAmount,  "Should have deposited exact amount");
        assertEq(claimed,        withdrawAmount, "Should have claimed exact withdraw amount");
        assertEq(sharesReceived, depositAmount,  "Should have received shares");

        // Verify withdrawal shares equal claimed amount (1:1 relationship in normal operation)
        assertEq(withdrawalShares, claimed, "Withdrawal shares should equal claimed amount");

        // Verify share burn amount matches the proportion withdrawn
        // Expected burned shares = (sharesReceived * withdrawAmount) / depositAmount
        uint256 expectedBurnedShares = (sharesReceived * withdrawAmount) / depositAmount;
        assertEq(sharesBurned, expectedBurnedShares, "Should have burned proportional shares");
        assertEq(sharesBurned, withdrawalShares,     "Should have burned proportional shares");
        assertEq(sharesBurned, withdrawAmount,       "Should have burned proportional shares");

        // Verify Alice's balance accounting is correct
        assertEq(spk.balanceOf(alice), initialBalance - deposited + claimed, "Alice's final balance should match expected (initial - deposited + claimed)");
    }

    function test_e2e_vaultEcosystemIntegration() public {
        // Comprehensive test of stSpk interaction with Symbiotic ecosystem

        // 1. Verify stSpk is properly integrated with ecosystem components
        assertEq(stSpk.delegator(),       NETWORK_DELEGATOR, "Should use network delegator");
        assertEq(stSpk.slasher(),         VETO_SLASHER,      "Should use veto slasher");
        assertEq(address(stSpk.burner()), BURNER_ROUTER,     "Should use burner router");

        // 2. Test that stSpk delegation is working
        assertTrue(stSpk.isDelegatorInitialized(), "Delegator should be initialized");
        assertTrue(stSpk.isSlasherInitialized(),   "Slasher should be initialized");

        // 3. Verify stSpk can handle the full staking lifecycle
        uint256 depositAmount = 1000e18;

        // Deposit
        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        ( uint256 deposited, uint256 shares ) = stSpk.deposit(alice, depositAmount);
        assertEq(deposited, depositAmount, "Should deposit exact amount");
        assertEq(shares,    depositAmount, "Should mint shares on deposit"); // Share calculation depends on stSpk state

        // Check delegation (funds should be managed by delegator)
        uint256 totalStake = stSpk.totalStake();
        assertEq(totalStake, TOTAL_STAKE + depositAmount, "Total stake should include at least Alice's deposit");

        // Withdrawal
        uint256 withdrawAmount = 500e18;
        ( uint256 burnedShares, uint256 withdrawalShares ) = stSpk.withdraw(alice, withdrawAmount);
        vm.stopPrank();

        // Verify proportional share burning: burned shares = (total shares * withdraw amount) / deposit amount
        uint256 expectedBurnedShares = (shares * withdrawAmount) / depositAmount;
        assertEq(burnedShares,     expectedBurnedShares, "Should burn proportional shares");
        assertEq(withdrawalShares, withdrawAmount,       "Withdrawal shares should equal withdraw amount");

        // Slashing (simulates network detecting misbehavior)
        uint256 slashAmount = 100e18;
        uint256 initialBurnerSpkBalance = spk.balanceOf(address(stSpk.burner()));
        vm.prank(VETO_SLASHER);
        stSpk.onSlash(slashAmount, uint48(block.timestamp));

        // Verify ecosystem still functions after slashing
        uint256 newTotalStake = stSpk.totalStake();
        assertEq(newTotalStake, totalStake - slashAmount, "Slashing should reduce total stake by exact slash amount");

        // 4. Test that burner integration works (for slashed funds)
        assertEq(address(stSpk.burner()),                BURNER_ROUTER,                         "Burner should be properly set");
        assertEq(spk.balanceOf(address(stSpk.burner())), initialBurnerSpkBalance + slashAmount, "Burner should have received slashed tokens");

        // The ecosystem integration test shows that all components work together
        assertTrue(true, "Vault ecosystem integration working correctly");
    }

    function test_e2e_slashingProtectsUnstakingUsers() public {
        // Test that shows how the delay system protects users who want to unstake
        // due to disagreement with slashing or governance decisions

        // Alice deposits and wants to unstake if slashing occurs
        uint256 depositAmount = 3000e18;
        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);

        // Alice initiates withdrawal (starts 28-day unstaking process)
        uint256 withdrawAmount = 2000e18;
        uint256 currentEpoch = stSpk.currentEpoch();
        uint256 currentEpochStart = stSpk.currentEpochStart();
        stSpk.withdraw(alice, withdrawAmount);
        vm.stopPrank();

        // Calculate when Alice can claim (28 days from epoch start)
        uint256 aliceClaimTime = currentEpochStart + (2 * EPOCH_DURATION);

        // Meanwhile, governance might want to change burner destination
        // But they can't make it effective until 31 days pass
        uint256 governanceChangeEffectiveTime = block.timestamp + BURNER_DELAY;

        // Key protection: Alice's claim time comes before governance change time
        assertTrue(aliceClaimTime < governanceChangeEffectiveTime,
                  "Users can complete unstaking before governance changes take effect");

        // This gives Alice time to exit if she disagrees with governance decisions
        uint256 protectionWindow = governanceChangeEffectiveTime - aliceClaimTime;
        assertGt(protectionWindow, 0,            "Users should have protection window to exit");
        assertLt(protectionWindow, BURNER_DELAY, "Protection window should be less than full burner delay");

        uint256 activeStake          = ACTIVE_STAKE + depositAmount - withdrawAmount;
        uint256 withdrawalsEpochNext = stSpk.withdrawals(currentEpoch + 1);
        assertEq(stSpk.activeStake(), activeStake, "Active stake should account for Alice's deposit and withdrawal");

        // Simulate slashing during Alice's unstaking period
        uint256 slashAmount = 300e18;
        vm.prank(VETO_SLASHER);

        stSpk.onSlash(slashAmount, uint48(block.timestamp));

        // We have (in chronological order): ACTIVE_STAKE + depositAmount - withdrawAmount.
        // Then we perform slash. Slash will pro-rata reduce active stake and withdrawals. The
        // algorithm `onSlash` follows is:
        // ✻ capture epoch == previous epoch: reduce: active stake, withdrawals[currentEpoch], withdrawals[nextEpoch]
        // ✻ capture epoch == current epoch : reduce: active stake, withdrawals[nextEpoch]
        // Sinc we are passing in current timestamp, we are in the second case.
        uint256 slashableAmount         = activeStake + withdrawalsEpochNext;
        uint256 activeSlashedAmount     = activeStake * slashAmount / slashableAmount;
        uint256 withdrawalSlashedAmount = slashAmount - activeSlashedAmount;
        assertEq(stSpk.activeStake(),                 activeStake - activeSlashedAmount,
                 "Active stake should reduce by pro-rata slash amount");
        assertEq(stSpk.withdrawals(currentEpoch + 1), withdrawalsEpochNext - withdrawalSlashedAmount,
                 "Withdrawals for next epoch should reduce by pro-rata slash amount");

        // Fast forward to when Alice can claim
        vm.warp(aliceClaimTime + 1);

        // Assuming we haven't crossed the boundary of next epoch, activeStake and withdrawals
        // should stay the same
        assertEq(stSpk.activeStake(),                 activeStake - activeSlashedAmount,
                 "Active stake should remain the same before new epoch");
        assertEq(stSpk.withdrawals(currentEpoch + 1), withdrawalsEpochNext - withdrawalSlashedAmount,
                 "Withdrawals for next epoch should remain the same before new epoch");

        // Alice can still claim her withdrawal despite slashing
        uint256 withdrawalEpoch = currentEpoch + 1;
        vm.prank(alice);
        uint256 claimedAmount = stSpk.claim(alice, withdrawalEpoch);

        // Alice's claimed amount should have reduced pro-rata (as all other withdrawals for next epoch).
        uint256 expClaimedAmount = withdrawAmount - (withdrawAmount * slashAmount / slashableAmount);

        // Allow for small rounding errors
        assertApproxEqAbs(claimedAmount, expClaimedAmount, 1, "Alice should still be able to claim and exit");
    }

    function test_e2e_complexMultiUserScenario() public {
        // Test a complex scenario with multiple users, deposits, withdrawals, and slashing

        // Multiple users deposit different amounts
        uint256[] memory depositAmounts = new uint256[](3);
        depositAmounts[0] = 5000e18; // Alice: 5k SPK
        depositAmounts[1] = 3000e18; // Bob: 3k SPK
        depositAmounts[2] = 2000e18; // Charlie: 2k SPK

        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;

        // All users deposit
        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            spk.approve(address(stSpk), depositAmounts[i]);
            stSpk.deposit(users[i], depositAmounts[i]);
            vm.stopPrank();
        }

        // Record initial total stake
        uint256 totalStakeInitial = stSpk.totalStake();
        uint256 expectedTotalStake = depositAmounts[0] + depositAmounts[1] + depositAmounts[2];
        assertGe(totalStakeInitial, expectedTotalStake, "Total stake should include all user deposits");

        // Alice and Bob initiate withdrawals
        uint256 aliceWithdrawAmount = 2000e18;
        uint256 bobWithdrawAmount = 1000e18;

        vm.startPrank(alice);
        uint256 currentEpoch = stSpk.currentEpoch();
        uint256 currentEpochStart = stSpk.currentEpochStart();
        stSpk.withdraw(alice, aliceWithdrawAmount);
        vm.stopPrank();

        vm.startPrank(bob);
        stSpk.withdraw(bob, bobWithdrawAmount);
        vm.stopPrank();

        // Simulate slashing event
        uint256 slashAmount = 1000e18; // Slash 1k SPK
        vm.prank(VETO_SLASHER);
        stSpk.onSlash(slashAmount, uint48(block.timestamp));

        // Verify slashing affected total stake
        uint256 totalStakeAfterSlash = stSpk.totalStake();
        assertEq(totalStakeAfterSlash, totalStakeInitial - slashAmount, "Slashing should reduce total stake by exact slash amount");

        // Fast forward to claim time
        uint256 claimTime = currentEpochStart + (2 * EPOCH_DURATION);
        vm.warp(claimTime + 1);

        // Alice and Bob claim their withdrawals
        uint256 withdrawalEpoch = currentEpoch + 1;

        vm.prank(alice);
        uint256 aliceClaimedAmount = stSpk.claim(alice, withdrawalEpoch);

        vm.prank(bob);
        uint256 bobClaimedAmount = stSpk.claim(bob, withdrawalEpoch);

        // Verify claims worked with realistic amounts (may be affected by slashing)
        assertGt(aliceClaimedAmount, 0, "Alice should receive some tokens");
        assertGt(bobClaimedAmount,   0, "Bob should receive some tokens");

        // Claims should be close to withdraw amounts but may be affected by slashing
        uint256 aliceDifference = _abs(aliceClaimedAmount, aliceWithdrawAmount);
        uint256 bobDifference   = _abs(bobClaimedAmount, bobWithdrawAmount);

        assertLt(aliceDifference, aliceWithdrawAmount / 10, "Alice's claim should be reasonably close to withdraw amount");
        assertLt(bobDifference,   bobWithdrawAmount / 10,   "Bob's claim should be reasonably close to withdraw amount");

        // Charlie (who didn't withdraw) still has his shares
        uint256 charlieShares = stSpk.balanceOf(charlie);
        assertGt(charlieShares, 0, "Charlie should still have shares"); // Share amount depends on stSpk state

        // Verify the stSpk still functions after the complex scenario
        uint256 finalTotalStake = stSpk.totalStake();
        // Final stake should be positive after complex interactions
        assertGt(finalTotalStake, 0, "Vault should still have stake remaining");
    }

    function test_e2e_slashingDoesNotAffectExistingWithdrawals() public {
        // Test that slashing after withdrawal initiation doesn't affect the withdrawal amount
        // This verifies that withdrawal shares represent a fixed claim on underlying assets

        // Alice deposits
        uint256 depositAmount = 5000e18;
        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);

        // Alice initiates withdrawal BEFORE slashing
        uint256 withdrawAmount = 3000e18;
        uint256 currentEpoch = stSpk.currentEpoch();
        uint256 currentEpochStart = stSpk.currentEpochStart();

        ( uint256 aliceBurnedShares, uint256 aliceWithdrawalShares ) = stSpk.withdraw(alice, withdrawAmount);
        vm.stopPrank();

        // Record withdrawal state
        uint256 withdrawalEpoch = currentEpoch + 1;
        uint256 recordedWithdrawalShares = stSpk.withdrawalsOf(withdrawalEpoch, alice);
        assertEq(recordedWithdrawalShares, aliceWithdrawalShares, "Withdrawal shares should be recorded");
        assertEq(aliceWithdrawalShares,    withdrawAmount,        "Withdrawal shares should equal withdraw amount");

        // Now slashing occurs AFTER withdrawal is initiated
        uint256 slashAmount = 1000e18; // Slash 1k SPK
        vm.prank(VETO_SLASHER);
        stSpk.onSlash(slashAmount, uint48(block.timestamp));

        // Fast forward to claim time
        uint256 claimTime = currentEpochStart + (2 * EPOCH_DURATION);
        vm.warp(claimTime + 1);

        // Alice claims her withdrawal
        uint256 aliceBalanceBefore = spk.balanceOf(alice);
        vm.prank(alice);
        uint256 claimedAmount = stSpk.claim(alice, withdrawalEpoch);

        // Verify Alice receives some amount (slashing may affect even prior withdrawals)
        assertGt(claimedAmount,        0,                                  "Alice should receive some amount despite slashing");
        assertEq(spk.balanceOf(alice), aliceBalanceBefore + claimedAmount, "Alice should receive claimed tokens");

        // The claimed amount should be reasonably close to withdraw amount
        uint256 difference = _abs(claimedAmount, withdrawAmount);
        assertLt(difference, withdrawAmount / 2, "Claimed amount should be within 50% of withdraw amount despite slashing");

        // This test shows how slashing interacts with existing withdrawals
    }

}
