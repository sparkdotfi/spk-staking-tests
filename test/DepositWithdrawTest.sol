// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";

contract TestDepositFailureTests is BaseTest {

    function test_deposit_insufficientBalanceBoundary() public {
        uint256 aliceBalance  = spk.balanceOf(alice);
        uint256 depositAmount = aliceBalance + 1; // More than Alice has
        uint256 totalSupply   = stSpk.totalSupply();

        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);

        vm.expectRevert("SDAO/insufficient-balance");
        stSpk.deposit(alice, depositAmount);

        stSpk.deposit(alice, aliceBalance);

        assertEq(spk.balanceOf(alice),   0,                          "SPK not transferred");
        assertEq(stSpk.balanceOf(alice), aliceBalance,               "stSpk not minted");
        assertEq(stSpk.totalSupply(),    totalSupply + aliceBalance, "Total supply not updated");  // 1:1 rate

        vm.stopPrank();
    }

    function test_deposit_invalidOnBehalfOf() public {
        vm.startPrank(alice);
        spk.approve(address(stSpk), 1000e18);
        vm.expectRevert("InvalidOnBehalfOf()");
        stSpk.deposit(address(0), 1000e18);
        vm.stopPrank();
    }

    function test_deposit_notWhitelistedDepositor() public {
        // Enable whitelist
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setDepositWhitelist(true);

        uint256 depositAmount = 100e18;

        // Bob (not whitelisted) should be blocked
        vm.startPrank(bob);
        spk.approve(address(stSpk), depositAmount);
        vm.expectRevert("NotWhitelistedDepositor()");
        stSpk.deposit(bob, depositAmount);
        vm.stopPrank();
    }

    function test_deposit_zeroAmount() public {
        vm.startPrank(alice);
        spk.approve(address(stSpk), 0);
        vm.expectRevert("InsufficientDeposit()");
        stSpk.deposit(alice, 0);
        vm.stopPrank();
    }

    function test_deposit_depositLimitReached() public {
        uint256 depositLimit = stSpk.activeStake() + 1000e18; // 1k SPK over the current active stake

        // Set up deposit limit
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setIsDepositLimit(true);

        vm.prank(SPARK_GOVERNANCE);
        stSpk.setDepositLimit(depositLimit);

        // Alice deposits up to the limit
        vm.startPrank(alice);
        spk.approve(address(stSpk), 1000e18);
        stSpk.deposit(alice, 1000e18);
        vm.stopPrank();

        // Alice tries to deposit 1 wei more (should fail)
        vm.startPrank(alice);
        spk.approve(address(stSpk), 1);
        vm.expectRevert("DepositLimitReached()");
        stSpk.deposit(alice, 1);
        vm.stopPrank();
    }

}

contract TestDepositSuccessTests is BaseTest {

     function test_userDeposit() public {
        uint256 depositAmount = 1000e18; // 1000 SPK

        vm.startPrank(alice);

        // Check initial balances
        uint256 initialSPKBalance   = spk.balanceOf(alice);
        uint256 initialstSpkBalance = stSpk.balanceOf(alice);
        uint256 initialTotalSupply  = stSpk.totalSupply();

        // Approve and deposit
        spk.approve(address(stSpk), depositAmount);
        ( uint256 depositedAmount, uint256 mintedShares ) = stSpk.deposit(alice, depositAmount);

        vm.stopPrank();

        // Verify deposit results
        assertEq(depositedAmount, depositAmount, "Incorrect deposited amount");
        assertEq(mintedShares,    depositAmount, "No shares minted");

        // Check balances after deposit
        assertEq(spk.balanceOf(alice),   initialSPKBalance  - depositAmount, "SPK not transferred");
        assertEq(stSpk.balanceOf(alice), initialstSpkBalance + mintedShares, "stSpk not minted");
        assertEq(stSpk.totalSupply(),    initialTotalSupply + mintedShares,  "Total supply not updated");

        assertEq(spk.balanceOf(address(stSpk)), TOTAL_STAKE + depositAmount, "SPK not transferred to vault");
    }

    function test_multipleUserDeposits() public {
        uint256 depositAmount = 500e18; // 500 SPK each

        // Alice deposits
        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        ( uint256 depositAmount1, uint256 aliceShares ) = stSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        spk.approve(address(stSpk), depositAmount);
        ( uint256 depositAmount2, uint256 bobShares ) = stSpk.deposit(bob, depositAmount);
        vm.stopPrank();

        // Verify both deposits
        assertEq(depositAmount1,         depositAmount, "Alice deposit amount incorrect");
        assertEq(depositAmount2,         depositAmount, "Bob deposit amount incorrect");
        assertEq(stSpk.balanceOf(alice), aliceShares,   "Alice shares incorrect");
        assertEq(stSpk.balanceOf(bob),   bobShares,     "Bob shares incorrect");

        assertEq(spk.balanceOf(address(stSpk)), TOTAL_STAKE + depositAmount1 + depositAmount2, "SPK not transferred to vault");
    }

    function test_deposit_VaultStakeAndSlashableBalance() public {
        // Test stake-related functions
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        // Check total stake
        uint256 totalStake = stSpk.totalStake();

        assertEq(totalStake, TOTAL_STAKE + depositAmount, "Invalid total stake");

        // Check slashable balance
        uint256 slashableBalance = stSpk.slashableBalanceOf(alice);

        assertEq(slashableBalance,              depositAmount,               "Invalid slashable balance for Alice");
        assertEq(spk.balanceOf(address(stSpk)), TOTAL_STAKE + depositAmount, "SPK not transferred to vault");
    }

}

