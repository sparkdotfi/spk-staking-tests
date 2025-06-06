// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";

contract EdgeCaseTest is BaseTest {

    function test_ZeroAmountDeposit() public {
        vm.startPrank(alice);
        spk.approve(address(sSpk), 0);
        vm.expectRevert("InsufficientDeposit()");
        sSpk.deposit(alice, 0);
        vm.stopPrank();
    }

    function test_ZeroAmountWithdraw() public {
        uint256 depositAmount = 1000 * 1e18;

        vm.startPrank(alice);
        spk.approve(address(sSpk), depositAmount);
        sSpk.deposit(alice, depositAmount);

        vm.expectRevert("InsufficientWithdrawal()");
        sSpk.withdraw(alice, 0);
        vm.stopPrank();
    }

    function test_ZeroSharesRedeem() public {
        uint256 depositAmount = 1000 * 1e18;

        vm.startPrank(alice);
        spk.approve(address(sSpk), depositAmount);
        sSpk.deposit(alice, depositAmount);

        vm.expectRevert("InsufficientRedemption()");
        sSpk.redeem(alice, 0);
        vm.stopPrank();
    }

    function test_InvalidRecipientClaim() public {
        vm.expectRevert("InvalidRecipient()");
        vm.prank(alice);
        sSpk.claim(address(0), 1);
    }

    function test_InvalidRecipientClaimBatch() public {
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = 1;

        vm.expectRevert("InvalidRecipient()");
        vm.prank(alice);
        sSpk.claimBatch(address(0), epochs);
    }

    function test_EmptyEpochsClaimBatch() public {
        uint256[] memory epochs = new uint256[](0);

        vm.expectRevert("InvalidLengthEpochs()");
        vm.prank(alice);
        sSpk.claimBatch(alice, epochs);
    }

    function test_InvalidOnBehalfOfDeposit() public {
        vm.startPrank(alice);
        spk.approve(address(sSpk), 1000 * 1e18);
        vm.expectRevert("InvalidOnBehalfOf()");
        sSpk.deposit(address(0), 1000 * 1e18);
        vm.stopPrank();
    }

    function test_DepositWithInsufficientBalance() public {
        uint256 aliceBalance = spk.balanceOf(alice);
        uint256 depositAmount = aliceBalance + 1; // More than Alice has

        vm.startPrank(alice);
        spk.approve(address(sSpk), depositAmount);

        vm.expectRevert("SDAO/insufficient-balance");
        sSpk.deposit(alice, depositAmount);

        vm.stopPrank();
    }

    function test_WithdrawMoreThanBalance() public {
        uint256 depositAmount = 1000 * 1e18;

        vm.startPrank(alice);
        spk.approve(address(sSpk), depositAmount);
        sSpk.deposit(alice, depositAmount);

        // Try to withdraw more than deposited
        uint256 withdrawAmount = depositAmount + 1;
        vm.expectRevert("TooMuchWithdraw()");
        sSpk.withdraw(alice, withdrawAmount);

        vm.stopPrank();
    }

    function test_ClaimBeforeEpochDelay() public {
        uint256 depositAmount = 1000 * 1e18;

        vm.startPrank(alice);
        spk.approve(address(sSpk), depositAmount);
        sSpk.deposit(alice, depositAmount);

        uint256 currentEpoch = sSpk.currentEpoch();
        sSpk.withdraw(alice, 500 * 1e18);

        // Try to claim immediately (should fail)
        vm.expectRevert("InvalidEpoch()");
        sSpk.claim(alice, currentEpoch + 1);

        vm.stopPrank();
    }
}
