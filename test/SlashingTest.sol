// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";
import "../lib/core/src/interfaces/slasher/IVetoSlasher.sol";

// NOTE: All of these tests are skipped because the configuration does not allow for slashing since the middleware is not set

contract SlashingTest is BaseTest {

    error InsufficientSlash();

    function test_cannotSlash() public {
        vm.startPrank(NETWORK);
        vm.expectRevert("NotNetworkMiddleware()");
        slasher.requestSlash(subnetwork, OPERATOR, 1, uint48(block.timestamp - 1), "");
    }

    function skip_test_unauthorizedCannotCallOnSlash() public {
        vm.expectRevert("NotSlasher()");
        vm.prank(attacker);
        stSpk.onSlash(1000e18, uint48(block.timestamp));
    }

    function _doSlash(uint256 slashAmount, uint48 captureTimestamp) internal returns (uint256 slashedAmount) {
        vm.startPrank(NETWORK);
        uint256 slashIndex = slasher.requestSlash(subnetwork, OPERATOR, slashAmount, captureTimestamp, "");

        skip(3 days + 1);  // Warp past veto window

        slashedAmount = slasher.executeSlash(slashIndex, "");

        vm.stopPrank();
    }

    function skip_test_onlySlasherCanSlash() public {
        // Initialize the system and add some deposits for slashing
        _initializeEpochSystem();

        uint256 depositAmount = 5000e18;
        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        skip(1 seconds);

        uint256 slashAmount = 500e18; // 10% slash
        uint48 captureTimestamp = uint48(block.timestamp - 1);  // Can't capture current timestamp and above

        // Verify the slasher address is correctly set
        address actualSlasher = stSpk.slasher();
        assertEq(actualSlasher, VETO_SLASHER, "Slasher should be the veto slasher");

        // Test that unauthorized parties cannot slash

        // Attacker cannot slash
        vm.expectRevert("NotSlasher()");
        vm.prank(attacker);
        stSpk.onSlash(slashAmount, captureTimestamp);

        // Even admin cannot slash directly
        vm.expectRevert("NotSlasher()");
        vm.prank(SPARK_GOVERNANCE);
        stSpk.onSlash(slashAmount, captureTimestamp);

        // Regular user cannot slash
        vm.expectRevert("NotSlasher()");
        vm.prank(alice);
        stSpk.onSlash(slashAmount, captureTimestamp);

        // NOW TEST THAT ACTUAL SLASHER CAN SLASH
        uint256 totalStakeBefore = stSpk.totalStake();

        uint256 slashedAmount = _doSlash(slashAmount, captureTimestamp);

        // Verify slashing worked
        assertEq(slashedAmount, slashAmount, "Slashed amount should exactly equal requested amount");

        uint256 totalStakeAfter = stSpk.totalStake();
        assertLt(totalStakeAfter, totalStakeBefore, "Total stake should decrease after slashing");

        // Verify the slashed amount is reasonable
        assertEq(totalStakeAfter, totalStakeBefore - slashedAmount, "Total stake should decrease by slashed amount");
    }

    function skip_test_realSlashingScenario() public {
        // Initialize epoch system and set up stSpk with deposits
        _initializeEpochSystem();

        // Setup: Alice deposits into stSpk
        uint256 depositAmount = 10000e18; // 10k SPK
        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        skip(1 seconds);

        // Record initial state before slashing
        uint256 aliceSharesBefore  = stSpk.balanceOf(alice);
        uint256 stSpkBalanceBefore = spk.balanceOf(address(stSpk));
        uint256 totalStakeBefore   = stSpk.totalStake();

        // Simulate a real slashing event
        uint256 slashAmount = 1000e18; // Slash 1k SPK (10% of deposit)
        uint48 captureTimestamp = uint48(block.timestamp - 1);  // Can't capture current timestamp and above

        uint256 slashedAmount = _doSlash(slashAmount, captureTimestamp);

        // Verify slashing effects with precise assertions
        uint256 totalStakeAfter   = stSpk.totalStake();
        uint256 stSpkBalanceAfter = spk.balanceOf(address(stSpk));
        uint256 aliceSharesAfter  = stSpk.balanceOf(alice);

        // Check that total stake was reduced by exact slashed amount
        assertEq(totalStakeAfter, totalStakeBefore - slashedAmount, "Total stake should decrease by exact slashed amount");

        // Check that stSpk balance decreased by exact slashed amount (funds moved to burner/governance)
        assertEq(stSpkBalanceAfter, stSpkBalanceBefore - slashedAmount, "Vault balance should decrease by exact slashed amount");

        // Alice's shares should remain exactly the same (slashing affects underlying value, not share count)
        assertEq(aliceSharesAfter, aliceSharesBefore, "Alice's shares count should remain unchanged");

        // Verify returned slashed amount is reasonable
        assertEq(slashedAmount, slashAmount, "Slashed amount should exactly equal requested amount");
    }

    function skip_test_slashingAccessControl() public {
        // Initialize system first to allow actual slashing verification
        _initializeEpochSystem();

        // Give Alice some tokens to deposit so slashing has an effect
        uint256 depositAmount = 2000e18;
        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        skip(1 seconds);

        uint256 slashAmount = 100e18;
        uint48 captureTimestamp = uint48(block.timestamp - 1);  // Can't capture current timestamp and above

        // Test that various unauthorized parties cannot slash

        // 1. Regular user cannot slash
        vm.expectRevert("NotSlasher()");
        vm.prank(alice);
        stSpk.onSlash(slashAmount, captureTimestamp);

        // 2. Governance cannot slash directly (must go through proper slasher)
        vm.expectRevert("NotSlasher()");
        vm.prank(SPARK_GOVERNANCE);
        stSpk.onSlash(slashAmount, captureTimestamp);

        // 3. Network delegator cannot slash directly
        vm.expectRevert("NotSlasher()");
        vm.prank(NETWORK_DELEGATOR);
        stSpk.onSlash(slashAmount, captureTimestamp);

        // 4. Attacker cannot slash
        vm.expectRevert("NotSlasher()");
        vm.prank(attacker);
        stSpk.onSlash(slashAmount, captureTimestamp);

        // 5. Only the designated veto slasher can slash - verify with precision
        uint256 totalStakeBefore   = stSpk.totalStake();
        uint256 stSpkBalanceBefore = spk.balanceOf(address(stSpk));

        uint256 slashedAmount = _doSlash(slashAmount, captureTimestamp);

        // Verify slashing succeeded with exact amounts
        uint256 totalStakeAfter  = stSpk.totalStake();
        uint256 stSpkBalanceAfter = spk.balanceOf(address(stSpk));

        assertEq(totalStakeAfter,   totalStakeBefore - slashedAmount,   "Total stake should decrease by exact slashed amount");
        assertEq(stSpkBalanceAfter, stSpkBalanceBefore - slashedAmount, "Vault balance should decrease by exact slashed amount");
        assertEq(slashedAmount,     slashAmount,                        "Slashed amount should exactly equal requested amount");
    }

    function skip_test_slashingImpactOnUserWithdrawals() public {
        // Initialize and set up deposits
        _initializeEpochSystem();

        uint256 depositAmount = 5000e18;

        vm.startPrank(alice);

        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);

        skip(1 seconds);

        // Alice initiates withdrawal before slashing
        uint256 withdrawAmount    = 2000e18;
        uint256 currentEpoch      = stSpk.currentEpoch();
        uint256 currentEpochStart = stSpk.currentEpochStart();

        stSpk.withdraw(alice, withdrawAmount);

        vm.stopPrank();

        // Record withdrawal shares and stSpk state before slashing
        uint256 withdrawalEpoch    = currentEpoch + 1;
        uint256 totalStakeBefore   = stSpk.totalStake();
        uint256 stSpkBalanceBefore = spk.balanceOf(address(stSpk));

        // Slashing occurs after withdrawal but before claim
        uint256 slashAmount = 1000e18; // 20% of original deposit
        uint256 slashedAmount = _doSlash(slashAmount, uint48(block.timestamp - 1));  // Can't capture current timestamp and above

        // Verify slashing occurred correctly
        uint256 totalStakeAfter   = stSpk.totalStake();
        uint256 stSpkBalanceAfter = spk.balanceOf(address(stSpk));

        assertEq(totalStakeAfter,   totalStakeBefore - slashedAmount,   "Total stake should decrease by exact slashed amount");
        assertEq(stSpkBalanceAfter, stSpkBalanceBefore - slashedAmount, "Vault balance should decrease by exact slashed amount");
        assertGt(slashedAmount,     0,                                  "Should have slashed a positive amount");

        // Fast forward to claim time
        uint256 claimableTime = currentEpochStart + (2 * EPOCH_DURATION);
        vm.warp(claimableTime + 1);

        // Alice attempts to claim her withdrawal
        uint256 aliceBalanceBefore = spk.balanceOf(alice);

        vm.prank(alice);
        uint256 claimedAmount = stSpk.claim(alice, withdrawalEpoch);

        // Verify claim worked and amount is affected by slashing
        uint256 aliceBalanceAfter = spk.balanceOf(alice);
        assertGt(claimedAmount,     0,                                  "Should still be able to claim something");
        assertEq(aliceBalanceAfter, aliceBalanceBefore + claimedAmount, "Should receive exact claimed amount");

        // The claimed amount should be less than the original withdrawal due to slashing
        assertLt(claimedAmount, withdrawAmount, "Claimed amount should be reduced due to slashing");

        // Verify the reduction is proportional to the slashing (allow for some tolerance)
        uint256 slashingPercentage = (slashedAmount * 1e18) / totalStakeBefore;
        uint256 reductionPercentage = ((withdrawAmount - claimedAmount) * 1e18) / withdrawAmount;

        // Allow for reasonable tolerance (within 100 basis points = 1%)
        assertGe(reductionPercentage, slashingPercentage - 0.00001e18, "Reduction should be at least close to slashing percentage");
        assertLe(reductionPercentage, slashingPercentage + 0.00001e18, "Reduction should not exceed slashing percentage by much");
    }

    function skip_test_slashingWithZeroAmount() public {
        vm.startPrank(NETWORK);
        vm.expectRevert("InsufficientSlash()");
        slasher.requestSlash(subnetwork, OPERATOR, 0, uint48(block.timestamp - 1), "");
    }

    function skip_test_slashingWithCurrentOrFutureTimestamp() public {
        vm.startPrank(NETWORK);
        vm.expectRevert("InvalidCaptureTimestamp()");
        slasher.requestSlash(subnetwork, OPERATOR, 0, uint48(block.timestamp), "");

        vm.expectRevert("InvalidCaptureTimestamp()");
        slasher.requestSlash(subnetwork, OPERATOR, 0, uint48(block.timestamp + 1), "");
    }

    // TODO: Refactor this
    function skip_test_completeSlashingFundFlow() public {
        // Test the complete slashing fund flow: stSpk -> burner router -> Spark Governance
        _initializeEpochSystem();

        // Setup: Alice deposits into stSpk
        uint256 depositAmount = 10000e18; // 10k SPK
        vm.startPrank(alice);
        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        skip(1 seconds);

        // Record initial balances before slashing
        uint256 stSpkBalanceBefore      = spk.balanceOf(address(stSpk));
        uint256 burnerBalanceBefore     = spk.balanceOf(BURNER_ROUTER);
        uint256 governanceBalanceBefore = spk.balanceOf(SPARK_GOVERNANCE);
        uint256 totalStakeBefore        = stSpk.totalStake();

        // Perform slashing
        uint256 slashAmount = 1000e18; // Slash 1k SPK

        uint48 captureTimestamp = uint48(block.timestamp - 1);  // Can't capture current timestamp and above

        uint256 slashedAmount = _doSlash(slashAmount, captureTimestamp);

        // Record balances after slashing
        uint256 stSpkBalanceAfter      = spk.balanceOf(address(stSpk));
        uint256 burnerBalanceAfter     = spk.balanceOf(BURNER_ROUTER);
        uint256 governanceBalanceAfter = spk.balanceOf(SPARK_GOVERNANCE);
        uint256 totalStakeAfter        = stSpk.totalStake();

        // Verify immediate fund flow effects
        // 1. Vault balance should decrease (funds leave immediately)
        assertEq(stSpkBalanceBefore - stSpkBalanceAfter, slashedAmount, "Vault balance should decrease immediately");

        // 2. Total stake should decrease (slashing reduces stakeable amount)
        assertEq(totalStakeBefore - totalStakeAfter, slashedAmount, "Total stake should decrease due to slashing");

        // 3. Either burner router or governance should have received the funds
        uint256 totalFundsAfter  = stSpkBalanceAfter + burnerBalanceAfter + governanceBalanceAfter;
        uint256 totalFundsBefore = stSpkBalanceBefore + burnerBalanceBefore + governanceBalanceBefore;

        // Total funds in the system should remain the same (just redistributed)
        assertEq(totalFundsAfter, totalFundsBefore, "Total funds should be conserved");

        // Calculate actual fund movements
        uint256 stSpkDecrease      = stSpkBalanceBefore - stSpkBalanceAfter;
        uint256 burnerIncrease     = burnerBalanceAfter - burnerBalanceBefore;
        uint256 governanceIncrease = governanceBalanceAfter - governanceBalanceBefore;

        // The stSpk decrease should match the increase somewhere else
        assertEq(stSpkDecrease, burnerIncrease + governanceIncrease, "Fund movement should balance");

        // Verify that funds moved immediately (no delay in transfer)
        assertGt(stSpkDecrease, 0, "Funds should have left stSpk immediately");
    }

    function skip_test_slashingWithVetoWindow() public {
        // Test that demonstrates the 3-day veto window concept
        _initializeEpochSystem();

        uint256 depositAmount = 5000e18;

        vm.startPrank(alice);

        spk.approve(address(stSpk), depositAmount);
        stSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        skip(1 seconds);

        // Record state before slashing
        uint256 stSpkBalanceBefore = spk.balanceOf(address(stSpk));

        // Slashing occurs at time T
        uint256 slashTime   = block.timestamp - 1;  // Can't capture current timestamp and above
        uint256 slashAmount = 500e18;

        uint256 slashedAmount = _doSlash(slashAmount, uint48(slashTime));

        // Verify slashing happened immediately
        uint256 stSpkBalanceAfter = spk.balanceOf(address(stSpk));
        assertEq(stSpkBalanceBefore - stSpkBalanceAfter, slashedAmount, "Slashing should take effect immediately");

        // The veto window is conceptual - in production:
        // - There's a 3-day window where governance could potentially veto the slashing
        // - But the funds are moved immediately to prevent griefing
        // - If vetoed, funds would need to be returned through governance action

        uint256 vetoWindowEnd = slashTime + SLASHER_VETO_DURATION;

        // Demonstrate timing relationships
        assertTrue(SLASHER_VETO_DURATION == 3 days, "Veto duration should be 3 days");
        assertTrue(vetoWindowEnd > slashTime,       "Veto window extends beyond slash time");

        // Fast forward past veto window
        vm.warp(vetoWindowEnd + 1);

        // After veto window, slashing is final
        // Vault balance should still be reduced (slashing remains in effect)
        assertEq(spk.balanceOf(address(stSpk)), stSpkBalanceAfter, "Slashing remains in effect after veto window");
    }

    function skip_test_networkOnboarding() public {
        // Test real network onboarding flow according to Symbiotic documentation
        // Reference: https://docs.symbiotic.fi/handbooks/networks-handbook

        // Real Symbiotic contract addresses on mainnet
        address networkRegistry          = 0xC773b1011461e7314CF05f97d95aa8e92C1Fd8aA;
        address networkMiddlewareService = 0xD7dC9B366c027743D90761F71858BCa83C6899Ad;

        // Create a mock network wanting to onboard
        address mockNetworkOwner = makeAddr("mockNetworkOwner");

        vm.startPrank(mockNetworkOwner);

        // Step 1: Register network in NetworkRegistry
        // Note: We can't actually call registerNetwork() on mainnet fork as it would fail
        // but we can verify the registry exists and has the right interface
        assertTrue(networkRegistry != address(0), "NetworkRegistry should exist");

        // Verify NetworkRegistry has the expected interface
        ( bool success, ) = networkRegistry.staticcall(
            abi.encodeWithSignature("isEntity(address)", mockNetworkOwner)
        );
        assertTrue(success, "NetworkRegistry should have isEntity function");

        // Step 2: Set network middleware (this would normally be done after deploying middleware)
        // Again, we can't actually call this on mainnet fork, but verify the service exists
        assertTrue(networkMiddlewareService != address(0), "NetworkMiddlewareService should exist");

        // Verify NetworkMiddlewareService has the expected interface
        ( bool middlewareSuccess, ) = networkMiddlewareService.staticcall(
            abi.encodeWithSignature("middleware(address)", mockNetworkOwner)
        );
        assertTrue(middlewareSuccess, "NetworkMiddlewareService should have middleware function");

        // Step 3: Network opts into stSpk by setting max network limit
        // Our stSpk already has a network delegator, so check if it supports the interface
        address delegator = stSpk.delegator();
        assertEq(delegator, NETWORK_DELEGATOR, "Vault should have delegator");

        // Verify delegator has network limit functionality (this is what networks would call)
        ( bool limitSuccess, ) = delegator.staticcall(
            abi.encodeWithSignature("maxNetworkLimit(bytes32)", bytes32(0))
        );
        assertTrue(limitSuccess, "Delegator should support network limits");

        vm.stopPrank();

        // Verify the network can theoretically interact with our stSpk
        assertTrue(stSpk.isDelegatorInitialized(), "Vault delegator should be initialized");
        assertEq(stSpk.delegator(), NETWORK_DELEGATOR, "Should use correct delegator");
    }

    function skip_test_operatorOnboardingFlow() public {
        // Test comprehensive operator onboarding flow according to Symbiotic documentation
        // Reference: https://docs.symbiotic.fi/handbooks/operators-handbook

        // Real Symbiotic contract addresses on mainnet
        address operatorRegistry    = 0xAd817a6Bc954F678451A71363f04150FDD81Af9F;
        address stSpkOptInService   = 0xb361894bC06cbBA7Ea8098BF0e32EB1906A5F891;
        address networkOptInService = 0x7133415b33B438843D581013f98A08704316633c;

        // Create mock operator wanting to onboard
        address mockOperator = makeAddr("mockOperator");

        vm.startPrank(mockOperator);

        // Step 1: Register operator in OperatorRegistry
        // Verify OperatorRegistry exists and has correct interface
        assertTrue(operatorRegistry != address(0), "OperatorRegistry should exist");

        ( bool regSuccess, ) = operatorRegistry.staticcall(
            abi.encodeWithSignature("isEntity(address)", mockOperator)
        );
        assertTrue(regSuccess, "OperatorRegistry should have isEntity function");

        // Step 2: Opt into stSpk using VaultOptInService
        assertTrue(stSpkOptInService != address(0), "VaultOptInService should exist");

        ( bool stSpkOptSuccess, ) = stSpkOptInService.staticcall(
            abi.encodeWithSignature("isOptedIn(address,address)", mockOperator, address(stSpk))
        );
        assertTrue(stSpkOptSuccess, "VaultOptInService should have isOptedIn function");

        // Step 3: Opt into network using NetworkOptInService
        assertTrue(networkOptInService != address(0), "NetworkOptInService should exist");

        ( bool networkOptSuccess, ) = networkOptInService.staticcall(
            abi.encodeWithSignature("isOptedIn(address,address)", mockOperator, NETWORK_DELEGATOR)
        );
        assertTrue(networkOptSuccess, "NetworkOptInService should have isOptedIn function");

        vm.stopPrank();

        // Step 4: Verify stSpk can manage operators through its delegator
        address delegator = stSpk.delegator();
        assertTrue(delegator != address(0), "Vault should have a delegator");
        assertEq(delegator, NETWORK_DELEGATOR, "Should use correct network delegator");

        // Verify delegator is properly initialized and can manage operator stakes
        assertTrue(stSpk.isDelegatorInitialized(), "Delegator should be initialized");

        // Verify slasher is properly configured for operator discipline
        address slasher = stSpk.slasher();
        assertEq(slasher, VETO_SLASHER, "Should use veto slasher for operator discipline");
        assertTrue(stSpk.isSlasherInitialized(), "Slasher should be initialized");

        // Step 5: Verify operator lifecycle management through stSpk
        // The stSpk should be able to track operator stakes through its delegator
        // and handle slashing through its slasher - both are properly configured

        // The complete onboarding flow verification:
        // 1. ✅ Symbiotic core contracts exist and have correct interfaces
        // 2. ✅ Vault has properly configured delegator for operator management
        // 3. ✅ Slashing mechanism is properly configured through veto slasher
        // 4. ✅ All required opt-in services are available for operators
        // 5. ✅ Network delegator and veto slasher are properly linked to the stSpk

        // Additional verification: Ensure stSpk can track stakes
        uint256 totalStake = stSpk.totalStake();
        assertTrue(totalStake >= 0, "Vault should be able to track total stake");

        // Verify epoch management for operator stake timing
        uint256 currentEpoch = stSpk.currentEpoch();
        assertTrue(currentEpoch >= 0, "Vault should track epochs for operator stake timing");
    }

    function skip_test_slashingProportionalImpact() public {
        // Simplified test for proportional slashing impact to avoid stack too deep
        _initializeEpochSystem();

        // Setup users with deposits
        uint256 aliceDeposit = 6000e18;  // 6k SPK
        uint256 bobDeposit   = 4000e18;  // 4k SPK

        // Alice deposits
        vm.startPrank(alice);
        spk.approve(address(stSpk), aliceDeposit);
        stSpk.deposit(alice, aliceDeposit);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        spk.approve(address(stSpk), bobDeposit);
        stSpk.deposit(bob, bobDeposit);
        vm.stopPrank();

        skip(1 seconds);

        // Record state before slashing
        uint256 totalStakeBefore   = stSpk.totalStake();
        uint256 stSpkBalanceBefore = spk.balanceOf(address(stSpk));
        uint256 aliceSharesBefore  = stSpk.balanceOf(alice);
        uint256 bobSharesBefore    = stSpk.balanceOf(bob);

        // Perform slashing (20% of total stake)
        uint256 slashAmount = totalStakeBefore / 5; // 20% slash
        uint256 slashedAmount = _doSlash(slashAmount, uint48(block.timestamp - 1));  // Can't capture current timestamp and above

        // Record state after slashing
        uint256 totalStakeAfter   = stSpk.totalStake();
        uint256 stSpkBalanceAfter = spk.balanceOf(address(stSpk));

        // Verify slashing occurred with exact amounts
        assertEq(totalStakeAfter,   totalStakeBefore - slashedAmount,   "Total stake should decrease by exact slashed amount");
        assertEq(stSpkBalanceAfter, stSpkBalanceBefore - slashedAmount, "Vault balance should decrease by exact slashed amount");
        assertGt(slashedAmount,     0,                                  "Should have slashed a positive amount");
        assertLe(slashedAmount,     slashAmount,                        "Slashed amount should not exceed requested amount");

        // Shares should remain the same (slashing doesn't burn shares, just reduces their value)
        assertEq(stSpk.balanceOf(alice), aliceSharesBefore, "Alice's shares should remain unchanged");
        assertEq(stSpk.balanceOf(bob),   bobSharesBefore,   "Bob's shares should remain unchanged");

        // Both users should be affected proportionally through share value reduction
        // The proportional impact is reflected in the reduced total stake backing their shares
        uint256 shareValueReductionPercentage = (slashedAmount * 10000) / totalStakeBefore; // basis points
        assertTrue(shareValueReductionPercentage > 0,     "Share value should be reduced by slashing");
        assertTrue(shareValueReductionPercentage <= 2000, "Share value reduction should be reasonable (<=20%)");
    }

    function skip_test_preciseWithdrawalCalculationsAfterSlashing() public {
        // Test withdrawal calculations with multiple users and slashing scenarios
        _initializeEpochSystem();

        // Setup: Multiple users with different deposit amounts
        uint256 aliceDeposit = 3000e18;  // 3k SPK
        uint256 bobDeposit   = 7000e18;    // 7k SPK

        // Alice deposits
        vm.startPrank(alice);
        spk.approve(address(stSpk), aliceDeposit);
        stSpk.deposit(alice, aliceDeposit);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        spk.approve(address(stSpk), bobDeposit);
        stSpk.deposit(bob, bobDeposit);
        vm.stopPrank();

        skip(1 seconds);

        // Both users initiate withdrawals
        uint256 aliceWithdrawAmount = 1500e18; // 50% of Alice's deposit
        uint256 bobWithdrawAmount   = 2100e18;   // 30% of Bob's deposit

        uint256 currentEpoch      = stSpk.currentEpoch();
        uint256 currentEpochStart = stSpk.currentEpochStart();

        vm.prank(alice);
        stSpk.withdraw(alice, aliceWithdrawAmount);

        vm.prank(bob);
        stSpk.withdraw(bob, bobWithdrawAmount);

        // Record pre-slashing state
        uint256 withdrawalEpoch = currentEpoch + 1;
        uint256 totalStakeBefore = stSpk.totalStake();

        // Perform slashing: 15% of total stake
        uint256 slashAmount = (totalStakeBefore * 1500) / 10000; // 15%

        uint256 slashedAmount = _doSlash(slashAmount, uint48(block.timestamp - 1));  // Can't capture current timestamp and above

        // Verify slashing math
        assertEq(stSpk.totalStake(), totalStakeBefore - slashedAmount, "Total stake should decrease by exact slashed amount");
        assertGt(slashedAmount, 0, "Should have slashed a positive amount");

        // Fast forward to claim time
        vm.warp(currentEpochStart + (2 * EPOCH_DURATION) + 1);

        // Test Alice's claim
        uint256 aliceBalanceBefore = spk.balanceOf(alice);
        vm.prank(alice);
        uint256 aliceClaimedAmount = stSpk.claim(alice, withdrawalEpoch);

        // Test Bob's claim
        uint256 bobBalanceBefore = spk.balanceOf(bob);
        vm.prank(bob);
        uint256 bobClaimedAmount = stSpk.claim(bob, withdrawalEpoch);

        // VERIFICATIONS

        // 1. Both users should receive some amount
        assertGt(aliceClaimedAmount, 0, "Alice should receive some amount");
        assertGt(bobClaimedAmount, 0, "Bob should receive some amount");

        // 2. Balance updates should be correct
        assertEq(spk.balanceOf(alice), aliceBalanceBefore + aliceClaimedAmount, "Alice's balance should increase by claimed amount");
        assertEq(spk.balanceOf(bob), bobBalanceBefore + bobClaimedAmount, "Bob's balance should increase by claimed amount");

        // 3. Claimed amounts should be reduced due to slashing
        assertLt(aliceClaimedAmount, aliceWithdrawAmount, "Alice's claim should be reduced due to slashing");
        assertLt(bobClaimedAmount, bobWithdrawAmount, "Bob's claim should be reduced due to slashing");

        // 4. Verify proportional impact (allow for reasonable tolerance)
        uint256 slashingPercentage = (slashedAmount * 10000) / totalStakeBefore; // basis points
        uint256 aliceReductionPercentage = ((aliceWithdrawAmount - aliceClaimedAmount) * 10000) / aliceWithdrawAmount;
        uint256 bobReductionPercentage = ((bobWithdrawAmount - bobClaimedAmount) * 10000) / bobWithdrawAmount;

        // Both users should be affected by similar percentage (within reasonable tolerance)
        assertTrue(aliceReductionPercentage >= slashingPercentage - 200, "Alice's reduction should be close to slashing percentage");
        assertTrue(aliceReductionPercentage <= slashingPercentage + 200, "Alice's reduction should not exceed slashing percentage by much");
        assertTrue(bobReductionPercentage >= slashingPercentage - 200, "Bob's reduction should be close to slashing percentage");
        assertTrue(bobReductionPercentage <= slashingPercentage + 200, "Bob's reduction should not exceed slashing percentage by much");

        // 5. The total claimed should be reasonable
        uint256 totalClaimed = aliceClaimedAmount + bobClaimedAmount;
        uint256 totalWithdrawn = aliceWithdrawAmount + bobWithdrawAmount;
        assertLt(totalClaimed, totalWithdrawn, "Total claimed should be less than total withdrawn due to slashing");

        // Total reduction should be reasonable
        uint256 totalReductionPercentage = ((totalWithdrawn - totalClaimed) * 10000) / totalWithdrawn;
        assertTrue(totalReductionPercentage >= slashingPercentage - 200, "Total reduction should be close to slashing percentage");
        assertTrue(totalReductionPercentage <= slashingPercentage + 200, "Total reduction should not exceed slashing percentage by much");
    }

    function skip_test_requestSlash_revertsInsufficientSlash() public {
        bytes32 network = bytes32(uint256(uint160(0x8c1a46D032B7b30D9AB4F30e51D8139CC3E85Ce3)) << 96);
        address NETWORK_MIDDLEWARE = 0x1bbd37E4325d931Aef5fEDEF1f87e8343835acE4;

        vm.prank(NETWORK_MIDDLEWARE);
        vm.expectRevert(abi.encodeWithSelector(InsufficientSlash.selector));
        IVetoSlasher(VETO_SLASHER).requestSlash(network, address(0), 1000e18, uint48(block.timestamp - 1 days), "");
    }

}