contract TestWithdrawFailureTests is BaseTest {

    function test_withdraw_invalidClaimer() public {
        vm.expectRevert("InvalidClaimer()");
        stSpk.withdraw(address(0), 1e18);
    }

    function test_withdraw_zeroAmount() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);

        vm.expectRevert("InsufficientWithdrawal()");
        stSpk.withdraw(alice, 0);
        vm.stopPrank();
    }

    function test_withdraw_tooMuchWithdrawBoundary() public {
        // First deposit
        uint256 depositAmount = 1000e18;
        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);

        // Revert if withdrawal amount is greater than balance
        vm.expectRevert("TooMuchWithdraw()");
        stSpk.withdraw(alice, depositAmount + 1);
    }

}

contract TestWithdrawSuccessTests is BaseTest {

    function test_withdraw() public {
        // First deposit
        uint256 depositAmount = 1000e18;
        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);

        // Record initial state
        uint256 initialShares = stSpk.balanceOf(alice);
        uint256 withdrawAmount = 500e18; // Withdraw half

        // Initiate withdrawal
        ( uint256 burnedShares, uint256 mintedWithdrawalShares ) = stSpk.withdraw(alice, withdrawAmount);

        vm.stopPrank();

        // Verify withdrawal initiation
        assertEq(burnedShares,           withdrawAmount, "No shares burned");
        assertEq(mintedWithdrawalShares, withdrawAmount, "No withdrawal shares minted");

        assertEq(stSpk.balanceOf(alice), initialShares - burnedShares, "Active shares not burned");

        // Check withdrawal shares
        uint256 currentEpoch     = stSpk.currentEpoch();
        uint256 withdrawalShares = stSpk.withdrawalsOf(currentEpoch + 1, alice);

        assertEq(withdrawalShares,              mintedWithdrawalShares,      "Withdrawal shares mismatch");
        assertEq(spk.balanceOf(address(stSpk)), TOTAL_STAKE + depositAmount, "SPK not transferred to vault");
    }

}

contract TestClaimFailureTests is BaseTest {

    function test_claim_invalidRecipient() public {
        vm.expectRevert("InvalidRecipient()");
        vm.prank(alice);
        stSpk.claim(address(0), 1);
    }

    function test_claim_beforeEpochDelayBoundary() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);

        uint256 currentEpoch = stSpk.currentEpoch();
        stSpk.withdraw(alice, 500e18);

        // Try to claim immediately (should fail)
        vm.expectRevert("InvalidEpoch()");
        stSpk.claim(alice, currentEpoch + 1);

        vm.stopPrank();
    }

    function test_claim_insufficientClaim() public {
        _initializeEpochSystem();

        // Setup: Deposit and withdraw
        uint256 depositAmount  = 2000e18;
        uint256 withdrawAmount = 1000e18;

        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);

        uint256 currentEpoch      = stSpk.currentEpoch();
        uint256 currentEpochStart = stSpk.currentEpochStart();

        stSpk.withdraw(alice, withdrawAmount);
        vm.stopPrank();

        // Calculate when we can claim: current epoch start + 2 full epochs
        // This ensures we wait until after the next epoch ends
        uint256 claimableTime = currentEpochStart + (2 * EPOCH_DURATION);

        // Fast forward to when withdrawal becomes claimable
        vm.warp(claimableTime + 1); // +1 to be sure we're past the boundary

        // Claim withdrawal
        vm.prank(alice);
        stSpk.claim(alice, currentEpoch + 1);

        // Claim again should revert
        vm.expectRevert("InsufficientClaim()");
        stSpk.claim(alice, currentEpoch + 1);
    }

}

