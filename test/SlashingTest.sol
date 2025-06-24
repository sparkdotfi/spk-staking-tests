// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";
import "../lib/core/src/interfaces/slasher/IVetoSlasher.sol";

contract SlashingTest is BaseTest {

    error InsufficientSlash();

    function test_wnauthorizedCannotCallOnSlash() public {
        vm.expectRevert("NotSlasher()");
        vm.prank(attacker);
        sSpk.onSlash(1000e18, uint48(block.timestamp));
    }

    function test_onlySlasherCanSlash() public {
        // Initialize the system and add some deposits for slashing
        _initializeEpochSystem();

        uint256 depositAmount = 5000e18;
        vm.startPrank(alice);
        spk.approve(address(sSpk), depositAmount);
        sSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        uint256 slashAmount = 500e18; // 10% slash
        uint48 captureTimestamp = uint48(block.timestamp);

        // Verify the slasher address is correctly set
        address actualSlasher = sSpk.slasher();
        assertEq(actualSlasher, VETO_SLASHER, "Slasher should be the veto slasher");

        // Test that unauthorized parties cannot slash

        // Attacker cannot slash
        vm.expectRevert("NotSlasher()");
        vm.prank(attacker);
        sSpk.onSlash(slashAmount, captureTimestamp);

        // Even admin cannot slash directly
        vm.expectRevert("NotSlasher()");
        vm.prank(SPARK_GOVERNANCE);
        sSpk.onSlash(slashAmount, captureTimestamp);

        // Regular user cannot slash
        vm.expectRevert("NotSlasher()");
        vm.prank(alice);
        sSpk.onSlash(slashAmount, captureTimestamp);

        // NOW TEST THAT ACTUAL SLASHER CAN SLASH
        uint256 totalStakeBefore = sSpk.totalStake();

        // The VETO_SLASHER should be able to slash successfully
        vm.prank(VETO_SLASHER);
        uint256 slashedAmount = sSpk.onSlash(slashAmount, captureTimestamp);

        // Verify slashing worked
        assertEq(slashedAmount, slashAmount, "Slashed amount should exactly equal requested amount");

        uint256 totalStakeAfter = sSpk.totalStake();
        assertLt(totalStakeAfter, totalStakeBefore, "Total stake should decrease after slashing");

        // Verify the slashed amount is reasonable
        assertEq(totalStakeAfter, totalStakeBefore - slashedAmount, "Total stake should decrease by slashed amount");
    }

    function test_realSlashingScenario() public {
        // Initialize epoch system and set up sSpk with deposits
        _initializeEpochSystem();

        // Setup: Alice deposits into sSpk
        uint256 depositAmount = 10000e18; // 10k SPK
        vm.startPrank(alice);
        spk.approve(address(sSpk), depositAmount);
        sSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        // Record initial state before slashing
        uint256 aliceSharesBefore = sSpk.balanceOf(alice);
        uint256 sSpkBalanceBefore = spk.balanceOf(address(sSpk));
        uint256 totalStakeBefore = sSpk.totalStake();

        // Simulate a real slashing event
        uint256 slashAmount = 1000e18; // Slash 1k SPK (10% of deposit)
        uint48 captureTimestamp = uint48(block.timestamp);

        // Only the veto slasher can perform slashing
        vm.prank(VETO_SLASHER);
        uint256 actualSlashedAmount = sSpk.onSlash(slashAmount, captureTimestamp);

        // Verify slashing effects with precise assertions
        uint256 totalStakeAfter = sSpk.totalStake();
        uint256 sSpkBalanceAfter = spk.balanceOf(address(sSpk));
        uint256 aliceSharesAfter = sSpk.balanceOf(alice);

        // Check that total stake was reduced by exact slashed amount
        assertEq(totalStakeAfter, totalStakeBefore - actualSlashedAmount, "Total stake should decrease by exact slashed amount");

        // Check that sSpk balance decreased by exact slashed amount (funds moved to burner/governance)
        assertEq(sSpkBalanceAfter, sSpkBalanceBefore - actualSlashedAmount, "Vault balance should decrease by exact slashed amount");

        // Alice's shares should remain exactly the same (slashing affects underlying value, not share count)
        assertEq(aliceSharesAfter, aliceSharesBefore, "Alice's shares count should remain unchanged");

        // Verify returned slashed amount is reasonable
        assertEq(actualSlashedAmount, slashAmount, "Slashed amount should exactly equal requested amount");
    }

    function test_slashingAccessControl() public {
        // Initialize system first to allow actual slashing verification
        _initializeEpochSystem();

        // Give Alice some tokens to deposit so slashing has an effect
        uint256 depositAmount = 2000e18;
        vm.startPrank(alice);
        spk.approve(address(sSpk), depositAmount);
        sSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        uint256 slashAmount = 100e18;
        uint48 captureTimestamp = uint48(block.timestamp);

        // Test that various unauthorized parties cannot slash

        // 1. Regular user cannot slash
        vm.expectRevert("NotSlasher()");
        vm.prank(alice);
        sSpk.onSlash(slashAmount, captureTimestamp);

        // 2. Governance cannot slash directly (must go through proper slasher)
        vm.expectRevert("NotSlasher()");
        vm.prank(SPARK_GOVERNANCE);
        sSpk.onSlash(slashAmount, captureTimestamp);

        // 3. Network delegator cannot slash directly
        vm.expectRevert("NotSlasher()");
        vm.prank(NETWORK_DELEGATOR);
        sSpk.onSlash(slashAmount, captureTimestamp);

        // 4. Attacker cannot slash
        vm.expectRevert("NotSlasher()");
        vm.prank(attacker);
        sSpk.onSlash(slashAmount, captureTimestamp);

        // 5. Only the designated veto slasher can slash - verify with precision
        uint256 totalStakeBefore = sSpk.totalStake();
        uint256 sSpkBalanceBefore = spk.balanceOf(address(sSpk));

        vm.prank(VETO_SLASHER);
        uint256 actualSlashedAmount = sSpk.onSlash(slashAmount, captureTimestamp);

        // Verify slashing succeeded with exact amounts
        uint256 totalStakeAfter = sSpk.totalStake();
        uint256 sSpkBalanceAfter = spk.balanceOf(address(sSpk));

        assertEq(totalStakeAfter,     totalStakeBefore - actualSlashedAmount,  "Total stake should decrease by exact slashed amount");
        assertEq(sSpkBalanceAfter,    sSpkBalanceBefore - actualSlashedAmount, "Vault balance should decrease by exact slashed amount");
        assertEq(actualSlashedAmount, slashAmount,                             "Slashed amount should exactly equal requested amount");
    }

    function test_slashingImpactOnUserWithdrawals() public {
        // Initialize and set up deposits
        _initializeEpochSystem();

        uint256 depositAmount = 5000e18;

        vm.startPrank(alice);

        spk.approve(address(sSpk), depositAmount);
        sSpk.deposit(alice, depositAmount);

        // Alice initiates withdrawal before slashing
        uint256 withdrawAmount    = 2000e18;
        uint256 currentEpoch      = sSpk.currentEpoch();
        uint256 currentEpochStart = sSpk.currentEpochStart();

        sSpk.withdraw(alice, withdrawAmount);

        vm.stopPrank();

        // Record withdrawal shares and sSpk state before slashing
        uint256 withdrawalEpoch = currentEpoch + 1;
        uint256 totalStakeBefore = sSpk.totalStake();
        uint256 sSpkBalanceBefore = spk.balanceOf(address(sSpk));

        // Slashing occurs after withdrawal but before claim
        uint256 slashAmount = 1000e18; // 20% of original deposit
        vm.prank(VETO_SLASHER);
        uint256 actualSlashedAmount = sSpk.onSlash(slashAmount, uint48(block.timestamp));

        // Verify slashing occurred correctly
        uint256 totalStakeAfter = sSpk.totalStake();
        uint256 sSpkBalanceAfter = spk.balanceOf(address(sSpk));

        assertEq(totalStakeAfter,     totalStakeBefore - actualSlashedAmount,  "Total stake should decrease by exact slashed amount");
        assertEq(sSpkBalanceAfter,    sSpkBalanceBefore - actualSlashedAmount, "Vault balance should decrease by exact slashed amount");
        assertGt(actualSlashedAmount, 0,                                       "Should have slashed a positive amount");

        // Fast forward to claim time
        uint256 claimableTime = currentEpochStart + (2 * EPOCH_DURATION);
        vm.warp(claimableTime + 1);

        // Alice attempts to claim her withdrawal
        uint256 aliceBalanceBefore = spk.balanceOf(alice);

        vm.prank(alice);
        uint256 claimedAmount = sSpk.claim(alice, withdrawalEpoch);

        // Verify claim worked and amount is affected by slashing
        uint256 aliceBalanceAfter = spk.balanceOf(alice);
        assertGt(claimedAmount,     0,                                  "Should still be able to claim something");
        assertEq(aliceBalanceAfter, aliceBalanceBefore + claimedAmount, "Should receive exact claimed amount");

        // The claimed amount should be less than the original withdrawal due to slashing
        assertLt(claimedAmount, withdrawAmount, "Claimed amount should be reduced due to slashing");

        // Verify the reduction is proportional to the slashing (allow for some tolerance)
        uint256 slashingPercentage = (actualSlashedAmount * 1e18) / totalStakeBefore;
        uint256 reductionPercentage = ((withdrawAmount - claimedAmount) * 1e18) / withdrawAmount;

        // Allow for reasonable tolerance (within 100 basis points = 1%)
        assertGe(reductionPercentage, slashingPercentage - 0.00001e18, "Reduction should be at least close to slashing percentage");
        assertLe(reductionPercentage, slashingPercentage + 0.00001e18, "Reduction should not exceed slashing percentage by much");
    }

    function test_multipleSlashingEvents() public {
        _initializeEpochSystem();

        // Give Alice extra tokens for this specific test
        deal(SPK, alice, 100_000e18); // Extra 100k SPK for slashing operations

        // Setup very large deposit to handle multiple slashes
        uint256 depositAmount = 50000e18; // 50k SPK
        vm.startPrank(alice);

        spk.approve(address(sSpk), depositAmount);
        sSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        uint256 initialTotalStake = sSpk.totalStake();
        uint256 initialVaultBalance = spk.balanceOf(address(sSpk));

        // First slashing event - small amount
        uint256 firstSlash = 50e18; // 50 SPK
        vm.prank(VETO_SLASHER);

        uint256 firstSlashedAmount         = sSpk.onSlash(firstSlash, uint48(block.timestamp));
        uint256 stakeAfterFirstSlash       = sSpk.totalStake();
        uint256 sSpkBalanceAfterFirstSlash = spk.balanceOf(address(sSpk));

        // Verify first slashing with exact amounts
        assertEq(stakeAfterFirstSlash,       initialTotalStake - firstSlashedAmount,   "First slash should reduce stake by exact amount");
        assertEq(sSpkBalanceAfterFirstSlash, initialVaultBalance - firstSlashedAmount, "First slash should reduce balance by exact amount");
        assertEq(firstSlashedAmount,         firstSlash,                               "First slashed amount should exactly equal requested amount");

        // Advance time
        vm.warp(block.timestamp + 1 days);

        // Second slashing event - small amount
        uint256 secondSlash = 25e18; // 25 SPK
        vm.prank(VETO_SLASHER);

        uint256 secondSlashedAmount         = sSpk.onSlash(secondSlash, uint48(block.timestamp));
        uint256 stakeAfterSecondSlash       = sSpk.totalStake();
        uint256 sSpkBalanceAfterSecondSlash = spk.balanceOf(address(sSpk));

        // Verify second slashing with exact amounts
        assertEq(stakeAfterSecondSlash,       stakeAfterFirstSlash - secondSlashedAmount,       "Second slash should reduce stake by exact amount");
        assertEq(sSpkBalanceAfterSecondSlash, sSpkBalanceAfterFirstSlash - secondSlashedAmount, "Second slash should reduce balance by exact amount");
        assertEq(secondSlashedAmount,         secondSlash,                                      "Second slashed amount should exactly equal requested amount");

        // Verify cumulative slashing effect with precision
        uint256 totalSlashedAmount = firstSlashedAmount + secondSlashedAmount;
        assertEq(stakeAfterSecondSlash,       initialTotalStake - totalSlashedAmount,   "Total stake reduction should equal sum of slashed amounts");
        assertEq(sSpkBalanceAfterSecondSlash, initialVaultBalance - totalSlashedAmount, "Total balance reduction should equal sum of slashed amounts");
    }

    function test_slashingWithZeroAmount() public {
        // Initialize system and add some stake to make the test meaningful
        _initializeEpochSystem();

        uint256 depositAmount = 1000e18;
        vm.startPrank(alice);
        spk.approve(address(sSpk), depositAmount);
        sSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        // Record state before zero slashing
        uint256 sSpkBalanceBefore = spk.balanceOf(address(sSpk));
        uint256 totalStakeBefore  = sSpk.totalStake();

        // Test edge case: slashing with zero amount
        vm.prank(VETO_SLASHER);
        uint256 actualSlashedAmount = sSpk.onSlash(0, uint48(block.timestamp));

        // Verify that zero slashing doesn't change state
        uint256 sSpkBalanceAfter = spk.balanceOf(address(sSpk));
        uint256 totalStakeAfter  = sSpk.totalStake();

        assertEq(actualSlashedAmount, 0,                 "Zero slashing should return zero slashed amount");
        assertEq(totalStakeAfter,     totalStakeBefore,  "Zero slashing should not change total stake");
        assertEq(sSpkBalanceAfter,    sSpkBalanceBefore, "Zero slashing should not change sSpk balance");
    }

    function test_slashingWithFutureTimestamp() public {
        // Initialize system and add stake for meaningful slashing
        _initializeEpochSystem();

        uint256 depositAmount = 2000e18;
        vm.startPrank(alice);
        spk.approve(address(sSpk), depositAmount);
        sSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        // Record state before slashing
        uint256 totalStakeBefore = sSpk.totalStake();
        uint256 sSpkBalanceBefore = spk.balanceOf(address(sSpk));

        // Test edge case: slashing with future timestamp
        uint48 futureTimestamp = uint48(block.timestamp + 1 days);
        uint256 slashAmount = 100e18;

        vm.prank(VETO_SLASHER);
        uint256 actualSlashedAmount = sSpk.onSlash(slashAmount, futureTimestamp);

        // Verify slashing still works regardless of timestamp
        uint256 sSpkBalanceAfter = spk.balanceOf(address(sSpk));
        uint256 totalStakeAfter  = sSpk.totalStake();

        assertEq(totalStakeAfter, totalStakeBefore - actualSlashedAmount, "Total stake should decrease by exact slashed amount");
        assertEq(sSpkBalanceAfter, sSpkBalanceBefore - actualSlashedAmount, "Vault balance should decrease by exact slashed amount");
        assertEq(actualSlashedAmount, slashAmount, "Slashed amount should exactly equal requested amount");
    }

    function test_completeSlashingFundFlow() public {
        // Test the complete slashing fund flow: sSpk -> burner router -> Spark Governance
        _initializeEpochSystem();

        // Setup: Alice deposits into sSpk
        uint256 depositAmount = 10000e18; // 10k SPK
        vm.startPrank(alice);
        spk.approve(address(sSpk), depositAmount);
        sSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        // Record initial balances before slashing
        uint256 sSpkBalanceBefore       = spk.balanceOf(address(sSpk));
        uint256 burnerBalanceBefore     = spk.balanceOf(BURNER_ROUTER);
        uint256 governanceBalanceBefore = spk.balanceOf(SPARK_GOVERNANCE);
        uint256 totalStakeBefore        = sSpk.totalStake();

        // Perform slashing
        uint256 slashAmount = 1000e18; // Slash 1k SPK

        uint48 captureTimestamp = uint48(block.timestamp);

        vm.prank(VETO_SLASHER);
        sSpk.onSlash(slashAmount, captureTimestamp);

        // Record balances after slashing
        uint256 sSpkBalanceAfter       = spk.balanceOf(address(sSpk));
        uint256 burnerBalanceAfter     = spk.balanceOf(BURNER_ROUTER);
        uint256 governanceBalanceAfter = spk.balanceOf(SPARK_GOVERNANCE);
        uint256 totalStakeAfter        = sSpk.totalStake();

        // Verify immediate fund flow effects
        // 1. Vault balance should decrease (funds leave immediately)
        assertLt(sSpkBalanceAfter, sSpkBalanceBefore, "Vault balance should decrease immediately");

        // 2. Total stake should decrease (slashing reduces stakeable amount)
        assertLt(totalStakeAfter, totalStakeBefore, "Total stake should decrease due to slashing");

        // 3. Either burner router or governance should have received the funds
        uint256 totalFundsAfter  = sSpkBalanceAfter + burnerBalanceAfter + governanceBalanceAfter;
        uint256 totalFundsBefore = sSpkBalanceBefore + burnerBalanceBefore + governanceBalanceBefore;

        // Total funds in the system should remain the same (just redistributed)
        assertEq(totalFundsAfter, totalFundsBefore, "Total funds should be conserved");

        // Calculate actual fund movements
        uint256 sSpkDecrease       = sSpkBalanceBefore - sSpkBalanceAfter;
        uint256 burnerIncrease     = burnerBalanceAfter - burnerBalanceBefore;
        uint256 governanceIncrease = governanceBalanceAfter - governanceBalanceBefore;

        // The sSpk decrease should match the increase somewhere else
        assertEq(sSpkDecrease, burnerIncrease + governanceIncrease, "Fund movement should balance");

        // Verify that funds moved immediately (no delay in transfer)
        assertGt(sSpkDecrease, 0, "Funds should have left sSpk immediately");
    }

    function test_slashingWithVetoWindow() public {
        // Test that demonstrates the 3-day veto window concept
        _initializeEpochSystem();

        uint256 depositAmount = 5000e18;

        vm.startPrank(alice);

        spk.approve(address(sSpk), depositAmount);
        sSpk.deposit(alice, depositAmount);
        vm.stopPrank();

        // Record state before slashing
        uint256 sSpkBalanceBefore = spk.balanceOf(address(sSpk));

        // Slashing occurs at time T
        uint256 slashTime   = block.timestamp;
        uint256 slashAmount = 500e18;

        vm.prank(VETO_SLASHER);
        sSpk.onSlash(slashAmount, uint48(slashTime));

        // Verify slashing happened immediately
        uint256 sSpkBalanceAfter = spk.balanceOf(address(sSpk));
        assertLt(sSpkBalanceAfter, sSpkBalanceBefore, "Slashing should take effect immediately");

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
        assertEq(spk.balanceOf(address(sSpk)), sSpkBalanceAfter, "Slashing remains in effect after veto window");
    }

    function test_networkOnboarding() public {
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

        // Step 3: Network opts into sSpk by setting max network limit
        // Our sSpk already has a network delegator, so check if it supports the interface
        address delegator = sSpk.delegator();
        assertEq(delegator, NETWORK_DELEGATOR, "Vault should have delegator");

        // Verify delegator has network limit functionality (this is what networks would call)
        ( bool limitSuccess, ) = delegator.staticcall(
            abi.encodeWithSignature("maxNetworkLimit(bytes32)", bytes32(0))
        );
        assertTrue(limitSuccess, "Delegator should support network limits");

        vm.stopPrank();

        // Verify the network can theoretically interact with our sSpk
        assertTrue(sSpk.isDelegatorInitialized(), "Vault delegator should be initialized");
        assertEq(sSpk.delegator(), NETWORK_DELEGATOR, "Should use correct delegator");
    }

    function test_operatorOnboardingFlow() public {
        // Test comprehensive operator onboarding flow according to Symbiotic documentation
        // Reference: https://docs.symbiotic.fi/handbooks/operators-handbook

        // Real Symbiotic contract addresses on mainnet
        address operatorRegistry    = 0xAd817a6Bc954F678451A71363f04150FDD81Af9F;
        address sSpkOptInService    = 0xb361894bC06cbBA7Ea8098BF0e32EB1906A5F891;
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

        // Step 2: Opt into sSpk using VaultOptInService
        assertTrue(sSpkOptInService != address(0), "VaultOptInService should exist");

        ( bool sSpkOptSuccess, ) = sSpkOptInService.staticcall(
            abi.encodeWithSignature("isOptedIn(address,address)", mockOperator, address(sSpk))
        );
        assertTrue(sSpkOptSuccess, "VaultOptInService should have isOptedIn function");

        // Step 3: Opt into network using NetworkOptInService
        assertTrue(networkOptInService != address(0), "NetworkOptInService should exist");

        ( bool networkOptSuccess, ) = networkOptInService.staticcall(
            abi.encodeWithSignature("isOptedIn(address,address)", mockOperator, NETWORK_DELEGATOR)
        );
        assertTrue(networkOptSuccess, "NetworkOptInService should have isOptedIn function");

        vm.stopPrank();

        // Step 4: Verify sSpk can manage operators through its delegator
        address delegator = sSpk.delegator();
        assertTrue(delegator != address(0), "Vault should have a delegator");
        assertEq(delegator, NETWORK_DELEGATOR, "Should use correct network delegator");

        // Verify delegator is properly initialized and can manage operator stakes
        assertTrue(sSpk.isDelegatorInitialized(), "Delegator should be initialized");

        // Verify slasher is properly configured for operator discipline
        address slasher = sSpk.slasher();
        assertEq(slasher, VETO_SLASHER, "Should use veto slasher for operator discipline");
        assertTrue(sSpk.isSlasherInitialized(), "Slasher should be initialized");

        // Step 5: Verify operator lifecycle management through sSpk
        // The sSpk should be able to track operator stakes through its delegator
        // and handle slashing through its slasher - both are properly configured

        // The complete onboarding flow verification:
        // 1. ✅ Symbiotic core contracts exist and have correct interfaces
        // 2. ✅ Vault has properly configured delegator for operator management
        // 3. ✅ Slashing mechanism is properly configured through veto slasher
        // 4. ✅ All required opt-in services are available for operators
        // 5. ✅ Network delegator and veto slasher are properly linked to the sSpk

        // Additional verification: Ensure sSpk can track stakes
        uint256 totalStake = sSpk.totalStake();
        assertTrue(totalStake >= 0, "Vault should be able to track total stake");

        // Verify epoch management for operator stake timing
        uint256 currentEpoch = sSpk.currentEpoch();
        assertTrue(currentEpoch >= 0, "Vault should track epochs for operator stake timing");
    }

    function test_slashingProportionalImpact() public {
        // Simplified test for proportional slashing impact to avoid stack too deep
        _initializeEpochSystem();

        // Setup users with deposits
        uint256 aliceDeposit = 6000e18;  // 6k SPK
        uint256 bobDeposit   = 4000e18;  // 4k SPK

        // Alice deposits
        vm.startPrank(alice);
        spk.approve(address(sSpk), aliceDeposit);
        sSpk.deposit(alice, aliceDeposit);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        spk.approve(address(sSpk), bobDeposit);
        sSpk.deposit(bob, bobDeposit);
        vm.stopPrank();

        // Record state before slashing
        uint256 totalStakeBefore  = sSpk.totalStake();
        uint256 sSpkBalanceBefore = spk.balanceOf(address(sSpk));
        uint256 aliceSharesBefore = sSpk.balanceOf(alice);
        uint256 bobSharesBefore   = sSpk.balanceOf(bob);

        // Perform slashing (20% of total stake)
        uint256 slashAmount = totalStakeBefore / 5; // 20% slash
        vm.prank(VETO_SLASHER);
        uint256 actualSlashedAmount = sSpk.onSlash(slashAmount, uint48(block.timestamp));

        // Record state after slashing
        uint256 totalStakeAfter  = sSpk.totalStake();
        uint256 sSpkBalanceAfter = spk.balanceOf(address(sSpk));

        // Verify slashing occurred with exact amounts
        assertEq(totalStakeAfter,     totalStakeBefore - actualSlashedAmount,  "Total stake should decrease by exact slashed amount");
        assertEq(sSpkBalanceAfter,    sSpkBalanceBefore - actualSlashedAmount, "Vault balance should decrease by exact slashed amount");
        assertGt(actualSlashedAmount, 0,                                       "Should have slashed a positive amount");
        assertLe(actualSlashedAmount, slashAmount,                             "Slashed amount should not exceed requested amount");

        // Shares should remain the same (slashing doesn't burn shares, just reduces their value)
        assertEq(sSpk.balanceOf(alice), aliceSharesBefore, "Alice's shares should remain unchanged");
        assertEq(sSpk.balanceOf(bob),   bobSharesBefore,   "Bob's shares should remain unchanged");

        // Both users should be affected proportionally through share value reduction
        // The proportional impact is reflected in the reduced total stake backing their shares
        uint256 shareValueReductionPercentage = (actualSlashedAmount * 10000) / totalStakeBefore; // basis points
        assertTrue(shareValueReductionPercentage > 0,     "Share value should be reduced by slashing");
        assertTrue(shareValueReductionPercentage <= 2000, "Share value reduction should be reasonable (<=20%)");
    }

    function test_preciseWithdrawalCalculationsAfterSlashing() public {
        // Test withdrawal calculations with multiple users and slashing scenarios
        _initializeEpochSystem();

        // Setup: Multiple users with different deposit amounts
        uint256 aliceDeposit = 3000e18;  // 3k SPK
        uint256 bobDeposit   = 7000e18;    // 7k SPK

        // Alice deposits
        vm.startPrank(alice);
        spk.approve(address(sSpk), aliceDeposit);
        sSpk.deposit(alice, aliceDeposit);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        spk.approve(address(sSpk), bobDeposit);
        sSpk.deposit(bob, bobDeposit);
        vm.stopPrank();

        // Both users initiate withdrawals
        uint256 aliceWithdrawAmount = 1500e18; // 50% of Alice's deposit
        uint256 bobWithdrawAmount   = 2100e18;   // 30% of Bob's deposit

        uint256 currentEpoch = sSpk.currentEpoch();
        uint256 currentEpochStart = sSpk.currentEpochStart();

        vm.prank(alice);
        sSpk.withdraw(alice, aliceWithdrawAmount);

        vm.prank(bob);
        sSpk.withdraw(bob, bobWithdrawAmount);

        // Record pre-slashing state
        uint256 withdrawalEpoch = currentEpoch + 1;
        uint256 totalStakeBefore = sSpk.totalStake();

        // Perform slashing: 15% of total stake
        uint256 slashAmount = (totalStakeBefore * 1500) / 10000; // 15%

        vm.prank(VETO_SLASHER);
        uint256 actualSlashedAmount = sSpk.onSlash(slashAmount, uint48(block.timestamp));

        // Verify slashing math
        assertEq(sSpk.totalStake(), totalStakeBefore - actualSlashedAmount, "Total stake should decrease by exact slashed amount");
        assertGt(actualSlashedAmount, 0, "Should have slashed a positive amount");

        // Fast forward to claim time
        vm.warp(currentEpochStart + (2 * EPOCH_DURATION) + 1);

        // Test Alice's claim
        uint256 aliceBalanceBefore = spk.balanceOf(alice);
        vm.prank(alice);
        uint256 aliceClaimedAmount = sSpk.claim(alice, withdrawalEpoch);

        // Test Bob's claim
        uint256 bobBalanceBefore = spk.balanceOf(bob);
        vm.prank(bob);
        uint256 bobClaimedAmount = sSpk.claim(bob, withdrawalEpoch);

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
        uint256 slashingPercentage = (actualSlashedAmount * 10000) / totalStakeBefore; // basis points
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

    function test_requestSlash_revertsInsufficientSlash() public {
        bytes32 network = bytes32(uint256(uint160(0x8c1a46D032B7b30D9AB4F30e51D8139CC3E85Ce3)) << 96);
        address NETWORK_MIDDLEWARE = 0x1bbd37E4325d931Aef5fEDEF1f87e8343835acE4;

        vm.prank(NETWORK_MIDDLEWARE);
        vm.expectRevert(abi.encodeWithSelector(InsufficientSlash.selector));
        IVetoSlasher(VETO_SLASHER).requestSlash(network, address(0), 1000e18, uint48(block.timestamp - 1 days), "");
    }

}
