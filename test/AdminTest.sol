// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";

contract SetIsDepositLimitFailureTests is BaseTest {

    function test_setIsDepositLimit_notRole() public {
        bytes32 depositLimitSetRole = keccak256("IS_DEPOSIT_LIMIT_SET_ROLE");
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                alice,
                depositLimitSetRole
            )
        );
        vm.prank(alice);
        sSpk.setIsDepositLimit(true);
    }

    function test_setIsDepositLimit_alreadySet() public {
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setIsDepositLimit(true);

        vm.expectRevert("AlreadySet()");
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setIsDepositLimit(true);

        // Can set a new value if it's different from the previous value
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setIsDepositLimit(false);
        assertFalse(sSpk.isDepositLimit(), "Deposit limit enabled");
    }

}

contract SetIsDepositLimitSuccessTests is BaseTest {

    event SetIsDepositLimit(bool status);

    function test_setIsDepositLimit() public {
        vm.prank(SPARK_GOVERNANCE);
        vm.expectEmit(address(sSpk));
        emit SetIsDepositLimit(true);
        sSpk.setIsDepositLimit(true);

        assertTrue(sSpk.isDepositLimit(), "Deposit limit not enabled");
    }

}

contract SetDepositLimitFailureTests is BaseTest {

    function test_setDepositLimit_notRole() public {
        bytes32 depositLimitSetRole = keccak256("DEPOSIT_LIMIT_SET_ROLE");
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                alice,
                depositLimitSetRole
            )
        );
        vm.prank(alice);
        sSpk.setDepositLimit(1_000_000e18);
    }

    function test_setDepositLimit_alreadySet() public {
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setDepositLimit(1_000_000e18);

        vm.expectRevert("AlreadySet()");
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setDepositLimit(1_000_000e18);

        // Can set a new deposit limit if it's different from the previous limit
        uint256 newLimit2 = 2_000_000e18; // 2M SPK limit
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setDepositLimit(newLimit2);
        assertEq(sSpk.depositLimit(), newLimit2, "Deposit limit not set correctly");
    }

}

contract SetDepositLimitSuccessTests is BaseTest {

    event SetDepositLimit(uint256 limit);

    function test_setIsDepositLimit() public {
        uint256 newLimit = 1_000_000e18; // 1M SPK limit

        vm.prank(SPARK_GOVERNANCE);
        vm.expectEmit(address(sSpk));
        emit SetDepositLimit(newLimit);
        sSpk.setDepositLimit(newLimit);

        assertEq(sSpk.depositLimit(), newLimit, "Deposit limit not set correctly");
    }

}

contract SetDepositWhitelistFailureTests is BaseTest {

    function test_setDepositWhitelist_notRole() public {
        bytes32 depositWhitelistSetRole = keccak256("DEPOSIT_WHITELIST_SET_ROLE");
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                alice,
                depositWhitelistSetRole
            )
        );
        vm.prank(alice);
        sSpk.setDepositWhitelist(true);
    }

    function test_setDepositWhitelist_alreadySet() public {
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setDepositWhitelist(true);

        vm.expectRevert("AlreadySet()");
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setDepositWhitelist(true);

        // Can set a new value if it's different from the previous value
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setDepositWhitelist(false);
        assertFalse(sSpk.depositWhitelist(), "Deposit whitelist not disabled");
    }

}

contract SetDepositWhitelistSuccessTests is BaseTest {

    event SetDepositWhitelist(bool status);

    function test_setDepositWhitelist() public {
        vm.prank(SPARK_GOVERNANCE);
        vm.expectEmit(address(sSpk));
        emit SetDepositWhitelist(true);
        sSpk.setDepositWhitelist(true);

        assertTrue(sSpk.depositWhitelist(), "Deposit whitelist not enabled");
    }

}

contract SetDepositorWhitelistStatusFailureTests is BaseTest {

    function test_setDepositorWhitelistStatus_notRole() public {
        bytes32 depositorWhitelistSetRole = keccak256("DEPOSITOR_WHITELIST_ROLE");
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                alice,
                depositorWhitelistSetRole
            )
        );
        vm.prank(alice);
        sSpk.setDepositorWhitelistStatus(alice, true);
    }

    function test_setDepositorWhitelistStatus_invalidAccount() public {
        vm.expectRevert("InvalidAccount()");
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setDepositorWhitelistStatus(address(0), true);
    }

    function test_setDepositorWhitelistStatus_alreadySet() public {
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setDepositorWhitelistStatus(alice, true);

        vm.expectRevert("AlreadySet()");
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setDepositorWhitelistStatus(alice, true);

        // Can set a new value if it's different from the previous value
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setDepositorWhitelistStatus(alice, false);

        assertFalse(sSpk.isDepositorWhitelisted(alice), "Alice not whitelisted");
    }

}

