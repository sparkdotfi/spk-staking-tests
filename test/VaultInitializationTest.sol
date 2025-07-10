// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";

import { VmSafe } from "forge-std/Vm.sol";

interface INetworkDelegator is IAccessControl {}

// TODO: Add hook configuration tests after done onchain

contract VaultInitializationTest is BaseTest {

    function test_VaultInitialization() public view {
        // Test basic stSpk properties
        assertEq(address(stSpk.collateral()), SPK,            "Incorrect collateral");
        assertEq(stSpk.epochDuration(),       EPOCH_DURATION, "Incorrect epoch duration");
        assertEq(address(stSpk.burner()),     BURNER_ROUTER,  "Incorrect burner");

        assertEq(stSpk.name(),   "Staked Spark", "Incorrect name");
        assertEq(stSpk.symbol(), "stSPK",        "Incorrect symbol");

        assertTrue(stSpk.isInitialized(), "Vault should be initialized");
    }

    function test_AdminRoles() public view {
        // Test that Spark Governance has all required admin roles
        // Use the standard OpenZeppelin DEFAULT_ADMIN_ROLE constant
        bytes32 defaultAdminRole = 0x00; // DEFAULT_ADMIN_ROLE is bytes32(0)

        // Define role constants based on OpenZeppelin AccessControl pattern
        bytes32 depositWhitelistSetRole = keccak256("DEPOSIT_WHITELIST_SET_ROLE");
        bytes32 depositorWhitelistRole  = keccak256("DEPOSITOR_WHITELIST_ROLE");
        bytes32 isDepositLimitSetRole   = keccak256("IS_DEPOSIT_LIMIT_SET_ROLE");
        bytes32 depositLimitSetRole     = keccak256("DEPOSIT_LIMIT_SET_ROLE");

        assertTrue(stSpk.hasRole(defaultAdminRole,        OWNER_MULTISIG), "Missing DEFAULT_ADMIN_ROLE");
        assertTrue(stSpk.hasRole(depositWhitelistSetRole, OWNER_MULTISIG), "Missing DEPOSIT_WHITELIST_SET_ROLE");
        assertTrue(stSpk.hasRole(depositorWhitelistRole,  OWNER_MULTISIG), "Missing DEPOSITOR_WHITELIST_ROLE");
        assertTrue(stSpk.hasRole(isDepositLimitSetRole,   OWNER_MULTISIG), "Missing IS_DEPOSIT_LIMIT_SET_ROLE");
        assertTrue(stSpk.hasRole(depositLimitSetRole,     OWNER_MULTISIG), "Missing DEPOSIT_LIMIT_SET_ROLE");
    }

    function test_DelegatorAndSlasherAlreadySet() public view {
        // Test that delegator and slasher are already initialized
        assertTrue(stSpk.isDelegatorInitialized(), "Delegator should be initialized");
        assertTrue(stSpk.isSlasherInitialized(),   "Slasher should be initialized");

        assertEq(stSpk.delegator(), NETWORK_DELEGATOR, "Incorrect delegator");
        assertEq(stSpk.slasher(),   VETO_SLASHER,      "Incorrect slasher");
    }

    function test_CannotSetDelegatorTwice() public {
        // Since delegator is already set, trying to set it again should fail
        vm.expectRevert("DelegatorAlreadyInitialized()");
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setDelegator(makeAddr("newDelegator"));
    }

    function test_CannotSetSlasherTwice() public {
        // Since slasher is already set, trying to set it again should fail
        vm.expectRevert("SlasherAlreadyInitialized()");
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setSlasher(makeAddr("newSlasher"));
    }

    function test_BurnerRouterConfiguration() public view {
        // Verify burner router configuration
        assertEq(address(burnerRouter.collateral()), SPK,              "Incorrect collateral in burner router");
        assertEq(burnerRouter.globalReceiver(),      SPARK_GOVERNANCE, "Incorrect global receiver");

        // Check delay (should be 31 days)
        assertEq(burnerRouter.delay(), BURNER_DELAY, "Incorrect burner delay");
    }

    function test_ERC20Functions() public view {
        assertEq(stSpk.name(),     "Staked Spark", "Incorrect name");
        assertEq(stSpk.symbol(),   "stSPK",        "Incorrect symbol");
        assertEq(stSpk.decimals(), spk.decimals(), "Incorrect decimals");  // Should match SPK decimals
    }

    function test_EpochFunctions() public {
        // Initialize epoch system first
        _initializeEpochSystem();

        // Record initial epoch state with precise values
        uint256 initialTimestamp = block.timestamp;
        uint256 currentEpoch = stSpk.currentEpoch();
        uint256 currentEpochStart = stSpk.currentEpochStart();
        uint256 nextEpochStart = stSpk.nextEpochStart();

        // Verify precise epoch timing relationships
        assertEq(nextEpochStart, currentEpochStart + EPOCH_DURATION, "Next epoch start should be exactly one EPOCH_DURATION after current");

        assertTrue(currentEpochStart <= initialTimestamp, "Current epoch start should not be in the future");
        assertTrue(nextEpochStart > initialTimestamp,     "Next epoch start should be in the future");

        // Verify epoch calculation precision
        uint256 expectedCurrentEpoch = (initialTimestamp - currentEpochStart) / EPOCH_DURATION;
        assertEq(currentEpoch, expectedCurrentEpoch, "Current epoch should match calculated epoch");

        // Test epoch progression by advancing time to exactly the next epoch start
        vm.warp(nextEpochStart);
        uint256 newCurrentEpoch = stSpk.currentEpoch();
        uint256 newCurrentEpochStart = stSpk.currentEpochStart();
        uint256 newNextEpochStart = stSpk.nextEpochStart();

        // Verify precise epoch advancement
        assertEq(newCurrentEpoch, currentEpoch + 1,                  "Epoch should advance by exactly 1");
        assertEq(newCurrentEpochStart, nextEpochStart,               "New current epoch start should equal previous next epoch start");
        assertEq(newNextEpochStart, nextEpochStart + EPOCH_DURATION, "New next epoch start should be exactly one EPOCH_DURATION later");

        // Test previousEpochStart function with precise validation
        if (newCurrentEpoch > 0) {
            uint256 previousEpochStart = stSpk.previousEpochStart();
            assertEq(previousEpochStart, currentEpochStart,                     "Previous epoch start should equal old current epoch start");
            assertEq(previousEpochStart, newCurrentEpochStart - EPOCH_DURATION, "Previous epoch start should be exactly one EPOCH_DURATION before current");
        }

        // Verify epoch duration consistency
        uint256 actualEpochDuration = newCurrentEpochStart - currentEpochStart;
        assertEq(actualEpochDuration, EPOCH_DURATION, "Actual epoch duration should exactly match EPOCH_DURATION constant");

        // Test edge case: advance time within the epoch and verify epoch doesn't change
        uint256 partialEpochTime = newNextEpochStart - 1; // 1 second before next epoch
        vm.warp(partialEpochTime);
        uint256 sameEpoch = stSpk.currentEpoch();
        uint256 sameEpochStart = stSpk.currentEpochStart();

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

        assertTrue(networkDelegator.hasRole(defaultAdminRole,             OWNER_MULTISIG), "Missing DEFAULT_ADMIN_ROLE");
        assertTrue(networkDelegator.hasRole(setNetworkLimitRole,          OWNER_MULTISIG), "Missing NETWORK_LIMIT_SET_ROLE");
        assertTrue(networkDelegator.hasRole(setOperatorNetworkSharesRole, OWNER_MULTISIG), "Missing OPERATOR_NETWORK_SHARES_SET_ROLE");
    }

}

