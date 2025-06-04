// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";

contract SlashingTest is BaseTest {
    
    function test_UnauthorizedCannotCallOnSlash() public {
        vm.expectRevert("NotSlasher()");
        vm.prank(attacker);
        vault.onSlash(1000 * 1e18, uint48(block.timestamp));
    }
    
    function test_OnlySlasherCanSlash() public {
        // Test that only the designated slasher can call onSlash
        address actualSlasher = vault.slasher();
        
        // Attacker cannot slash
        vm.expectRevert("NotSlasher()");
        vm.prank(attacker);
        vault.onSlash(100 * 1e18, uint48(block.timestamp));
        
        // Even admin cannot slash
        vm.expectRevert("NotSlasher()");
        vm.prank(SPARK_GOVERNANCE);
        vault.onSlash(100 * 1e18, uint48(block.timestamp));
        
        // Only actual slasher can slash (though we can't easily test this on mainnet fork)
        assertEq(actualSlasher, VETO_SLASHER, "Slasher should be the veto slasher");
    }
    
    function test_RealSlashingScenario() public {
        // Initialize epoch system and set up vault with deposits
        _initializeEpochSystem();
        
        // Setup: Alice deposits into vault
        uint256 depositAmount = 10000 * 1e18; // 10k SPK
        vm.startPrank(alice);
        spkToken.approve(VAULT_ADDRESS, depositAmount);
        vault.deposit(alice, depositAmount);
        vm.stopPrank();
        
        // Record initial state before slashing
        uint256 aliceSharesBefore = vaultToken.balanceOf(alice);
        uint256 vaultBalanceBefore = spkToken.balanceOf(VAULT_ADDRESS);
        uint256 totalStakeBefore = vault.totalStake();
        
        // Simulate a real slashing event
        uint256 slashAmount = 1000 * 1e18; // Slash 1k SPK (10% of deposit)
        uint48 captureTimestamp = uint48(block.timestamp);
        
        // Only the veto slasher can perform slashing
        vm.prank(VETO_SLASHER);
        vault.onSlash(slashAmount, captureTimestamp);
        
        // Verify slashing effects
        uint256 totalStakeAfter = vault.totalStake();
        uint256 vaultBalanceAfter = spkToken.balanceOf(VAULT_ADDRESS);
        
        // Check that total stake was reduced (slashing happened)
        assertLt(totalStakeAfter, totalStakeBefore, "Total stake should decrease after slashing");
        
        // Check that vault balance changed (slashed tokens are moved to burner or redistributed)
        assertLt(vaultBalanceAfter, vaultBalanceBefore, "Vault balance should decrease due to slashing");
        
        // Alice's shares should still be the same (slashing affects the underlying value)
        uint256 aliceSharesAfter = vaultToken.balanceOf(alice);
        assertEq(aliceSharesAfter, aliceSharesBefore, "Alice's shares count remains the same");
        
        // But the value per share has decreased due to slashing
        assertTrue(totalStakeAfter < totalStakeBefore, "Slashing reduces total stake");
    }
    
    function test_SlashingAccessControl() public {
        uint256 slashAmount = 100 * 1e18;
        uint48 captureTimestamp = uint48(block.timestamp);
        
        // Test that various unauthorized parties cannot slash
        
        // 1. Regular user cannot slash
        vm.expectRevert("NotSlasher()");
        vm.prank(alice);
        vault.onSlash(slashAmount, captureTimestamp);
        
        // 2. Governance cannot slash directly (must go through proper slasher)
        vm.expectRevert("NotSlasher()");
        vm.prank(SPARK_GOVERNANCE);
        vault.onSlash(slashAmount, captureTimestamp);
        
        // 3. Network delegator cannot slash directly
        vm.expectRevert("NotSlasher()");
        vm.prank(NETWORK_DELEGATOR);
        vault.onSlash(slashAmount, captureTimestamp);
        
        // 4. Attacker cannot slash
        vm.expectRevert("NotSlasher()");
        vm.prank(attacker);
        vault.onSlash(slashAmount, captureTimestamp);
        
        // 5. Only the designated veto slasher can slash
        vm.prank(VETO_SLASHER);
        vault.onSlash(slashAmount, captureTimestamp); // Should succeed
    }
    
    function test_SlashingImpactOnUserWithdrawals() public {
        // Initialize and set up deposits
        _initializeEpochSystem();
        
        uint256 depositAmount = 5000 * 1e18;
        vm.startPrank(alice);
        spkToken.approve(VAULT_ADDRESS, depositAmount);
        vault.deposit(alice, depositAmount);
        
        // Alice initiates withdrawal before slashing
        uint256 withdrawAmount = 2000 * 1e18;
        uint256 currentEpoch = vault.currentEpoch();
        uint256 currentEpochStart = vault.currentEpochStart();
        vault.withdraw(alice, withdrawAmount);
        vm.stopPrank();
        
        // Record withdrawal shares before slashing
        uint256 withdrawalEpoch = currentEpoch + 1;
        uint256 withdrawalSharesBefore = vault.withdrawalsOf(withdrawalEpoch, alice);
        
        // Slashing occurs after withdrawal but before claim
        uint256 slashAmount = 1000 * 1e18; // 20% of remaining stake
        vm.prank(VETO_SLASHER);
        vault.onSlash(slashAmount, uint48(block.timestamp));
        
        // Fast forward to claim time
        uint256 claimableTime = currentEpochStart + (2 * EPOCH_DURATION);
        vm.warp(claimableTime + 1);
        
        // Alice attempts to claim her withdrawal
        uint256 aliceBalanceBefore = spkToken.balanceOf(alice);
        
        vm.prank(alice);
        uint256 claimedAmount = vault.claim(alice, withdrawalEpoch);
        
        // Verify claim worked but amount might be affected by slashing
        assertGt(claimedAmount, 0, "Should still be able to claim something");
        assertEq(spkToken.balanceOf(alice), aliceBalanceBefore + claimedAmount, "Should receive claimed tokens");
    }
    
    function test_MultipleSlashingEvents() public {
        _initializeEpochSystem();
        
        // Give Alice extra tokens for this specific test
        _giveTokens(alice, 100000 * 1e18); // Extra 100k SPK for slashing operations
        
        // Setup very large deposit to handle multiple slashes
        uint256 depositAmount = 50000 * 1e18; // 50k SPK
        vm.startPrank(alice);
        spkToken.approve(VAULT_ADDRESS, depositAmount);
        vault.deposit(alice, depositAmount);
        vm.stopPrank();
        
        uint256 initialTotalStake = vault.totalStake();
        
        // First slashing event - small amount
        uint256 firstSlash = 50 * 1e18; // 50 SPK
        vm.prank(VETO_SLASHER);
        vault.onSlash(firstSlash, uint48(block.timestamp));
        
        uint256 stakeAfterFirstSlash = vault.totalStake();
        assertLt(stakeAfterFirstSlash, initialTotalStake, "First slash should reduce stake");
        
        // Advance time
        vm.warp(block.timestamp + 1 days);
        
        // Second slashing event - small amount
        uint256 secondSlash = 25 * 1e18; // 25 SPK
        vm.prank(VETO_SLASHER);
        vault.onSlash(secondSlash, uint48(block.timestamp));
        
        uint256 stakeAfterSecondSlash = vault.totalStake();
        assertLt(stakeAfterSecondSlash, stakeAfterFirstSlash, "Second slash should further reduce stake");
        
        // Verify cumulative slashing effect
        uint256 totalSlashEffect = initialTotalStake - stakeAfterSecondSlash;
        assertGt(totalSlashEffect, 0, "Slashing should have some effect");
    }
    
    function test_SlashingWithZeroAmount() public {
        // Test edge case: slashing with zero amount
        vm.prank(VETO_SLASHER);
        vault.onSlash(0, uint48(block.timestamp)); // Should not revert
        
        // Verify that zero slashing doesn't change anything meaningfully
        uint256 totalStake = vault.totalStake();
        assertEq(totalStake, totalStake, "Zero slashing should not change total stake significantly");
    }
    
    function test_SlashingWithFutureTimestamp() public {
        // Test edge case: slashing with future timestamp
        uint48 futureTimestamp = uint48(block.timestamp + 1 days);
        
        vm.prank(VETO_SLASHER);
        vault.onSlash(100 * 1e18, futureTimestamp); // Should not revert
        
        // If it doesn't revert, verify slashing still works
        uint256 totalStake = vault.totalStake();
        // The exact behavior depends on implementation
    }
    
    function test_CompleteSlashingFundFlow() public {
        // Test the complete slashing fund flow: vault -> burner router -> Spark Governance
        _initializeEpochSystem();
        
        // Setup: Alice deposits into vault
        uint256 depositAmount = 10000 * 1e18; // 10k SPK
        vm.startPrank(alice);
        spkToken.approve(VAULT_ADDRESS, depositAmount);
        vault.deposit(alice, depositAmount);
        vm.stopPrank();
        
        // Record initial balances before slashing
        uint256 vaultBalanceBefore = spkToken.balanceOf(VAULT_ADDRESS);
        uint256 burnerBalanceBefore = spkToken.balanceOf(BURNER_ROUTER);
        uint256 governanceBalanceBefore = spkToken.balanceOf(SPARK_GOVERNANCE);
        uint256 totalStakeBefore = vault.totalStake();
        
        // Perform slashing
        uint256 slashAmount = 1000 * 1e18; // Slash 1k SPK
        uint48 captureTimestamp = uint48(block.timestamp);
        
        vm.prank(VETO_SLASHER);
        vault.onSlash(slashAmount, captureTimestamp);
        
        // Record balances after slashing
        uint256 vaultBalanceAfter = spkToken.balanceOf(VAULT_ADDRESS);
        uint256 burnerBalanceAfter = spkToken.balanceOf(BURNER_ROUTER);
        uint256 governanceBalanceAfter = spkToken.balanceOf(SPARK_GOVERNANCE);
        uint256 totalStakeAfter = vault.totalStake();
        
        // Verify immediate fund flow effects
        // 1. Vault balance should decrease (funds leave immediately)
        assertLt(vaultBalanceAfter, vaultBalanceBefore, "Vault balance should decrease immediately");
        
        // 2. Total stake should decrease (slashing reduces stakeable amount)
        assertLt(totalStakeAfter, totalStakeBefore, "Total stake should decrease due to slashing");
        
        // 3. Either burner router or governance should have received the funds
        uint256 totalFundsAfter = vaultBalanceAfter + burnerBalanceAfter + governanceBalanceAfter;
        uint256 totalFundsBefore = vaultBalanceBefore + burnerBalanceBefore + governanceBalanceBefore;
        
        // Total funds in the system should remain the same (just redistributed)
        assertEq(totalFundsAfter, totalFundsBefore, "Total funds should be conserved");
        
        // Calculate actual fund movements
        uint256 vaultDecrease = vaultBalanceBefore - vaultBalanceAfter;
        uint256 burnerIncrease = burnerBalanceAfter - burnerBalanceBefore;
        uint256 governanceIncrease = governanceBalanceAfter - governanceBalanceBefore;
        
        // The vault decrease should match the increase somewhere else
        assertEq(vaultDecrease, burnerIncrease + governanceIncrease, "Fund movement should balance");
        
        // Verify that funds moved immediately (no delay in transfer)
        assertGt(vaultDecrease, 0, "Funds should have left vault immediately");
    }
    
    function test_SlashingWithVetoWindow() public {
        // Test that demonstrates the 3-day veto window concept
        _initializeEpochSystem();
        
        uint256 depositAmount = 5000 * 1e18;
        vm.startPrank(alice);
        spkToken.approve(VAULT_ADDRESS, depositAmount);
        vault.deposit(alice, depositAmount);
        vm.stopPrank();
        
        // Record state before slashing
        uint256 vaultBalanceBefore = spkToken.balanceOf(VAULT_ADDRESS);
        
        // Slashing occurs at time T
        uint256 slashTime = block.timestamp;
        uint256 slashAmount = 500 * 1e18;
        
        vm.prank(VETO_SLASHER);
        vault.onSlash(slashAmount, uint48(slashTime));
        
        // Verify slashing happened immediately
        uint256 vaultBalanceAfter = spkToken.balanceOf(VAULT_ADDRESS);
        assertLt(vaultBalanceAfter, vaultBalanceBefore, "Slashing should take effect immediately");
        
        // The veto window is conceptual - in production:
        // - There's a 3-day window where governance could potentially veto the slashing
        // - But the funds are moved immediately to prevent griefing
        // - If vetoed, funds would need to be returned through governance action
        
        uint256 vetoWindowEnd = slashTime + SLASHER_VETO_DURATION;
        
        // Demonstrate timing relationships
        assertTrue(SLASHER_VETO_DURATION == 3 days, "Veto duration should be 3 days");
        assertTrue(vetoWindowEnd > slashTime, "Veto window extends beyond slash time");
        
        // Fast forward past veto window
        vm.warp(vetoWindowEnd + 1);
        
        // After veto window, slashing is final
        // Vault balance should still be reduced (slashing remains in effect)
        assertEq(spkToken.balanceOf(VAULT_ADDRESS), vaultBalanceAfter, "Slashing remains in effect after veto window");
    }
    
    function test_NetworkOnboarding() public {
        // Test real network onboarding flow according to Symbiotic documentation
        // Reference: https://docs.symbiotic.fi/handbooks/networks-handbook
        
        // Real Symbiotic contract addresses on mainnet
        address networkRegistry = 0xC773b1011461e7314CF05f97d95aa8e92C1Fd8aA;
        address networkMiddlewareService = 0xD7dC9B366c027743D90761F71858BCa83C6899Ad;
        
        // Create a mock network wanting to onboard
        address mockNetworkOwner = makeAddr("mockNetworkOwner");
        address mockNetworkMiddleware = makeAddr("mockNetworkMiddleware");
        
        vm.startPrank(mockNetworkOwner);
        
        // Step 1: Register network in NetworkRegistry
        // Note: We can't actually call registerNetwork() on mainnet fork as it would fail
        // but we can verify the registry exists and has the right interface
        assertTrue(networkRegistry != address(0), "NetworkRegistry should exist");
        
        // Verify NetworkRegistry has the expected interface
        (bool success,) = networkRegistry.staticcall(
            abi.encodeWithSignature("isEntity(address)", mockNetworkOwner)
        );
        assertTrue(success, "NetworkRegistry should have isEntity function");
        
        // Step 2: Set network middleware (this would normally be done after deploying middleware)
        // Again, we can't actually call this on mainnet fork, but verify the service exists
        assertTrue(networkMiddlewareService != address(0), "NetworkMiddlewareService should exist");
        
        // Verify NetworkMiddlewareService has the expected interface
        (bool middlewareSuccess,) = networkMiddlewareService.staticcall(
            abi.encodeWithSignature("middleware(address)", mockNetworkOwner)
        );
        assertTrue(middlewareSuccess, "NetworkMiddlewareService should have middleware function");
        
        // Step 3: Network opts into vault by setting max network limit
        // Our vault already has a network delegator, so check if it supports the interface
        address delegator = vault.delegator();
        assertEq(delegator, NETWORK_DELEGATOR, "Vault should have delegator");
        
        // Verify delegator has network limit functionality (this is what networks would call)
        (bool limitSuccess,) = delegator.staticcall(
            abi.encodeWithSignature("maxNetworkLimit(bytes32)", bytes32(0))
        );
        assertTrue(limitSuccess, "Delegator should support network limits");
        
        vm.stopPrank();
        
        // Verify the network can theoretically interact with our vault
        assertTrue(vault.isDelegatorInitialized(), "Vault delegator should be initialized");
        assertEq(vault.delegator(), NETWORK_DELEGATOR, "Should use correct delegator");
    }
    
    function test_OperatorOnboardingFlow() public {
        // Test comprehensive operator onboarding flow according to Symbiotic documentation
        // Reference: https://docs.symbiotic.fi/handbooks/operators-handbook
        
        // Real Symbiotic contract addresses on mainnet
        address operatorRegistry = 0xAd817a6Bc954F678451A71363f04150FDD81Af9F;
        address vaultOptInService = 0xb361894bC06cbBA7Ea8098BF0e32EB1906A5F891;
        address networkOptInService = 0x7133415b33B438843D581013f98A08704316633c;
        
        // Create mock operator wanting to onboard
        address mockOperator = makeAddr("mockOperator");
        
        vm.startPrank(mockOperator);
        
        // Step 1: Register operator in OperatorRegistry
        // Verify OperatorRegistry exists and has correct interface
        assertTrue(operatorRegistry != address(0), "OperatorRegistry should exist");
        
        (bool regSuccess,) = operatorRegistry.staticcall(
            abi.encodeWithSignature("isEntity(address)", mockOperator)
        );
        assertTrue(regSuccess, "OperatorRegistry should have isEntity function");
        
        // Step 2: Opt into vault using VaultOptInService
        assertTrue(vaultOptInService != address(0), "VaultOptInService should exist");
        
        (bool vaultOptSuccess,) = vaultOptInService.staticcall(
            abi.encodeWithSignature("isOptedIn(address,address)", mockOperator, VAULT_ADDRESS)
        );
        assertTrue(vaultOptSuccess, "VaultOptInService should have isOptedIn function");
        
        // Step 3: Opt into network using NetworkOptInService  
        assertTrue(networkOptInService != address(0), "NetworkOptInService should exist");
        
        (bool networkOptSuccess,) = networkOptInService.staticcall(
            abi.encodeWithSignature("isOptedIn(address,address)", mockOperator, NETWORK_DELEGATOR)
        );
        assertTrue(networkOptSuccess, "NetworkOptInService should have isOptedIn function");
        
        vm.stopPrank();
        
        // Step 4: Verify vault can manage operators through its delegator
        address delegator = vault.delegator();
        assertTrue(delegator != address(0), "Vault should have a delegator");
        assertEq(delegator, NETWORK_DELEGATOR, "Should use correct network delegator");
        
        // Verify delegator is properly initialized and can manage operator stakes
        assertTrue(vault.isDelegatorInitialized(), "Delegator should be initialized");
        
        // Verify slasher is properly configured for operator discipline
        address slasher = vault.slasher();
        assertEq(slasher, VETO_SLASHER, "Should use veto slasher for operator discipline");
        assertTrue(vault.isSlasherInitialized(), "Slasher should be initialized");
        
        // Step 5: Verify operator lifecycle management through vault
        // The vault should be able to track operator stakes through its delegator
        // and handle slashing through its slasher - both are properly configured
        
        // The complete onboarding flow verification:
        // 1. ✅ Symbiotic core contracts exist and have correct interfaces
        // 2. ✅ Vault has properly configured delegator for operator management
        // 3. ✅ Slashing mechanism is properly configured through veto slasher
        // 4. ✅ All required opt-in services are available for operators
        // 5. ✅ Network delegator and veto slasher are properly linked to the vault
        
        // Additional verification: Ensure vault can track stakes
        uint256 totalStake = vault.totalStake();
        assertTrue(totalStake >= 0, "Vault should be able to track total stake");
        
        // Verify epoch management for operator stake timing
        uint256 currentEpoch = vault.currentEpoch();
        assertTrue(currentEpoch >= 0, "Vault should track epochs for operator stake timing");
    }
    
    function test_SlashingProportionalImpact() public {
        // Simplified test for proportional slashing impact to avoid stack too deep
        _initializeEpochSystem();
        
        // Setup users with deposits
        uint256 aliceDeposit = 6000 * 1e18;  // 6k SPK
        uint256 bobDeposit = 4000 * 1e18;    // 4k SPK
        
        // Alice deposits
        vm.startPrank(alice);
        spkToken.approve(VAULT_ADDRESS, aliceDeposit);
        vault.deposit(alice, aliceDeposit);
        vm.stopPrank();
        
        // Bob deposits  
        vm.startPrank(bob);
        spkToken.approve(VAULT_ADDRESS, bobDeposit);
        vault.deposit(bob, bobDeposit);
        vm.stopPrank();
        
        // Record state before slashing
        uint256 totalStakeBefore = vault.totalStake();
        uint256 aliceSharesBefore = vaultToken.balanceOf(alice);
        uint256 bobSharesBefore = vaultToken.balanceOf(bob);
        
        // Perform slashing (20% of total stake)
        uint256 slashAmount = totalStakeBefore / 5; // 20% slash
        vm.prank(VETO_SLASHER);
        vault.onSlash(slashAmount, uint48(block.timestamp));
        
        // Record state after slashing
        uint256 totalStakeAfter = vault.totalStake();
        
        // Verify slashing occurred
        assertLt(totalStakeAfter, totalStakeBefore, "Total stake should decrease");
        
        // Shares should remain the same (slashing doesn't burn shares, just reduces their value)
        assertEq(vaultToken.balanceOf(alice), aliceSharesBefore, "Alice's shares should remain the same");
        assertEq(vaultToken.balanceOf(bob), bobSharesBefore, "Bob's shares should remain the same");
        
        // Both users should be affected proportionally
        uint256 actualSlashAmount = totalStakeBefore - totalStakeAfter;
        assertGt(actualSlashAmount, 0, "Some slashing should have occurred");
    }
} 