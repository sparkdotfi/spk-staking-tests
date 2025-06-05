// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";

contract VaultInitializationTest is BaseTest {
    
    function test_VaultInitialization() public view {
        // Test basic vault properties
        assertEq(address(vault.collateral()), SPK_TOKEN, "Incorrect collateral");
        assertEq(vault.epochDuration(), EPOCH_DURATION, "Incorrect epoch duration");
        assertEq(address(vault.burner()), BURNER_ROUTER, "Incorrect burner");
        
        // Test ERC20 metadata using the vault's own interface (VaultTokenized extends ERC20)
        IERC20Metadata vaultMeta = IERC20Metadata(VAULT_ADDRESS);
        assertEq(vaultMeta.name(), "Staked Spark", "Incorrect name");
        assertEq(vaultMeta.symbol(), "sSPK", "Incorrect symbol");
        assertTrue(vault.isInitialized(), "Vault should be initialized");
    }
    
    function test_AdminRoles() public view {
        // Test that Spark Governance has all required admin roles
        // Use the standard OpenZeppelin DEFAULT_ADMIN_ROLE constant
        bytes32 defaultAdminRole = 0x00; // DEFAULT_ADMIN_ROLE is bytes32(0)
        
        // Define role constants based on OpenZeppelin AccessControl pattern
        bytes32 depositWhitelistSetRole = keccak256("DEPOSIT_WHITELIST_SET_ROLE");
        bytes32 depositorWhitelistRole = keccak256("DEPOSITOR_WHITELIST_ROLE");
        bytes32 isDepositLimitSetRole = keccak256("IS_DEPOSIT_LIMIT_SET_ROLE");
        bytes32 depositLimitSetRole = keccak256("DEPOSIT_LIMIT_SET_ROLE");
        
        assertTrue(vaultAccess.hasRole(defaultAdminRole, SPARK_GOVERNANCE), "Missing DEFAULT_ADMIN_ROLE");
        assertTrue(vaultAccess.hasRole(depositWhitelistSetRole, SPARK_GOVERNANCE), "Missing DEPOSIT_WHITELIST_SET_ROLE");
        assertTrue(vaultAccess.hasRole(depositorWhitelistRole, SPARK_GOVERNANCE), "Missing DEPOSITOR_WHITELIST_ROLE");
        assertTrue(vaultAccess.hasRole(isDepositLimitSetRole, SPARK_GOVERNANCE), "Missing IS_DEPOSIT_LIMIT_SET_ROLE");
        assertTrue(vaultAccess.hasRole(depositLimitSetRole, SPARK_GOVERNANCE), "Missing DEPOSIT_LIMIT_SET_ROLE");
    }
    
    function test_DelegatorAndSlasherAlreadySet() public view {
        // Test that delegator and slasher are already initialized
        assertTrue(vault.isDelegatorInitialized(), "Delegator should be initialized");
        assertTrue(vault.isSlasherInitialized(), "Slasher should be initialized");
        assertEq(vault.delegator(), NETWORK_DELEGATOR, "Incorrect delegator");
        assertEq(vault.slasher(), VETO_SLASHER, "Incorrect slasher");
    }
    
    function test_CannotSetDelegatorTwice() public {
        // Since delegator is already set, trying to set it again should fail
        vm.expectRevert("DelegatorAlreadyInitialized()");
        vm.prank(SPARK_GOVERNANCE);
        vault.setDelegator(makeAddr("newDelegator"));
    }
    
    function test_CannotSetSlasherTwice() public {
        // Since slasher is already set, trying to set it again should fail
        vm.expectRevert("SlasherAlreadyInitialized()");
        vm.prank(SPARK_GOVERNANCE);
        vault.setSlasher(makeAddr("newSlasher"));
    }
    
    function test_BurnerRouterConfiguration() public view {
        // Verify burner router configuration
        assertEq(address(burnerRouter.collateral()), SPK_TOKEN, "Incorrect collateral in burner router");
        assertEq(burnerRouter.globalReceiver(), SPARK_GOVERNANCE, "Incorrect global receiver");
        
        // Check delay (should be 31 days)
        assertEq(burnerRouter.delay(), BURNER_DELAY, "Incorrect burner delay");
    }
    
    function test_ERC20Functions() public view {
        // Test ERC20 interface functions using IERC20Metadata
        IERC20Metadata vaultMeta = IERC20Metadata(VAULT_ADDRESS);
        assertEq(vaultMeta.name(), "Staked Spark", "Incorrect name");
        assertEq(vaultMeta.symbol(), "sSPK", "Incorrect symbol");
        assertEq(vaultMeta.decimals(), spkTokenMeta.decimals(), "Incorrect decimals"); // Should match SPK decimals
    }
    
    function test_EpochFunctions() public {
        // Initialize epoch system first
        _initializeEpochSystem();
        
        // Record initial epoch state with precise values
        uint256 initialTimestamp = block.timestamp;
        uint256 currentEpoch = vault.currentEpoch();
        uint256 currentEpochStart = vault.currentEpochStart();
        uint256 nextEpochStart = vault.nextEpochStart();
        
        // Verify precise epoch timing relationships
        assertEq(nextEpochStart, currentEpochStart + EPOCH_DURATION, "Next epoch start should be exactly one EPOCH_DURATION after current");
        assertTrue(currentEpochStart <= initialTimestamp, "Current epoch start should not be in the future");
        assertTrue(nextEpochStart > initialTimestamp, "Next epoch start should be in the future");
        
        // Verify epoch calculation precision
        uint256 expectedCurrentEpoch = (initialTimestamp - currentEpochStart) / EPOCH_DURATION;
        assertEq(currentEpoch, expectedCurrentEpoch, "Current epoch should match calculated epoch");
        
        // Test epoch progression by advancing time to exactly the next epoch start
        vm.warp(nextEpochStart);
        uint256 newCurrentEpoch = vault.currentEpoch();
        uint256 newCurrentEpochStart = vault.currentEpochStart();
        uint256 newNextEpochStart = vault.nextEpochStart();
        
        // Verify precise epoch advancement
        assertEq(newCurrentEpoch, currentEpoch + 1, "Epoch should advance by exactly 1");
        assertEq(newCurrentEpochStart, nextEpochStart, "New current epoch start should equal previous next epoch start");
        assertEq(newNextEpochStart, nextEpochStart + EPOCH_DURATION, "New next epoch start should be exactly one EPOCH_DURATION later");
        
        // Test previousEpochStart function with precise validation
        if (newCurrentEpoch > 0) {
            uint256 previousEpochStart = vault.previousEpochStart();
            assertEq(previousEpochStart, currentEpochStart, "Previous epoch start should equal old current epoch start");
            assertEq(previousEpochStart, newCurrentEpochStart - EPOCH_DURATION, "Previous epoch start should be exactly one EPOCH_DURATION before current");
        }
        
        // Verify epoch duration consistency
        uint256 actualEpochDuration = newCurrentEpochStart - currentEpochStart;
        assertEq(actualEpochDuration, EPOCH_DURATION, "Actual epoch duration should exactly match EPOCH_DURATION constant");
        
        // Test edge case: advance time within the epoch and verify epoch doesn't change
        uint256 partialEpochTime = newNextEpochStart - 1; // 1 second before next epoch
        vm.warp(partialEpochTime);
        uint256 sameEpoch = vault.currentEpoch();
        uint256 sameEpochStart = vault.currentEpochStart();
        
        assertEq(sameEpoch, newCurrentEpoch, "Epoch should not change when advancing within same epoch");
        assertEq(sameEpochStart, newCurrentEpochStart, "Epoch start should not change when advancing within same epoch");
    }
} 