contract EventsTest is BaseTest {

    uint256 constant START_BLOCK = 20000000;  // June 1, 2024 - well before all deployments

    function _toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function _assertLogs(VmSafe.EthGetLogs memory log, bytes32[] memory topics) internal pure {
        for (uint256 i; i < topics.length; ++i) {
            assertEq(log.topics[i], topics[i], "topic mismatch");
        }
    }

}

contract NetworkDelegatorDeploymentEventsTest is EventsTest {

    bytes32 constant DELEGATOR_FACTORY = bytes32(uint256(uint160(0x985Ed57AF9D475f1d83c1c1c8826A0E5A34E8C7B)));

    // event sig hashes
    bytes32 private constant INITIALIZED_SIG           = keccak256("Initialized(uint64)");
    bytes32 private constant ON_SLASH_SIG              = keccak256("OnSlash(bytes32,address,uint256,uint48)");
    bytes32 private constant ROLE_GRANTED_SIG          = keccak256("RoleGranted(bytes32,address,address)");
    bytes32 private constant SET_HOOK_SIG              = keccak256("SetHook(address)");
    bytes32 private constant SET_MAX_NETWORK_LIMIT_SIG = keccak256("SetMaxNetworkLimit(bytes32,uint256)");
    bytes32 private constant SET_NETWORK_LIMIT_SIG     = keccak256("SetNetworkLimit(bytes32,uint256)");
    bytes32 private constant SET_OPERATOR_SHARES_SIG   = keccak256("SetOperatorNetworkShares(bytes32,address,uint256)");

    bytes32 private constant DEFAULT_ADMIN_ROLE               = 0x00;
    bytes32 private constant HOOK_SET_ROLE                    = keccak256("HOOK_SET_ROLE");
    bytes32 private constant NETWORK_LIMIT_SET_ROLE           = keccak256("NETWORK_LIMIT_SET_ROLE");
    bytes32 private constant OPERATOR_NETWORK_SHARES_SET_ROLE = keccak256("OPERATOR_NETWORK_SHARES_SET_ROLE");

    function test_networkDelegatorEventsInHistory() public {
        // fetch *all* logs from deploymentBlock → latest
        VmSafe.EthGetLogs[] memory allLogs = vm.eth_getLogs(
            START_BLOCK,
            block.number,
            NETWORK_DELEGATOR,
            new bytes32[](0)
        );

        assertEq(allLogs.length, 5, "Incorrect number of logs");

        bytes32 multisig = _toBytes32(OWNER_MULTISIG);

        bytes32[] memory roleGrantedTopics = new bytes32[](4);
        roleGrantedTopics[0] = ROLE_GRANTED_SIG;
        roleGrantedTopics[1] = NETWORK_LIMIT_SET_ROLE;
        roleGrantedTopics[2] = multisig;
        roleGrantedTopics[3] = DELEGATOR_FACTORY;

        _assertLogs(allLogs[0], roleGrantedTopics);

        roleGrantedTopics[1] = OPERATOR_NETWORK_SHARES_SET_ROLE;
        _assertLogs(allLogs[1], roleGrantedTopics);

        roleGrantedTopics[1] = DEFAULT_ADMIN_ROLE;
        _assertLogs(allLogs[2], roleGrantedTopics);

        assertEq(allLogs[4].topics[0],     INITIALIZED_SIG);
        assertEq(allLogs[4].topics.length, 1);
    }

}

