// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";

// Import Symbiotic interfaces
import "../lib/burners/src/interfaces/router/IBurnerRouter.sol";
import "../lib/core/src/interfaces/vault/IVault.sol";
import "../lib/core/src/interfaces/vault/IVaultTokenized.sol";

// Import OpenZeppelin interfaces
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { INetworkMiddlewareService }  from "../lib/core/src/interfaces/service/INetworkMiddlewareService.sol";
import { INetworkRestakeDelegator }   from "../lib/core/src/interfaces/delegator/INetworkRestakeDelegator.sol";
import { IOptInService }              from "../lib/core/src/interfaces/service/IOptInService.sol";
import { IVetoSlasher }               from "../lib/core/src/interfaces/slasher/IVetoSlasher.sol";

interface IStakedSPK is IERC20Metadata, IVaultTokenized, IAccessControl {}

abstract contract BaseTest is Test {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    // Deployed addresses
    address constant BURNER_ROUTER     = 0x8BaB0b7975A3128D3D712A33Dc59eb5346e74BCd;
    address constant NETWORK_DELEGATOR = 0x2C5bF9E8e16716A410644d6b4979d74c1951952d;
    address constant STAKED_SPK_VAULT  = 0xc6132FAF04627c8d05d6E759FAbB331Ef2D8F8fD;
    address constant VETO_SLASHER      = 0x4BaaEB2Bf1DC32a2Fb2DaA4E7140efb2B5f8cAb7;
    address constant RESET_HOOK        = 0xC3B87BbE976f5Bfe4Dc4992ae4e22263Df15ccBE;

    // Actors
    address constant HYPERLANE_NETWORK = 0x59cf937Ea9FA9D7398223E3aA33d92F7f5f986A2;
    address constant OPERATOR          = 0x087c25f83ED20bda587CFA035ED0c96338D4660f;  // TODO: Change
    address constant OWNER_MULTISIG    = 0x7a27a9f2A823190140cfb4027f4fBbfA438bac79;
    address constant SPARK_GOVERNANCE  = 0x3300f198988e4C9C63F75dF86De36421f06af8c4;

    // Token
    address constant SPK = 0xc20059e0317DE91738d13af027DfC4a50781b066;

    // Constants from deployment
    uint48 constant BURNER_DELAY          = 31 days;
    uint48 constant EPOCH_DURATION        = 2 weeks;
    uint48 constant SLASHER_VETO_DURATION = 3 days;

    // Constants based on fork time
    uint256 ACTIVE_STAKE;
    uint256 TOTAL_STAKE;

    // Test users
    address alice    = makeAddr("alice");
    address attacker = makeAddr("attacker");
    address bob      = makeAddr("bob");
    address charlie  = makeAddr("charlie");

    // Contract instances
    IBurnerRouter  burnerRouter = IBurnerRouter(BURNER_ROUTER);
    IERC20Metadata spk          = IERC20Metadata(SPK);
    IStakedSPK     sSpk         = IStakedSPK(STAKED_SPK_VAULT);  // For accessing ERC20 functions
    IVetoSlasher   slasher      = IVetoSlasher(VETO_SLASHER);

    INetworkRestakeDelegator delegator = INetworkRestakeDelegator(NETWORK_DELEGATOR);

    INetworkMiddlewareService middlewareService;

    bytes32 public subnetwork;

    /**********************************************************************************************/
    /*** Setup                                                                                  ***/
    /**********************************************************************************************/

    function setUp() public virtual {
        vm.createSelectFork(getChain("mainnet").rpcUrl, 22769489);  // June 14, 2025

        ACTIVE_STAKE = sSpk.activeStake();
        TOTAL_STAKE  = sSpk.totalStake();

        middlewareService = INetworkMiddlewareService(slasher.NETWORK_MIDDLEWARE_SERVICE());

        subnetwork = bytes32(uint256(uint160(HYPERLANE_NETWORK)) << 96 | 0);  // Subnetwork.subnetwork(network, 0)

        _setupTestUsers();

        /***********************************/
        /*** Do Hyperlane configuration  ***/
        /***********************************/

        // --- Step 1: Do configurations as network, setting middleware, max network limit, and resolver

        vm.startPrank(HYPERLANE_NETWORK);
        middlewareService.setMiddleware(HYPERLANE_NETWORK);
        delegator.setMaxNetworkLimit(0, 2_000_000e18);
        slasher.setResolver(0, OWNER_MULTISIG, "");
        vm.stopPrank();

        // --- Step 2: Configure the network and operator to take control of 100k SPK stake as the vault owner

        vm.startPrank(OWNER_MULTISIG);
        delegator.setNetworkLimit(subnetwork, 2_000_000e18);
        delegator.setOperatorNetworkShares(
            subnetwork,
            OPERATOR,
            1e18  // 100% shares
        );
        delegator.setHook(RESET_HOOK);
        IAccessControl(address(delegator)).grantRole(delegator.OPERATOR_NETWORK_SHARES_SET_ROLE(), RESET_HOOK);
        vm.stopPrank();

        assertEq(delegator.totalOperatorNetworkSharesAt(subnetwork, uint48(block.timestamp), ""), 1e18);

        // --- Step 3: Opt in to the vault as the operator

        vm.startPrank(OPERATOR);
        IOptInService(delegator.OPERATOR_VAULT_OPT_IN_SERVICE()).optIn(address(sSpk));
        vm.stopPrank();
    }

    function _setupTestUsers() internal {
        deal(SPK, alice,    10_000e18);
        deal(SPK, bob,      10_000e18);
        deal(SPK, charlie,  10_000e18);
        deal(SPK, attacker, 10_000e18);
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    /**
     * @notice Helper function to initialize the epoch system with a deposit
     * @dev The epoch system starts when the first deposit is made
     */
    function _initializeEpochSystem() internal {
        // Make a small deposit to start the epoch system
        address initialDepositor = makeAddr("epochInitializer");
        deal(SPK, initialDepositor, 1e18); // 1 SPK

        vm.startPrank(initialDepositor);
        spk.approve(address(sSpk), 1e18);
        sSpk.deposit(initialDepositor, 1e18);
        vm.stopPrank();
    }

    /**
     * @notice Helper function to calculate absolute difference between two numbers
     * @param a First number
     * @param b Second number
     * @return Absolute difference
     */
    function _abs(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a - b : b - a;
    }

}
