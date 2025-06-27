// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";

import { VmSafe } from "forge-std/Vm.sol";

interface INetworkDelegator is IAccessControl {}

// TODO: Add hook configuration tests after done onchain

contract VaultInitializationTest is BaseTest {

    function test_VaultInitialization() public view {
        // Test basic sSpk properties
        assertEq(address(sSpk.collateral()), SPK,            "Incorrect collateral");
        assertEq(sSpk.epochDuration(),       EPOCH_DURATION, "Incorrect epoch duration");
        assertEq(address(sSpk.burner()),     BURNER_ROUTER,  "Incorrect burner");

        assertEq(sSpk.name(),   "Staked Spark", "Incorrect name");
        assertEq(sSpk.symbol(), "stSPK",        "Incorrect symbol");

        assertTrue(sSpk.isInitialized(), "Vault should be initialized");
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

        assertTrue(sSpk.hasRole(defaultAdminRole, OWNER_MULTISIG),        "Missing DEFAULT_ADMIN_ROLE");
        assertTrue(sSpk.hasRole(depositWhitelistSetRole, OWNER_MULTISIG), "Missing DEPOSIT_WHITELIST_SET_ROLE");
        assertTrue(sSpk.hasRole(depositorWhitelistRole, OWNER_MULTISIG),  "Missing DEPOSITOR_WHITELIST_ROLE");
        assertTrue(sSpk.hasRole(isDepositLimitSetRole, OWNER_MULTISIG),   "Missing IS_DEPOSIT_LIMIT_SET_ROLE");
        assertTrue(sSpk.hasRole(depositLimitSetRole, OWNER_MULTISIG),     "Missing DEPOSIT_LIMIT_SET_ROLE");
    }

    function test_DelegatorAndSlasherAlreadySet() public view {
        // Test that delegator and slasher are already initialized
        assertTrue(sSpk.isDelegatorInitialized(), "Delegator should be initialized");
        assertTrue(sSpk.isSlasherInitialized(),   "Slasher should be initialized");

        assertEq(sSpk.delegator(), NETWORK_DELEGATOR, "Incorrect delegator");
        assertEq(sSpk.slasher(),   VETO_SLASHER,      "Incorrect slasher");
    }

    function test_CannotSetDelegatorTwice() public {
        // Since delegator is already set, trying to set it again should fail
        vm.expectRevert("DelegatorAlreadyInitialized()");
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setDelegator(makeAddr("newDelegator"));
    }

    function test_CannotSetSlasherTwice() public {
        // Since slasher is already set, trying to set it again should fail
        vm.expectRevert("SlasherAlreadyInitialized()");
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setSlasher(makeAddr("newSlasher"));
    }

    function test_BurnerRouterConfiguration() public view {
        // Verify burner router configuration
        assertEq(address(burnerRouter.collateral()), SPK,              "Incorrect collateral in burner router");
        assertEq(burnerRouter.globalReceiver(),      SPARK_GOVERNANCE, "Incorrect global receiver");

        // Check delay (should be 31 days)
        assertEq(burnerRouter.delay(), BURNER_DELAY, "Incorrect burner delay");
    }

    function test_ERC20Functions() public view {
        assertEq(sSpk.name(),     "Staked Spark", "Incorrect name");
        assertEq(sSpk.symbol(),   "stSPK",        "Incorrect symbol");
        assertEq(sSpk.decimals(), spk.decimals(), "Incorrect decimals");  // Should match SPK decimals
    }

    function test_EpochFunctions() public {
        // Initialize epoch system first
        _initializeEpochSystem();

        // Record initial epoch state with precise values
        uint256 initialTimestamp = block.timestamp;
        uint256 currentEpoch = sSpk.currentEpoch();
        uint256 currentEpochStart = sSpk.currentEpochStart();
        uint256 nextEpochStart = sSpk.nextEpochStart();

        // Verify precise epoch timing relationships
        assertEq(nextEpochStart, currentEpochStart + EPOCH_DURATION, "Next epoch start should be exactly one EPOCH_DURATION after current");

        assertTrue(currentEpochStart <= initialTimestamp, "Current epoch start should not be in the future");
        assertTrue(nextEpochStart > initialTimestamp,     "Next epoch start should be in the future");

        // Verify epoch calculation precision
        uint256 expectedCurrentEpoch = (initialTimestamp - currentEpochStart) / EPOCH_DURATION;
        assertEq(currentEpoch, expectedCurrentEpoch, "Current epoch should match calculated epoch");

        // Test epoch progression by advancing time to exactly the next epoch start
        vm.warp(nextEpochStart);
        uint256 newCurrentEpoch = sSpk.currentEpoch();
        uint256 newCurrentEpochStart = sSpk.currentEpochStart();
        uint256 newNextEpochStart = sSpk.nextEpochStart();

        // Verify precise epoch advancement
        assertEq(newCurrentEpoch, currentEpoch + 1,                  "Epoch should advance by exactly 1");
        assertEq(newCurrentEpochStart, nextEpochStart,               "New current epoch start should equal previous next epoch start");
        assertEq(newNextEpochStart, nextEpochStart + EPOCH_DURATION, "New next epoch start should be exactly one EPOCH_DURATION later");

        // Test previousEpochStart function with precise validation
        if (newCurrentEpoch > 0) {
            uint256 previousEpochStart = sSpk.previousEpochStart();
            assertEq(previousEpochStart, currentEpochStart,                     "Previous epoch start should equal old current epoch start");
            assertEq(previousEpochStart, newCurrentEpochStart - EPOCH_DURATION, "Previous epoch start should be exactly one EPOCH_DURATION before current");
        }

        // Verify epoch duration consistency
        uint256 actualEpochDuration = newCurrentEpochStart - currentEpochStart;
        assertEq(actualEpochDuration, EPOCH_DURATION, "Actual epoch duration should exactly match EPOCH_DURATION constant");

        // Test edge case: advance time within the epoch and verify epoch doesn't change
        uint256 partialEpochTime = newNextEpochStart - 1; // 1 second before next epoch
        vm.warp(partialEpochTime);
        uint256 sameEpoch = sSpk.currentEpoch();
        uint256 sameEpochStart = sSpk.currentEpochStart();

        assertEq(sameEpoch,      newCurrentEpoch,      "Epoch should not change when advancing within same epoch");
        assertEq(sameEpochStart, newCurrentEpochStart, "Epoch start should not change when advancing within same epoch");
    }

    function test_networkDelegator_configuration() public view {
        INetworkDelegator networkDelegator = INetworkDelegator(NETWORK_DELEGATOR);

        // Test that Spark Governance has all required admin roles
        // Use the standard OpenZeppelin DEFAULT_ADMIN_ROLE constant
        bytes32 defaultAdminRole = 0x00; // DEFAULT_ADMIN_ROLE is bytes32(0)

        // Define role constants based on OpenZeppelin AccessControl pattern
        bytes32 setNetworkLimitRole          = keccak256("NETWORK_LIMIT_SET_ROLE");
        bytes32 setOperatorNetworkSharesRole = keccak256("OPERATOR_NETWORK_SHARES_SET_ROLE");

        assertTrue(networkDelegator.hasRole(defaultAdminRole, OWNER_MULTISIG),             "Missing DEFAULT_ADMIN_ROLE");
        assertTrue(networkDelegator.hasRole(setNetworkLimitRole, OWNER_MULTISIG),          "Missing DEPOSIT_WHITELIST_SET_ROLE");
        assertTrue(networkDelegator.hasRole(setOperatorNetworkSharesRole, OWNER_MULTISIG), "Missing DEPOSITOR_WHITELIST_ROLE");
    }

}

contract HistoricalLogsTest is BaseTest {

    // event sig hashes
    bytes32 private constant SET_NETWORK_LIMIT_SIG =
        keccak256("SetNetworkLimit(bytes32,uint256)");
    bytes32 private constant SET_OPERATOR_SHARES_SIG =
        keccak256("SetOperatorNetworkShares(bytes32,address,uint256)");

    function test_noConfigEventsInHistory() public {
        // fetch *all* logs from deploymentBlock → latest
        uint256 deploymentBlock = 22624651;
        VmSafe.EthGetLogs[] memory allLogs = vm.eth_getLogs(
            deploymentBlock,
            block.number,
            NETWORK_DELEGATOR,
            new bytes32[](0)
        );

        // scan them for our forbidden event signatures
        for (uint i = 0; i < allLogs.length; i++) {
            bytes32 sig = allLogs[i].topics[0];
            assertTrue(
                sig != SET_NETWORK_LIMIT_SIG,
                "historic SetNetworkLimit found!"
            );
            assertTrue(
                sig != SET_OPERATOR_SHARES_SIG,
                "historic SetOperatorNetworkShares found!"
            );
        }
    }

}