contract SetDepositorWhitelistStatusSuccessTests is BaseTest {

    event SetDepositorWhitelistStatus(address indexed account, bool status);

    function test_setDepositorWhitelistStatus() public {
        vm.prank(SPARK_GOVERNANCE);
        vm.expectEmit(address(sSpk));
        emit SetDepositorWhitelistStatus(alice, true);
        sSpk.setDepositorWhitelistStatus(alice, true);

        assertTrue(sSpk.isDepositorWhitelisted(alice), "Alice not whitelisted");

        // Should whitelist a new user
        vm.prank(SPARK_GOVERNANCE);
        sSpk.setDepositorWhitelistStatus(bob, true);

        assertTrue(sSpk.isDepositorWhitelisted(bob), "Bob not whitelisted");
    }

}

contract TestBurnerRouterSetGlobalReceiverFailureTests is BaseTest {

    function test_setGlobalReceiver_notRole() public {
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice)
        );
        vm.prank(alice);
        burnerRouter.setGlobalReceiver(alice);
    }

    function test_setGlobalReceiver_alreadySet() public {
        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setGlobalReceiver(alice);

        vm.warp(block.timestamp + BURNER_DELAY + 1);

        // Now accept the receiver change
        burnerRouter.acceptGlobalReceiver();

        vm.expectRevert("AlreadySet()");
        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setGlobalReceiver(alice);

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setGlobalReceiver(bob);

        vm.warp(block.timestamp + BURNER_DELAY + 1);

        // Now accept the receiver change
        burnerRouter.acceptGlobalReceiver();

        // Verify the receiver has been changed
        assertEq(burnerRouter.globalReceiver(), bob, "Receiver should be updated after delay");
    }

}

contract TestBurnerRouterSetGlobalReceiverSuccessTests is BaseTest {

    function test_setGlobalReceiver() public {
        address currentReceiver = burnerRouter.globalReceiver();
        assertEq(currentReceiver, SPARK_GOVERNANCE, "Current receiver should be Spark Governance");

        address newReceiver = makeAddr("newReceiver");

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setGlobalReceiver(newReceiver);

        // Current receiver should still be the old one
        assertEq(burnerRouter.globalReceiver(), currentReceiver, "Receiver should not change immediately");

        // Fast forward past the 31-day delay
        vm.warp(block.timestamp + BURNER_DELAY + 1);

        // Now accept the receiver change
        burnerRouter.acceptGlobalReceiver();

        // Verify the receiver has been changed
        assertEq(burnerRouter.globalReceiver(), newReceiver, "Receiver should be updated after delay");

        // The key point: users have 28 days (2 epochs) to unstake if they disagree
        // The 31-day delay ensures they have time to complete unstaking before changes take effect
        uint256 unstakingTime = 2 * EPOCH_DURATION; // 28 days
        assertTrue(BURNER_DELAY > unstakingTime, "Burner delay should be longer than unstaking time");
    }

}

contract TestBurnerRouterOwnershipTest is BaseTest {

    function test_BurnerRouterOwnership() public view {
        // Test that Spark Governance is the actual owner of the burner router
        address owner = OwnableUpgradeable(address(burnerRouter)).owner();
        assertEq(owner, SPARK_GOVERNANCE, "Spark Governance should be the owner of burner router");
    }

}

contract TestBurnerRouterSetDelayFailureTests is BaseTest {

    function test_setDelay_notRole() public {
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice)
        );
        vm.prank(alice);
        burnerRouter.setDelay(15 days);
    }

    function test_setDelay_alreadySet() public {
        uint48 initialDelay = burnerRouter.delay();
        uint48 newDelay = 15 days; // Change from 31 days to 15 days

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setDelay(newDelay);

        vm.warp(block.timestamp + initialDelay + 1);

        burnerRouter.acceptDelay();

        vm.expectRevert("AlreadySet()");
        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setDelay(newDelay);

        // Can set a new delay if it's different from the previous delay
        uint48 newDelay2 = 10 days;
        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setDelay(newDelay2);

        vm.warp(block.timestamp + initialDelay + 1);

        burnerRouter.acceptDelay();

        assertEq(burnerRouter.delay(), newDelay2, "Delay should be updated to new value");
    }

}

contract TestBurnerRouterSetDelaySuccessTests is BaseTest {

    function test_setDelay() public {
        uint48 newDelay = 15 days; // Change from 31 days to 15 days

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setDelay(newDelay);

        ( uint48 pendingDelay, ) = burnerRouter.pendingDelay();

        assertEq(pendingDelay, newDelay, "Delay should be updated to new value");
    }

}