contract BurnerRouterDeploymentEventsTest is EventsTest {

    // BURNER_ROUTER event signatures
    bytes32 private constant INITIALIZED_SIG           = keccak256("Initialized(uint64)");
    bytes32 private constant OWNERSHIP_TRANSFERRED_SIG = keccak256("OwnershipTransferred(address,address)");

    function test_burnerRouterEventsInHistory() public {
        // Fetch *all* logs from deploymentBlock → latest
        VmSafe.EthGetLogs[] memory allLogs = vm.eth_getLogs(
            START_BLOCK,
            block.number,
            BURNER_ROUTER,
            new bytes32[](0)
        );

        assertEq(allLogs.length, 2, "Incorrect number of logs");

        bytes32 multisig = _toBytes32(OWNER_MULTISIG);

        bytes32[] memory ownershipTransferredTopics = new bytes32[](3);
        ownershipTransferredTopics[0] = OWNERSHIP_TRANSFERRED_SIG;
        ownershipTransferredTopics[1] = _toBytes32(address(0));
        ownershipTransferredTopics[2] = multisig;

        _assertLogs(allLogs[0], ownershipTransferredTopics);

        assertEq(allLogs[1].topics[0],     INITIALIZED_SIG);
        assertEq(allLogs[1].topics.length, 1);
    }

}

