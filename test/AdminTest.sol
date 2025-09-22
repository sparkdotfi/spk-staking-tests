// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";

contract OwnershipTransferTest is BaseTest {

    function test_ownershipTransfer() public {
        _testOwnershipTransfer();
    }

}

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
        stSpk.setIsDepositLimit(true);
    }

    function test_setIsDepositLimit_alreadySet() public {
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setIsDepositLimit(true);

        vm.expectRevert("AlreadySet()");
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setIsDepositLimit(true);

        // Can set a new value if it's different from the previous value
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setIsDepositLimit(false);
        assertFalse(stSpk.isDepositLimit(), "Deposit limit enabled");
    }

}

contract SetIsDepositLimitSuccessTests is BaseTest {

    event SetIsDepositLimit(bool status);

    function test_setIsDepositLimit() public {
        vm.prank(SPARK_GOVERNANCE);
        vm.expectEmit(address(stSpk));
        emit SetIsDepositLimit(true);
        stSpk.setIsDepositLimit(true);

        assertTrue(stSpk.isDepositLimit(), "Deposit limit not enabled");
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
        stSpk.setDepositLimit(1_000_000e18);
    }

    function test_setDepositLimit_alreadySet() public {
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setDepositLimit(1_000_000e18);

        vm.expectRevert("AlreadySet()");
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setDepositLimit(1_000_000e18);

        // Can set a new deposit limit if it's different from the previous limit
        uint256 newLimit2 = 2_000_000e18; // 2M SPK limit
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setDepositLimit(newLimit2);
        assertEq(stSpk.depositLimit(), newLimit2, "Deposit limit not set correctly");
    }

}

contract SetDepositLimitSuccessTests is BaseTest {

    event SetDepositLimit(uint256 limit);

    function test_setIsDepositLimit() public {
        uint256 newLimit = 1_000_000e18; // 1M SPK limit

        vm.prank(SPARK_GOVERNANCE);
        vm.expectEmit(address(stSpk));
        emit SetDepositLimit(newLimit);
        stSpk.setDepositLimit(newLimit);

        assertEq(stSpk.depositLimit(), newLimit, "Deposit limit not set correctly");
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
        stSpk.setDepositWhitelist(true);
    }

    function test_setDepositWhitelist_alreadySet() public {
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setDepositWhitelist(true);

        vm.expectRevert("AlreadySet()");
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setDepositWhitelist(true);

        // Can set a new value if it's different from the previous value
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setDepositWhitelist(false);
        assertFalse(stSpk.depositWhitelist(), "Deposit whitelist not disabled");
    }

}

contract SetDepositWhitelistSuccessTests is BaseTest {

    event SetDepositWhitelist(bool status);

    function test_setDepositWhitelist() public {
        vm.prank(SPARK_GOVERNANCE);
        vm.expectEmit(address(stSpk));
        emit SetDepositWhitelist(true);
        stSpk.setDepositWhitelist(true);

        assertTrue(stSpk.depositWhitelist(), "Deposit whitelist not enabled");
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
        stSpk.setDepositorWhitelistStatus(alice, true);
    }

    function test_setDepositorWhitelistStatus_invalidAccount() public {
        vm.expectRevert("InvalidAccount()");
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setDepositorWhitelistStatus(address(0), true);
    }

    function test_setDepositorWhitelistStatus_alreadySet() public {
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setDepositorWhitelistStatus(alice, true);

        vm.expectRevert("AlreadySet()");
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setDepositorWhitelistStatus(alice, true);

        // Can set a new value if it's different from the previous value
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setDepositorWhitelistStatus(alice, false);

        assertFalse(stSpk.isDepositorWhitelisted(alice), "Alice not whitelisted");
    }

}

contract SetDepositorWhitelistStatusSuccessTests is BaseTest {

    event SetDepositorWhitelistStatus(address indexed account, bool status);

    function test_setDepositorWhitelistStatus() public {
        vm.prank(SPARK_GOVERNANCE);
        vm.expectEmit(address(stSpk));
        emit SetDepositorWhitelistStatus(alice, true);
        stSpk.setDepositorWhitelistStatus(alice, true);

        assertTrue(stSpk.isDepositorWhitelisted(alice), "Alice not whitelisted");

        // Should whitelist a new user
        vm.prank(SPARK_GOVERNANCE);
        stSpk.setDepositorWhitelistStatus(bob, true);

        assertTrue(stSpk.isDepositorWhitelisted(bob), "Bob not whitelisted");
    }

}