contract TestClaimSuccessTests is BaseTest {

    function test_claim() public {
        _initializeEpochSystem();

        // Setup: Deposit and withdraw
        uint256 depositAmount  = 2000e18;
        uint256 withdrawAmount = 1000e18;

        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);

        uint256 currentEpoch      = stSpk.currentEpoch();
        uint256 currentEpochStart = stSpk.currentEpochStart();

        stSpk.withdraw(alice, withdrawAmount);
        vm.stopPrank();

        // Calculate when we can claim: current epoch start + 2 full epochs
        // This ensures we wait until after the next epoch ends
        uint256 claimableTime = currentEpochStart + (2 * EPOCH_DURATION);

        // Fast forward to when withdrawal becomes claimable
        vm.warp(claimableTime + 1); // +1 to be sure we're past the boundary

        uint256 aliceBalanceBefore = spk.balanceOf(alice);

        // Claim withdrawal
        vm.prank(alice);
        uint256 claimedAmount = stSpk.claim(alice, currentEpoch + 1);

        assertEq(claimedAmount,                 withdrawAmount,                                      "Invalid claimed amount");
        assertEq(spk.balanceOf(alice),          aliceBalanceBefore + claimedAmount,                  "SPK not received");
        assertEq(stSpk.balanceOf(alice),        depositAmount - withdrawAmount,                      "Active shares not burned");
        assertEq(spk.balanceOf(address(stSpk)), TOTAL_STAKE + depositAmount - withdrawAmount + 1e18, "SPK not transferred to vault");
    }

}

// NOTE: All failure modes of _claim are captured in the above claim tests.
contract TestClaimBatchFailureTests is BaseTest {

    function test_claimBatch_invalidRecipient() public {
        _initializeEpochSystem();

        uint256[] memory epochs = new uint256[](1);
        epochs[0] = 1;

        vm.expectRevert("InvalidRecipient()");
        vm.prank(alice);
        stSpk.claimBatch(address(0), epochs);
    }

    function test_claimBatch_emptyEpochs() public {
        uint256[] memory epochs = new uint256[](0);

        vm.expectRevert("InvalidLengthEpochs()");
        vm.prank(alice);
        stSpk.claimBatch(alice, epochs);
    }

}

contract TestClaimBatchSuccessTests is BaseTest {

    function test_claimBatch() public {
        // Step 0: Initialize epoch system with a deposit
        _initializeEpochSystem();

        // Provide more realistic scenario where a user withdraws mid-epoch
        skip(1 days);

        // Setup multiple withdrawals across different epochs
        uint256 depositAmount  = 3000e18;
        uint256 withdrawAmount = 500e18;

        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);

        uint256[] memory withdrawalEpochs = new uint256[](3);
        uint256 firstEpochStart = stSpk.currentEpochStart();

        // Make withdrawals in different epochs
        for (uint256 i = 0; i < 3; i++) {
            uint256 currentEpoch = stSpk.currentEpoch();
            withdrawalEpochs[i] = currentEpoch + 1;

            stSpk.withdraw(alice, withdrawAmount);

            // Advance to next epoch
            vm.warp(block.timestamp + EPOCH_DURATION);
        }

        vm.stopPrank();

        // Calculate when the first withdrawal becomes claimable
        // First withdrawal needs: firstEpochStart + 2 * EPOCH_DURATION
        uint256 firstClaimableTime = firstEpochStart + (2 * EPOCH_DURATION);

        // Since we made 3 withdrawals across 3 epochs, the last one needs more time
        // Wait until all withdrawals are claimable (first one + 2 more epochs)
        uint256 allClaimableTime = firstClaimableTime + (2 * EPOCH_DURATION);

        vm.warp(allClaimableTime - 1);
        vm.expectRevert("InvalidEpoch()");
        vm.prank(alice);
        stSpk.claimBatch(alice, withdrawalEpochs);

        vm.warp(allClaimableTime);

        // Batch claim
        uint256 aliceBalanceBefore = spk.balanceOf(alice);
        vm.prank(alice);
        uint256 totalClaimed = stSpk.claimBatch(alice, withdrawalEpochs);

        // Verify batch claim
        assertEq(totalClaimed,                  1500e18,                                           "Nothing claimed in batch");
        assertEq(spk.balanceOf(alice),          aliceBalanceBefore + totalClaimed,                 "SPK not received from batch claim");
        assertEq(spk.balanceOf(address(stSpk)), TOTAL_STAKE + depositAmount - totalClaimed + 1e18, "SPK not transferred to vault");
    }

}