contract StakedSPKVaultDeploymentEventsTest is EventsTest {

    // SPK_VAULT event signatures
    bytes32 private constant ADMIN_CHANGED_SIG         = keccak256("AdminChanged(address,address)");
    bytes32 private constant DEPOSIT_SIG               = keccak256("Deposit(address,address,uint256,uint256)");
    bytes32 private constant INITIALIZED_SIG           = keccak256("Initialized(uint64)");
    bytes32 private constant OWNERSHIP_TRANSFERRED_SIG = keccak256("OwnershipTransferred(address,address)");
    bytes32 private constant ROLE_GRANTED_SIG          = keccak256("RoleGranted(bytes32,address,address)");
    bytes32 private constant SET_DELEGATOR_SIG         = keccak256("SetDelegator(address)");
    bytes32 private constant SET_SLASHER_SIG           = keccak256("SetSlasher(address)");
    bytes32 private constant TRANSFER_SIG              = keccak256("Transfer(address,address,uint256)");
    bytes32 private constant UPGRADED_SIG              = keccak256("Upgraded(address)");
    bytes32 private constant WITHDRAW_SIG              = keccak256("Withdraw(address,address,uint256,uint256,uint256)");

    bytes32 private constant DEFAULT_ADMIN_ROLE         = 0x00;
    bytes32 private constant DEPOSIT_LIMIT_SET_ROLE     = keccak256("DEPOSIT_LIMIT_SET_ROLE");
    bytes32 private constant DEPOSIT_WHITELIST_SET_ROLE = keccak256("DEPOSIT_WHITELIST_SET_ROLE");
    bytes32 private constant DEPOSITOR_WHITELIST_ROLE   = keccak256("DEPOSITOR_WHITELIST_ROLE");
    bytes32 private constant IS_DEPOSIT_LIMIT_SET_ROLE  = keccak256("IS_DEPOSIT_LIMIT_SET_ROLE");

    function test_spkVaultEventsInHistory() public {
        // fetch *all* logs from deploymentBlock → latest
        VmSafe.EthGetLogs[] memory allLogs = vm.eth_getLogs(
            START_BLOCK,
            block.number,
            STAKED_SPK_VAULT,
            new bytes32[](0)
        );

        bytes32 multisig     = _toBytes32(OWNER_MULTISIG);
        bytes32 vaultFactory = _toBytes32(0xAEb6bdd95c502390db8f52c8909F703E9Af6a346);

        bytes32[] memory upgradedTopics = new bytes32[](2);
        upgradedTopics[0] = UPGRADED_SIG;
        upgradedTopics[1] = 0x0000000000000000000000005a0dc8e73d6846f12630b8f7d5197fa8cf669cfe;

        _assertLogs(allLogs[0], upgradedTopics);

        bytes32[] memory ownershipTransferredTopics = new bytes32[](3);
        ownershipTransferredTopics[0] = OWNERSHIP_TRANSFERRED_SIG;
        ownershipTransferredTopics[1] = _toBytes32(address(0));
        ownershipTransferredTopics[2] = multisig;

        _assertLogs(allLogs[1], ownershipTransferredTopics);

        bytes32[] memory roleGrantedTopics1 = new bytes32[](4);
        roleGrantedTopics1[0] = ROLE_GRANTED_SIG;
        roleGrantedTopics1[1] = DEFAULT_ADMIN_ROLE;
        roleGrantedTopics1[2] = multisig;
        roleGrantedTopics1[3] = vaultFactory;

        _assertLogs(allLogs[2], roleGrantedTopics1);

        bytes32[] memory roleGrantedTopics2 = new bytes32[](4);
        roleGrantedTopics2[0] = ROLE_GRANTED_SIG;
        roleGrantedTopics2[1] = DEPOSIT_WHITELIST_SET_ROLE;
        roleGrantedTopics2[2] = multisig;
        roleGrantedTopics2[3] = vaultFactory;

        _assertLogs(allLogs[3], roleGrantedTopics2);

        bytes32[] memory roleGrantedTopics3 = new bytes32[](4);
        roleGrantedTopics3[0] = ROLE_GRANTED_SIG;
        roleGrantedTopics3[1] = DEPOSITOR_WHITELIST_ROLE;
        roleGrantedTopics3[2] = multisig;
        roleGrantedTopics3[3] = vaultFactory;

        _assertLogs(allLogs[4], roleGrantedTopics3);

        bytes32[] memory roleGrantedTopics4 = new bytes32[](4);
        roleGrantedTopics4[0] = ROLE_GRANTED_SIG;
        roleGrantedTopics4[1] = IS_DEPOSIT_LIMIT_SET_ROLE;
        roleGrantedTopics4[2] = multisig;
        roleGrantedTopics4[3] = vaultFactory;

        _assertLogs(allLogs[5], roleGrantedTopics4);

        bytes32[] memory roleGrantedTopics5 = new bytes32[](4);
        roleGrantedTopics5[0] = ROLE_GRANTED_SIG;
        roleGrantedTopics5[1] = DEPOSIT_LIMIT_SET_ROLE;
        roleGrantedTopics5[2] = multisig;
        roleGrantedTopics5[3] = vaultFactory;

        _assertLogs(allLogs[6], roleGrantedTopics5);

        assertEq(allLogs[7].topics[0],     INITIALIZED_SIG);
        assertEq(allLogs[7].topics.length, 1);

        assertEq(allLogs[8].topics[0],     ADMIN_CHANGED_SIG);
        assertEq(allLogs[8].topics.length, 1);

        bytes32[] memory setDelegatorTopics = new bytes32[](2);
        setDelegatorTopics[0] = SET_DELEGATOR_SIG;
        setDelegatorTopics[1] = _toBytes32(NETWORK_DELEGATOR);

        _assertLogs(allLogs[9], setDelegatorTopics);

        bytes32[] memory setSlasherTopics = new bytes32[](2);
        setSlasherTopics[0] = SET_SLASHER_SIG;
        setSlasherTopics[1] = _toBytes32(VETO_SLASHER);

        _assertLogs(allLogs[10], setSlasherTopics);

        // scan them for all SPK_VAULT event signatures
        for (uint i = 11; i < allLogs.length; i++) {
            bytes32 sig = allLogs[i].topics[0];
            assertTrue(
                sig == TRANSFER_SIG ||
                sig == DEPOSIT_SIG ||
                sig == WITHDRAW_SIG,
                "Unknown SPK_VAULT event found!"
            );
        }
    }

}

contract VetoSlasherDeploymentEventsTest is EventsTest {

    // VETO_SLASHER event signatures
    bytes32 private constant INITIALIZED_SIG =
        keccak256("Initialized(uint64)");

    function test_vetoSlasherEventsInHistory() public {
        // fetch *all* logs from deploymentBlock → latest
        VmSafe.EthGetLogs[] memory allLogs = vm.eth_getLogs(
            START_BLOCK,
            block.number,
            VETO_SLASHER,
            new bytes32[](0)
        );

        assertEq(allLogs.length, 1, "Incorrect number of logs");

        assertEq(allLogs[0].topics[0],     INITIALIZED_SIG);
        assertEq(allLogs[0].topics.length, 1);
    }

}
