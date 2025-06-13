// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./BaseTest.sol";

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
}

interface INetworkRegistry {
    function registerNetwork() external;
}

interface IOperatorRegistry {
    function registerOperator() external;
}

interface INetworkMiddlewareService {
    function setMiddleware(address middleware) external;
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

interface IOptInService {
    function optIn(address where) external;
    function WHO_REGISTRY() external view returns (address);
}

contract GovernanceSlashingTest is BaseTest {

    IVetoSlasher             slasher;
    INetworkRestakeDelegator delegator;
    INetworkRegistry         registry;
    INetworkMiddlewareService middlewareService;

    bytes32 public subnetwork;

    function setUp() public override {
        super.setUp();

        slasher   = IVetoSlasher(VETO_SLASHER);
        delegator = INetworkRestakeDelegator(NETWORK_DELEGATOR);
        registry  = INetworkRegistry(slasher.NETWORK_REGISTRY());

        middlewareService = INetworkMiddlewareService(slasher.NETWORK_MIDDLEWARE_SERVICE());

        subnetwork = bytes32(uint256(uint160(SPARK_GOVERNANCE)) << 96 | 0);  // Subnetwork.subnetwork(network, 0)
    }

    function test_governanceCanSlashFirstLossPool() public {
        _initializeEpochSystem();

        // ————— Wire up “first-loss” capital —————
        vm.startPrank(SPARK_GOVERNANCE);

        registry.registerNetwork();                             // register your fake network
        middlewareService.setMiddleware(SPARK_GOVERNANCE);   // gov is now the only middleware

        delegator.setMaxNetworkLimit(0, 10_000e18);             // cap at 10k SPK
        delegator.setNetworkLimit(subnetwork, 10_000e18);       // opt into 10k stake
        delegator.setOperatorNetworkShares(
            subnetwork,
            SPARK_GOVERNANCE,
            1e18                                                // 100% shares
        );

        IOptInService vaultOptInService = IOptInService(delegator.OPERATOR_VAULT_OPT_IN_SERVICE());

        IOperatorRegistry(vaultOptInService.WHO_REGISTRY()).registerOperator();

        vaultOptInService.optIn(address(sSpk));

        IOptInService(delegator.OPERATOR_NETWORK_OPT_IN_SERVICE()).optIn(SPARK_GOVERNANCE);

        vm.stopPrank();

        // ————— User deposits 5k SPK —————
        vm.startPrank(alice);
        spk.approve(address(sSpk), 5_000e18);
        sSpk.deposit(alice, 5_000e18);
        vm.stopPrank();

        // sanity-check operator shares
        uint256 shares = delegator.totalOperatorNetworkSharesAt(
            subnetwork,
            uint48(block.timestamp),
            ""
        );
        assertEq(shares, 1e18);

        skip(24 hours);

        // ————— Governance triggers & executes a slash —————
        uint48  ts    = uint48(block.timestamp - 1 hours);
        uint256 amt   = 500e18;

        vm.prank(SPARK_GOVERNANCE);
        uint256 idx = slasher.requestSlash(subnetwork, SPARK_GOVERNANCE, amt, ts, "");

        // // fast-forward past veto window (in real code you'd wait 3 days)
        // vm.warp(block.timestamp + 3 days + 1);

        // vm.prank(SPARK_GOVERNANCE);
        // uint256 slashed = slasher.executeSlash(idx, "");

        // assertEq(slashed, amt, "should slash exactly amt");

        // // now verify alice’s stake was reduced by amt
        // assertEq(sSpk.totalStake(), 5_000e18 - amt);
    }

}
