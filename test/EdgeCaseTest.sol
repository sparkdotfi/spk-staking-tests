// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";

contract EdgeCaseTest is BaseTest {
    
    function test_ZeroAmountDeposit() public {
        vm.startPrank(alice);
        spkToken.approve(VAULT_ADDRESS, 0);
        vm.expectRevert("InsufficientDeposit()");
        vault.deposit(alice, 0);
        vm.stopPrank();
    }
    
    function test_ZeroAmountWithdraw() public {
        uint256 depositAmount = 1000 * 1e18;
        
        vm.startPrank(alice);
        spkToken.approve(VAULT_ADDRESS, depositAmount);
        vault.deposit(alice, depositAmount);
        
        vm.expectRevert("InsufficientWithdrawal()");
        vault.withdraw(alice, 0);
        vm.stopPrank();
    }
    
    function test_ZeroSharesRedeem() public {
        uint256 depositAmount = 1000 * 1e18;
        
        vm.startPrank(alice);
        spkToken.approve(VAULT_ADDRESS, depositAmount);
        vault.deposit(alice, depositAmount);
        
        vm.expectRevert("InsufficientRedemption()");
        vault.redeem(alice, 0);
        vm.stopPrank();
    }
    
    function test_InvalidRecipientClaim() public {
        vm.expectRevert("InvalidRecipient()");
        vm.prank(alice);
        vault.claim(address(0), 1);
    }
    
    function test_InvalidRecipientClaimBatch() public {
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = 1;
        
        vm.expectRevert("InvalidRecipient()");
        vm.prank(alice);
        vault.claimBatch(address(0), epochs);
    }
    
    function test_EmptyEpochsClaimBatch() public {
        uint256[] memory epochs = new uint256[](0);
        
        vm.expectRevert("InvalidLengthEpochs()");
        vm.prank(alice);
        vault.claimBatch(alice, epochs);
    }
    
    function test_InvalidOnBehalfOfDeposit() public {
        vm.startPrank(alice);
        spkToken.approve(VAULT_ADDRESS, 1000 * 1e18);
        vm.expectRevert("InvalidOnBehalfOf()");
        vault.deposit(address(0), 1000 * 1e18);
        vm.stopPrank();
    }
    
    function test_DepositWithInsufficientBalance() public {
        uint256 aliceBalance = spkToken.balanceOf(alice);
        uint256 depositAmount = aliceBalance + 1; // More than Alice has
        
        vm.startPrank(alice);
        spkToken.approve(VAULT_ADDRESS, depositAmount);
        
        vm.expectRevert("SDAO/insufficient-balance");
        vault.deposit(alice, depositAmount);
        
        vm.stopPrank();
    }
    
    function test_WithdrawMoreThanBalance() public {
        uint256 depositAmount = 1000 * 1e18;
        
        vm.startPrank(alice);
        spkToken.approve(VAULT_ADDRESS, depositAmount);
        vault.deposit(alice, depositAmount);
        
        // Try to withdraw more than deposited
        uint256 withdrawAmount = depositAmount + 1;
        vm.expectRevert("TooMuchWithdraw()");
        vault.withdraw(alice, withdrawAmount);
        
        vm.stopPrank();
    }
    
    function test_ClaimBeforeEpochDelay() public {
        uint256 depositAmount = 1000 * 1e18;
        
        vm.startPrank(alice);
        spkToken.approve(VAULT_ADDRESS, depositAmount);
        vault.deposit(alice, depositAmount);
        
        uint256 currentEpoch = vault.currentEpoch();
        vault.withdraw(alice, 500 * 1e18);
        
        // Try to claim immediately (should fail)
        vm.expectRevert("InvalidEpoch()");
        vault.claim(alice, currentEpoch + 1);
        
        vm.stopPrank();
    }
} 