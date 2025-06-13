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
    }

    function test_governanceCanSlashFirstLossPool() public {
        /*****************************************/
        /*** Do Spark Governance configuration ***/
        /*****************************************/

        // Step 1: Set the middleware to Spark Governance, set max network limit in vault delegator
        vm.startPrank(HYPERLANE_NETWORK);
        middlewareService.setMiddleware(HYPERLANE_NETWORK);
        delegator.setMaxNetworkLimit(0, 100_000e18);
        vm.stopPrank();

        // Step 2: Configure the network and operator to take control of 100k SPK stake
        vm.startPrank(OWNER_MULTISIG);
        delegator.setNetworkLimit(subnetwork, 100_000e18);
        delegator.setOperatorNetworkShares(
            subnetwork,
            OPERATOR,
            1e18  // 100% shares
        );
        vm.stopPrank();

        assertEq(delegator.totalOperatorNetworkSharesAt(subnetwork, uint48(block.timestamp), ""), 1e18);

        // Step 3: Opt in to the vault as the operator
        vm.startPrank(OPERATOR);
        IOptInService(delegator.OPERATOR_VAULT_OPT_IN_SERVICE()).optIn(address(sSpk));
        vm.stopPrank();

        /***********************************/
        /*** Test slashing functionality ***/
        /***********************************/

        deal(address(spk), alice, 10_000_000e18);

        // Step 1: Deposit 10m SPK to Spark Governance
        vm.startPrank(alice);
        spk.approve(address(sSpk), 10_000_000e18);
        sSpk.deposit(alice, 10_000_000e18);
        vm.stopPrank();

        skip(24 hours);  // Warp 24 hours

        // Step 2: Request a slash of 10% of staked SPK (500)
        uint48 captureTimestamp = uint48(block.timestamp - 1 hours);

        vm.prank(HYPERLANE_NETWORK);
        uint256 slashIndex = slasher.requestSlash(subnetwork, OPERATOR, 10_000_000e18, captureTimestamp, "");

        assertEq(slasher.slashRequestsLength(), 1);

        ( ,, uint256 amount,,, ) = slasher.slashRequests(slashIndex);

        assertEq(amount, 100_000e18);  // Can't request to slash more than the network limit (requested full 10m)

        // Step 3: Fast-forward past veto window and execute the slash
        vm.warp(block.timestamp + 3 days + 1);

        assertEq(sSpk.activeBalanceOf(alice), 10_000_000e18);
        assertEq(sSpk.totalStake(),           10_000_000e18);
        assertEq(sSpk.activeStake(),          10_000_000e18);

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""), 100_000e18);

        assertEq(spk.balanceOf(address(sSpk)), 10_000_000e18);
        assertEq(spk.balanceOf(BURNER_ROUTER), 0);

        vm.prank(HYPERLANE_NETWORK);
        slasher.executeSlash(slashIndex, "");

        assertEq(sSpk.activeBalanceOf(alice), 9_900_000e18);
        assertEq(sSpk.totalStake(),           9_900_000e18);
        assertEq(sSpk.activeStake(),          9_900_000e18);

        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp, ""), 0);

        assertEq(spk.balanceOf(address(sSpk)), 9_900_000e18);
        assertEq(spk.balanceOf(BURNER_ROUTER), 100_000e18);

        uint256 governanceBalance = spk.balanceOf(SPARK_GOVERNANCE);

        // Step 4: Transfer funds from the burner router to Spark Governance
        //         NOTE: This can be called by anyone
        IBurnerRouter(BURNER_ROUTER).triggerTransfer(SPARK_GOVERNANCE);

        assertEq(spk.balanceOf(BURNER_ROUTER),    0);
        assertEq(spk.balanceOf(SPARK_GOVERNANCE), governanceBalance + 100_000e18);

        // Step 5: Show that slasher cannot slash anymore once the limit is hit
        vm.prank(HYPERLANE_NETWORK);
        vm.expectRevert("InsufficientSlash()");
        slasher.executeSlash(slashIndex, "");
    }

}