contract BurnerRouterSetGlobalReceiverFailureTests is BaseTest {

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

        ( address pendingGlobalReceiver, ) = burnerRouter.pendingGlobalReceiver();

        assertEq(pendingGlobalReceiver, bob, "Global receiver should be updated after delay");
    }

}

contract BurnerRouterSetGlobalReceiverSuccessTests is BaseTest {

    function test_setGlobalReceiver() public {
        address currentReceiver = burnerRouter.globalReceiver();
        assertEq(currentReceiver, SPARK_GOVERNANCE, "Current receiver should be Spark Governance");

        address newReceiver = makeAddr("newReceiver");

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setGlobalReceiver(newReceiver);

        // Current receiver should still be the old one
        assertEq(burnerRouter.globalReceiver(), currentReceiver, "Receiver should not change immediately");

        ( address pendingGlobalReceiver, ) = burnerRouter.pendingGlobalReceiver();

        assertEq(pendingGlobalReceiver, newReceiver, "Global receiver should be updated after delay");
    }

}

contract BurnerRouterAcceptGlobalReceiverFailureTests is BaseTest {

    function test_acceptGlobalReceiver_notReady() public {
        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setGlobalReceiver(alice);

        vm.warp(block.timestamp + BURNER_DELAY - 1);

        vm.expectRevert("NotReady()");
        burnerRouter.acceptGlobalReceiver();

        // Fast forward past the delay period
        skip(1 seconds);

        // Now accept the receiver change
        burnerRouter.acceptGlobalReceiver();

        assertEq(burnerRouter.globalReceiver(), alice, "Receiver should be updated after delay");
    }

}