contract TestRedeemFailureTests is BaseTest {

    function test_redeem_moreThanBalanceBoundary() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        ( , uint256 mintedShares ) = stSpk.deposit(alice, depositAmount);

        // Try to redeem more shares than owned
        uint256 excessShares = mintedShares + 1;
        vm.expectRevert("TooMuchRedeem()");
        stSpk.redeem(alice, excessShares);

        vm.stopPrank();
    }

    function test_redeem_zeroShares() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);

        vm.expectRevert("InsufficientRedemption()");
        stSpk.redeem(alice, 0);
        vm.stopPrank();
    }

}

contract TestRedeemSuccessTests is BaseTest {

    function test_redeem() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        ( , uint256 mintedShares ) = stSpk.deposit(alice, depositAmount);

        // Redeem half the shares
        uint256 currentEpoch        = stSpk.currentEpoch();
        uint256 initialActiveShares = stSpk.balanceOf(alice);
        uint256 redeemShares        = mintedShares / 2;

        // Calculate expected assets based on current share price
        uint256 activeStake    = stSpk.activeStake();   // NOTE: NOT the same as totalStake()
        uint256 activeShares   = stSpk.activeShares();  // NOTE: NOT the same as totalSupply()
        uint256 expectedAssets = redeemShares * activeStake / activeShares;

        ( uint256 withdrawnAssets, uint256 redeemWithdrawalShares ) = stSpk.redeem(alice, redeemShares);

        vm.stopPrank();

        // Verify redeem results with proper mathematical validation
        assertEq(withdrawnAssets,        expectedAssets, "No assets withdrawn");
        assertEq(redeemWithdrawalShares, redeemShares,   "No withdrawal shares minted");

        // Verify active shares were burned correctly
        assertEq(stSpk.balanceOf(alice),        initialActiveShares - redeemShares, "Active shares not burned correctly");
        assertEq(spk.balanceOf(address(stSpk)), TOTAL_STAKE + depositAmount,        "SPK not transferred to vault");

        // Check withdrawal shares were created correctly
        uint256 withdrawalShares = stSpk.withdrawalsOf(currentEpoch + 1, alice);
        assertEq(withdrawalShares, redeemWithdrawalShares, "Withdrawal shares mismatch");

        // Additional validation: withdrawal shares should represent the same value as withdrawn assets
        // In a 1:1 scenario, withdrawal shares should equal the asset amount withdrawn
        assertEq(redeemWithdrawalShares, withdrawnAssets, "Withdrawal shares should equal withdrawn assets");
    }

}

contract TestVaultTokenTest is BaseTest {

    function test_vaultToken_transferability() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        ( , uint256 mintedShares ) = stSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        // Check if Alice can transfer her stSpk tokens to Bob
        uint256 transferAmount = mintedShares / 2;

        vm.startPrank(alice);
        // This should work if stSpk tokens are transferable
        stSpk.transfer(bob, transferAmount);
        vm.stopPrank();

        // Verify transfer worked
        assertEq(stSpk.balanceOf(bob),   transferAmount,                "Bob should have received stSpk tokens");
        assertEq(stSpk.balanceOf(alice), mintedShares - transferAmount, "Alice should have remaining stSpk tokens");
    }

    function test_vaultToken_approvalAndTransferFrom() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        ( , uint256 mintedShares ) = stSpk.deposit(alice, depositAmount);

        // Alice approves Bob to spend her stSpk tokens
        uint256 approvalAmount = mintedShares / 2;
        stSpk.approve(bob, approvalAmount);
        vm.stopPrank();

        // Bob uses the approval to transfer Alice's tokens to Charlie
        vm.startPrank(bob);
        stSpk.transferFrom(alice, charlie, approvalAmount);
        vm.stopPrank();

        // Verify transfer worked
        assertEq(stSpk.balanceOf(charlie),    approvalAmount,                "Charlie should have received stSpk tokens");
        assertEq(stSpk.balanceOf(alice),      mintedShares - approvalAmount, "Alice should have remaining stSpk tokens");
        assertEq(stSpk.allowance(alice, bob), 0,                             "Allowance should be used up");
    }

}