contract TestBurnerRouterAcceptDelayFailureTests is BaseTest {

    function test_setDelay_notReady() public {
        uint48 newDelay = 15 days; // Change from 31 days to 15 days

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setDelay(newDelay);

        vm.expectRevert("NotReady()");
        burnerRouter.acceptDelay();
    }

}

contract TestBurnerRouterAcceptDelaySuccessTests is BaseTest {

    function test_acceptDelay() public {
        // Check initial delay (should be 31 days)
        uint48 initialDelay = burnerRouter.delay();
        assertEq(initialDelay, BURNER_DELAY, "Initial delay should be 31 days");

        // Test that owner (Spark Governance) can initiate delay change
        uint48 newDelay = 15 days; // Change from 31 days to 15 days

        // Get the owner of the burner router to verify it's Spark Governance
        address burnerOwner = OwnableUpgradeable(address(burnerRouter)).owner();

        // Note: The actual owner might be a different address than SPARK_GOVERNANCE
        // so we'll use the actual owner for the test
        vm.prank(burnerOwner);
        burnerRouter.setDelay(newDelay);

        // Check that delay is still the old value (change is pending)
        assertEq(burnerRouter.delay(), initialDelay, "Delay should still be old value while pending");

        // Fast forward past the delay period (initial delay + 1)
        vm.warp(block.timestamp + initialDelay + 1);

        // Now accept the delay change
        burnerRouter.acceptDelay();

        // Verify the delay has been changed
        assertEq(burnerRouter.delay(), newDelay, "Delay should be updated to new value");
    }

}

contract TestBurnerRouterSetNetworkReceiverFailureTests is BaseTest {

    function test_setNetworkReceiver_notRole() public {
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice)
        );
        vm.prank(alice);
        burnerRouter.setNetworkReceiver(makeAddr("network"), alice);
    }

    function test_setGlobalReceiver_alreadySet() public {
        address network = makeAddr("network");

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setNetworkReceiver(network, alice);

        vm.warp(block.timestamp + BURNER_DELAY + 1);

        burnerRouter.acceptNetworkReceiver(network);

        vm.expectRevert("AlreadySet()");
        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setNetworkReceiver(network, alice);

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setNetworkReceiver(network, bob);

        vm.warp(block.timestamp + BURNER_DELAY + 1);

        // Now accept the receiver change
        burnerRouter.acceptNetworkReceiver(network);

        // Verify the receiver has been changed
        assertEq(burnerRouter.networkReceiver(network), bob, "Receiver should be updated after delay");
    }

}

contract TestBurnerRouterSetNetworkReceiverSuccessTests is BaseTest {

    function test_setNetworkReceiver() public {
        address network = makeAddr("network");

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setNetworkReceiver(network, alice);

        // Fast forward past the 31-day delay
        vm.warp(block.timestamp + BURNER_DELAY + 1);

        // Now accept the receiver change
        burnerRouter.acceptNetworkReceiver(network);

        // Verify the receiver has been changed
        assertEq(burnerRouter.networkReceiver(network), alice, "Receiver should be updated after delay");
    }

}

contract TestBurnerRouterSetOperatorNetworkReceiverFailureTests is BaseTest {

    function test_setOperatorNetworkReceiver_notRole() public {
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice)
        );
        vm.prank(alice);
        burnerRouter.setOperatorNetworkReceiver(makeAddr("network"), makeAddr("operator"), alice);
    }

    function test_setOperatorNetworkReceiver_alreadySet() public {
        address network = makeAddr("network");
        address operator = makeAddr("operator");

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setOperatorNetworkReceiver(network, operator, alice);

        vm.warp(block.timestamp + BURNER_DELAY + 1);

        burnerRouter.acceptOperatorNetworkReceiver(network, operator);

        vm.expectRevert("AlreadySet()");
        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setOperatorNetworkReceiver(network, operator, alice);

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setOperatorNetworkReceiver(network, operator, bob);

        vm.warp(block.timestamp + BURNER_DELAY + 1);

        // Now accept the receiver change
        burnerRouter.acceptOperatorNetworkReceiver(network, operator);

        // Verify the receiver has been changed
        assertEq(burnerRouter.operatorNetworkReceiver(network, operator), bob, "Receiver should be updated after delay");
    }

}

contract TestBurnerRouterSetOperatorNetworkReceiverSuccessTests is BaseTest {

    function test_setOperatorNetworkReceiver() public {
        address network = makeAddr("network");
        address operator = makeAddr("operator");

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setOperatorNetworkReceiver(network, operator, alice);

        // Fast forward past the 31-day delay
        vm.warp(block.timestamp + BURNER_DELAY + 1);

        // Now accept the receiver change
        burnerRouter.acceptOperatorNetworkReceiver(network, operator);

        // Verify the receiver has been changed
        assertEq(burnerRouter.operatorNetworkReceiver(network, operator), alice, "Receiver should be updated after delay");
    }

}