contract BurnerRouterAcceptGlobalReceiverSuccessTests is BaseTest {

    function test_acceptGlobalReceiver() public {
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

contract BurnerRouterOwnershipTest is BaseTest {

    function test_BurnerRouterOwnership() public view {
        // Test that Spark Governance is the actual owner of the burner router
        address owner = OwnableUpgradeable(address(burnerRouter)).owner();
        assertEq(owner, SPARK_GOVERNANCE, "Spark Governance should be the owner of burner router");
    }

}

contract BurnerRouterSetDelayFailureTests is BaseTest {

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

contract BurnerRouterSetDelaySuccessTests is BaseTest {

    function test_setDelay() public {
        uint48 newDelay = 15 days; // Change from 31 days to 15 days

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setDelay(newDelay);

        ( uint48 pendingDelay, ) = burnerRouter.pendingDelay();

        assertEq(pendingDelay, newDelay, "Delay should be updated to new value");
    }

}

contract BurnerRouterAcceptDelayFailureTests is BaseTest {

    function test_acceptDelay_notReady() public {
        uint48 initialDelay = burnerRouter.delay();
        uint48 newDelay     = 15 days;  // Change from 31 days to 15 days

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setDelay(newDelay);

        vm.warp(block.timestamp + initialDelay - 1);

        vm.expectRevert("NotReady()");
        burnerRouter.acceptDelay();

        // Fast forward past the delay period (initial delay)
        skip(1 seconds);

        // Now accept the delay change
        burnerRouter.acceptDelay();
    }

}

contract BurnerRouterAcceptDelaySuccessTests is BaseTest {

    function test_acceptDelay() public {
        // Check initial delay (should be 31 days)
        uint48 initialDelay = burnerRouter.delay();
        assertEq(initialDelay, BURNER_DELAY, "Initial delay should be 31 days");

        // Test that owner (Spark Governance) can initiate delay change
        uint48 newDelay = 15 days; // Change from 31 days to 15 days

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setDelay(newDelay);

        // Check that delay is still the old value (change is pending)
        assertEq(burnerRouter.delay(), initialDelay, "Delay should still be old value while pending");

        vm.warp(block.timestamp + initialDelay - 1);

        vm.expectRevert("NotReady()");
        burnerRouter.acceptDelay();

        // Fast forward past the delay period (initial delay)
        skip(1 seconds);

        // Now accept the delay change
        burnerRouter.acceptDelay();

        // Verify the delay has been changed
        assertEq(burnerRouter.delay(), newDelay, "Delay should be updated to new value");
    }

}

contract BurnerRouterSetNetworkReceiverFailureTests is BaseTest {

    function test_setNetworkReceiver_notRole() public {
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice)
        );
        vm.prank(alice);
        burnerRouter.setNetworkReceiver(makeAddr("network"), alice);
    }

    function test_setNetworkReceiver_alreadySet() public {
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

        ( address pendingNetworkReceiver, ) = burnerRouter.pendingNetworkReceiver(network);

        assertEq(pendingNetworkReceiver, bob, "Network receiver should be updated after delay");
    }

}

contract BurnerRouterSetNetworkReceiverSuccessTests is BaseTest {

    function test_setNetworkReceiver() public {
        address network = makeAddr("network");

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setNetworkReceiver(network, alice);

        ( address pendingNetworkReceiver, ) = burnerRouter.pendingNetworkReceiver(network);

        assertEq(pendingNetworkReceiver, alice, "Network receiver should be updated after delay");
    }

}

contract BurnerRouterAcceptNetworkReceiverFailureTests is BaseTest {

    function test_acceptNetworkReceiver_notReady() public {
        address network = makeAddr("network");

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setNetworkReceiver(network, alice);

        vm.warp(block.timestamp + BURNER_DELAY - 1);

        vm.expectRevert("NotReady()");
        burnerRouter.acceptNetworkReceiver(network);

        // Fast forward past the delay period
        skip(1 seconds);

        // Now accept the receiver change
        burnerRouter.acceptNetworkReceiver(network);

        assertEq(burnerRouter.networkReceiver(network), alice, "Receiver should be updated after delay");
    }

}

contract BurnerRouterAcceptNetworkReceiverSuccessTests is BaseTest {

    function test_acceptNetworkReceiver() public {
        address network = makeAddr("network");

        address currentReceiver = burnerRouter.networkReceiver(network);

        address newReceiver = makeAddr("newReceiver");

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setNetworkReceiver(network, newReceiver);

        // Current receiver should still be the old one
        assertEq(burnerRouter.networkReceiver(network), currentReceiver, "Receiver should not change immediately");

        // Fast forward past the 31-day delay
        vm.warp(block.timestamp + BURNER_DELAY + 1);

        // Now accept the receiver change
        burnerRouter.acceptNetworkReceiver(network);

        // Verify the receiver has been changed
        assertEq(burnerRouter.networkReceiver(network), newReceiver, "Receiver should be updated after delay");
    }

}

contract BurnerRouterSetOperatorNetworkReceiverFailureTests is BaseTest {

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

        ( address pendingOperatorNetworkReceiver, ) = burnerRouter.pendingOperatorNetworkReceiver(network, operator);

        assertEq(pendingOperatorNetworkReceiver, bob, "Operator network receiver should be updated after delay");
    }

}

contract BurnerRouterSetOperatorNetworkReceiverSuccessTests is BaseTest {

    function test_setOperatorNetworkReceiver() public {
        address network = makeAddr("network");
        address operator = makeAddr("operator");

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setOperatorNetworkReceiver(network, operator, alice);

        ( address pendingOperatorNetworkReceiver, ) = burnerRouter.pendingOperatorNetworkReceiver(network, operator);

        assertEq(pendingOperatorNetworkReceiver, alice, "Operator network receiver should be updated after delay");
    }

}

contract BurnerRouterAcceptOperatorNetworkReceiverFailureTests is BaseTest {

    function test_acceptOperatorNetworkReceiver_notReady() public {
        address network = makeAddr("network");
        address operator = makeAddr("operator");

        vm.prank(SPARK_GOVERNANCE);
        burnerRouter.setOperatorNetworkReceiver(network, operator, alice);

        vm.warp(block.timestamp + BURNER_DELAY - 1);

        vm.expectRevert("NotReady()");
        burnerRouter.acceptOperatorNetworkReceiver(network, operator);

        // Fast forward past the delay period
        skip(1 seconds);

        // Now accept the receiver change
        burnerRouter.acceptOperatorNetworkReceiver(network, operator);

        assertEq(burnerRouter.operatorNetworkReceiver(network, operator), alice, "Receiver should be updated after delay");
    }

}

contract BurnerRouterAcceptOperatorNetworkReceiverSuccessTests is BaseTest {

    function test_acceptOperatorNetworkReceiver() public {
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
