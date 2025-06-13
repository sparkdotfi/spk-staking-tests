// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";

import { INetworkMiddlewareService }  from "../lib/core/src/interfaces/service/INetworkMiddlewareService.sol";
import { INetworkRegistry }           from "../lib/core/src/interfaces/INetworkRegistry.sol";
import { INetworkRestakeDelegator }   from "../lib/core/src/interfaces/delegator/INetworkRestakeDelegator.sol";
import { IOperatorRegistry }          from "../lib/core/src/interfaces/IOperatorRegistry.sol";
import { IOptInService }              from "../lib/core/src/interfaces/service/IOptInService.sol";
import { IVault }                     from "../lib/core/src/interfaces/vault/IVault.sol";
import { IVaultTokenized }            from "../lib/core/src/interfaces/vault/IVaultTokenized.sol";
import { IVetoSlasher }               from "../lib/core/src/interfaces/slasher/IVetoSlasher.sol";

contract GovernanceSlashingTest is BaseTest {

    address public constant OPERATOR_REGISTRY = 0xAd817a6Bc954F678451A71363f04150FDD81Af9F;

    IVetoSlasher              slasher;
    INetworkRestakeDelegator  delegator;
    INetworkRegistry          networkRegistry;
    INetworkMiddlewareService middlewareService;
    IOperatorRegistry         operatorRegistry;

    bytes32 public subnetwork;

    function setUp() public override {
        super.setUp();

        slasher   = IVetoSlasher(VETO_SLASHER);
        delegator = INetworkRestakeDelegator(NETWORK_DELEGATOR);

        networkRegistry   = INetworkRegistry(slasher.NETWORK_REGISTRY());
        operatorRegistry  = IOperatorRegistry(OPERATOR_REGISTRY);
        middlewareService = INetworkMiddlewareService(slasher.NETWORK_MIDDLEWARE_SERVICE());

        subnetwork = bytes32(uint256(uint160(HYPERLANE_NETWORK)) << 96 | 0);  // Subnetwork.subnetwork(network, 0)

        /***********************************/
        /*** Do Hyperlane configuration  ***/
        /***********************************/

        // --- Step 1: Do configurations as network, setting middleware, max network limit, and resolver

        vm.startPrank(HYPERLANE_NETWORK);
        middlewareService.setMiddleware(HYPERLANE_NETWORK);
        delegator.setMaxNetworkLimit(0, 100_000e18);
        slasher.setResolver(0, OWNER_MULTISIG, "");
        vm.stopPrank();

        // --- Step 2: Configure the network and operator to take control of 100k SPK stake as the vault owner

        vm.startPrank(OWNER_MULTISIG);
        delegator.setNetworkLimit(subnetwork, 100_000e18);
        delegator.setOperatorNetworkShares(
            subnetwork,
            OPERATOR,
            1e18  // 100% shares
        );
        vm.stopPrank();

        assertEq(delegator.totalOperatorNetworkSharesAt(subnetwork, uint48(block.timestamp), ""), 1e18);

        // --- Step 3: Opt in to the vault as the operator

        vm.startPrank(OPERATOR);
        IOptInService(delegator.OPERATOR_VAULT_OPT_IN_SERVICE()).optIn(address(sSpk));
        vm.stopPrank();

    }

    function test_hyperlaneCanSlashUpToNetworkLimit() public {

        // --- Step 1: Deposit 10m SPK to stSPK as two users

        deal(address(spk), alice, 6_000_000e18);
        deal(address(spk), bob,   4_000_000e18);

        vm.startPrank(alice);
        spk.approve(address(sSpk), 6_000_000e18);
        sSpk.deposit(alice, 6_000_000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        spk.approve(address(sSpk), 4_000_000e18);
        sSpk.deposit(bob, 4_000_000e18);
        vm.stopPrank();

        skip(24 hours);  // Warp 24 hours

        // --- Step 2: Request a slash of all staked SPK (show that network limit is hit)

        uint48 captureTimestamp = uint48(block.timestamp - 1 hours);

        vm.prank(HYPERLANE_NETWORK);
        uint256 slashIndex = slasher.requestSlash(subnetwork, OPERATOR, 10_000_000e18, captureTimestamp, "");

        assertEq(slasher.slashRequestsLength(), 1);

        ( ,, uint256 amount,,, bool completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    100_000e18);  // Can't request to slash more than the network limit (requested full 10m)
        assertEq(completed, false);

        // --- Step 3: Fast-forward past veto window and execute the slash

        skip(3 days + 1);

        assertEq(sSpk.activeBalanceOf(alice), 6_000_000e18);
        assertEq(sSpk.activeBalanceOf(bob),   4_000_000e18);
        assertEq(sSpk.totalStake(),           10_000_000e18);
        assertEq(sSpk.activeStake(),          10_000_000e18);

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""), 100_000e18);

        assertEq(spk.balanceOf(address(sSpk)), 10_000_000e18);
        assertEq(spk.balanceOf(BURNER_ROUTER), 0);

        vm.prank(HYPERLANE_NETWORK);
        slasher.executeSlash(slashIndex, "");

        assertEq(sSpk.activeBalanceOf(alice), 6_000_000e18 - 60_000e18);  // Proportional slash
        assertEq(sSpk.activeBalanceOf(bob),   4_000_000e18 - 40_000e18);  // Proportional slash
        assertEq(sSpk.totalStake(),           9_900_000e18);
        assertEq(sSpk.activeStake(),          9_900_000e18);

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""), 0);

        assertEq(spk.balanceOf(address(sSpk)), 9_900_000e18);
        assertEq(spk.balanceOf(BURNER_ROUTER), 100_000e18);

        ( ,, amount,,, completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    100_000e18);
        assertEq(completed, true);

        uint256 governanceBalance = spk.balanceOf(SPARK_GOVERNANCE);

        // --- Step 4: Transfer funds from the burner router to Spark Governance
        //         NOTE: This can be called by anyone

        IBurnerRouter(BURNER_ROUTER).triggerTransfer(SPARK_GOVERNANCE);

        assertEq(spk.balanceOf(BURNER_ROUTER),    0);
        assertEq(spk.balanceOf(SPARK_GOVERNANCE), governanceBalance + 100_000e18);

        // --- Step 5: Show that slasher cannot slash anymore with the same request

        // Can't execute the same slash again
        vm.prank(HYPERLANE_NETWORK);
        vm.expectRevert("InsufficientSlash()");
        slasher.executeSlash(slashIndex, "");

        // --- Step 6: Show that slasher also cannot request new slashes because the network limit has been hit

        skip(24 hours);  // Warp 24 hours

        captureTimestamp = uint48(block.timestamp - 1 hours);

        vm.prank(HYPERLANE_NETWORK);
        vm.expectRevert("InsufficientSlash()");
        slashIndex = slasher.requestSlash(subnetwork, OPERATOR, 100e18, captureTimestamp, "");  // Use smaller amount to show its not because of 10m
    }

    function test_ownerMultisigCanVetoSlash() public {

        // --- Step 1: Deposit 10m SPK to stSPK as two users

        deal(address(spk), alice, 6_000_000e18);
        deal(address(spk), bob,   4_000_000e18);

        vm.startPrank(alice);
        spk.approve(address(sSpk), 6_000_000e18);
        sSpk.deposit(alice, 6_000_000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        spk.approve(address(sSpk), 4_000_000e18);
        sSpk.deposit(bob, 4_000_000e18);
        vm.stopPrank();

        skip(24 hours);  // Warp 24 hours

        // --- Step 2: Request a slash of 10% of staked SPK (500)

        uint48 captureTimestamp = uint48(block.timestamp - 1 hours);

        vm.prank(HYPERLANE_NETWORK);
        uint256 slashIndex = slasher.requestSlash(subnetwork, OPERATOR, 10_000_000e18, captureTimestamp, "");

        assertEq(slasher.slashRequestsLength(), 1);

        ( ,, uint256 amount,,, bool completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    100_000e18);  // Can't request to slash more than the network limit (requested full 10m)
        assertEq(completed, false);

        // --- Step 3: Owner multisig vetos the slash request

        skip(3 days - 1 seconds);  // Demonstrate multisig has a full three days from request to veto

        vm.prank(OWNER_MULTISIG);
        slasher.vetoSlash(slashIndex, "");

        ( ,, amount,,, completed ) = slasher.slashRequests(slashIndex);

        assertEq(amount,    100_000e18);
        assertEq(completed, true);  // Prevents execution of the slash

        // --- Step 4: Attempt to execute the slashing after veto (should fail)

        skip(1 seconds);  // Fast-forward to the next block to pass the check to show relevant error

        vm.prank(HYPERLANE_NETWORK);
        vm.expectRevert("SlashRequestCompleted()");
        slasher.executeSlash(slashIndex, "");
    }

}
