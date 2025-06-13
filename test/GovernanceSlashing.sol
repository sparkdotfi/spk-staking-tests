// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";

interface INetworkMiddlewareService {
    function setMiddleware(address middleware) external;
}

interface INetworkRegistry {
    function registerNetwork() external;
}

interface INetworkRestakeDelegator {
    function setNetworkLimit(bytes32 subnetwork, uint256 amount) external;
    function setMaxNetworkLimit(uint96 identifier, uint256 amount) external;
    function setOperatorNetworkShares(
        bytes32 subnetwork,
        address operator,
        uint256 shares
    ) external;
    function totalOperatorNetworkSharesAt(
        bytes32 subnetwork,
        uint48 timestamp,
        bytes memory hint
    ) external view returns (uint256);
    function OPERATOR_VAULT_OPT_IN_SERVICE() external view returns (address);
    function OPERATOR_NETWORK_OPT_IN_SERVICE() external view returns (address);
}

interface IOperatorRegistry {
    function registerOperator() external;
}

interface IOptInService {
    function optIn(address where) external;
    function WHO_REGISTRY() external view returns (address);
}

interface IVetoSlasher {
    function NETWORK_MIDDLEWARE_SERVICE() external view returns (address);
    function NETWORK_REGISTRY() external view returns (address);
    function requestSlash(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48  captureTimestamp,
        bytes   calldata hints
    ) external returns (uint256 slashIndex);
    function executeSlash(uint256 slashIndex, bytes calldata hints) external;
}

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

        subnetwork = bytes32(uint256(uint160(SPARK_GOVERNANCE)) << 96 | 0);  // Subnetwork.subnetwork(network, 0)
    }

    function test_governanceCanSlashFirstLossPool() public {
        /*****************************************/
        /*** Do Spark Governance configuration ***/
        /*****************************************/

        vm.startPrank(SPARK_GOVERNANCE);

        // Step 1: Register the network and operator (both Spark Governance)
        networkRegistry.registerNetwork();
        operatorRegistry.registerOperator();

        // Step 2: Set the middleware to Spark Governance
        middlewareService.setMiddleware(SPARK_GOVERNANCE);

        // Step 3: Configure the network and operator to take control of SPK stake
        delegator.setMaxNetworkLimit(0, 10_000e18);
        delegator.setNetworkLimit(subnetwork, 10_000e18);
        delegator.setOperatorNetworkShares(
            subnetwork,
            SPARK_GOVERNANCE,
            1e18  // 100% shares
        );

        // Step 4: Opt in to the vault and the network as the operator (Spark Governance)
        IOptInService(delegator.OPERATOR_VAULT_OPT_IN_SERVICE()).optIn(address(sSpk));
        IOptInService(delegator.OPERATOR_NETWORK_OPT_IN_SERVICE()).optIn(SPARK_GOVERNANCE);

        vm.stopPrank();

        /***********************************/
        /*** Test slashing functionality ***/
        /***********************************/

        // Step 1: Deposit 5k SPK to Spark Governance
        vm.startPrank(alice);
        spk.approve(address(sSpk), 5_000e18);
        sSpk.deposit(alice, 5_000e18);
        vm.stopPrank();

        // Step 2: Check the operator shares (means Spark Governance has control of the stake)
        uint256 shares = delegator.totalOperatorNetworkSharesAt(
            subnetwork,
            uint48(block.timestamp),
            ""
        );
        assertEq(shares, 1e18);

        skip(24 hours);  // Warp 24 hours

        // Step 3: Request a slash of 10% of staked SPK (500)
        uint48  captureTimestamp = uint48(block.timestamp - 1 hours);

        vm.prank(SPARK_GOVERNANCE);
        uint256 slashIndex = slasher.requestSlash(subnetwork, SPARK_GOVERNANCE, 500e18, captureTimestamp, "");

        // Step 4: Fast-forward past veto window and execute the slash
        vm.warp(block.timestamp + 3 days + 1);

        assertEq(sSpk.activeBalanceOf(alice), 5000e18);
        assertEq(sSpk.totalStake(),           5000e18);

        assertEq(spk.balanceOf(address(sSpk)), 5000e18);
        assertEq(spk.balanceOf(BURNER_ROUTER), 0);

        vm.prank(SPARK_GOVERNANCE);
        slasher.executeSlash(slashIndex, "");

        assertEq(sSpk.activeBalanceOf(alice), 4500e18);
        assertEq(sSpk.totalStake(),           4500e18);

        assertEq(spk.balanceOf(address(sSpk)), 4500e18);
        assertEq(spk.balanceOf(BURNER_ROUTER), 500e18);

        uint256 governanceBalance = spk.balanceOf(SPARK_GOVERNANCE);

        // Step 6: Transfer funds from the burner router to Spark Governance
        //         NOTE: This can be called by anyone
        IBurnerRouter(BURNER_ROUTER).triggerTransfer(SPARK_GOVERNANCE);

        assertEq(spk.balanceOf(BURNER_ROUTER),    0);
        assertEq(spk.balanceOf(SPARK_GOVERNANCE), governanceBalance + 500e18);

    }

}
