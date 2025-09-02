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

import { INetworkMiddlewareService } from "../lib/core/src/interfaces/service/INetworkMiddlewareService.sol";
import { INetworkRegistry }          from "../lib/core/src/interfaces/INetworkRegistry.sol";
import { IOperatorRegistry }         from "../lib/core/src/interfaces/IOperatorRegistry.sol";
import { INetworkRestakeDelegator as INetworkRestakeDelegatorBase }  from "../lib/core/src/interfaces/delegator/INetworkRestakeDelegator.sol";
import { IOptInService }             from "../lib/core/src/interfaces/service/IOptInService.sol";
import { IVetoSlasher }              from "../lib/core/src/interfaces/slasher/IVetoSlasher.sol";

interface IStakedSPK is IERC20Metadata, IVaultTokenized, IAccessControl {}
interface INetworkRestakeDelegator is INetworkRestakeDelegatorBase, IAccessControl {}

abstract contract BaseTest is Test {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    // Symbiotic system addresses
    address constant VAULT_FACTORY     = 0xAEb6bdd95c502390db8f52c8909F703E9Af6a346;
    address constant NETWORK_REGISTRY  = 0xC773b1011461e7314CF05f97d95aa8e92C1Fd8aA;
    address constant OPERATOR_REGISTRY = 0xAd817a6Bc954F678451A71363f04150FDD81Af9F;

    // Deployed addresses
    address constant BURNER_ROUTER     = 0x8BaB0b7975A3128D3D712A33Dc59eb5346e74BCd;
    address constant NETWORK_DELEGATOR = 0x2C5bF9E8e16716A410644d6b4979d74c1951952d;
    address constant STAKED_SPK_VAULT  = 0xc6132FAF04627c8d05d6E759FAbB331Ef2D8F8fD;
    address constant VETO_SLASHER      = 0x4BaaEB2Bf1DC32a2Fb2DaA4E7140efb2B5f8cAb7;
    address constant RESET_HOOK        = 0xC3B87BbE976f5Bfe4Dc4992ae4e22263Df15ccBE;

    // Actors
    address constant SPARK_CONTROLLED_MULTISIG = 0x7a27a9f2A823190140cfb4027f4fBbfA438bac79;
    address constant SPARK_GOVERNANCE          = 0x3300f198988e4C9C63F75dF86De36421f06af8c4;

    address constant NETWORK        = SPARK_GOVERNANCE;
    address constant OPERATOR       = SPARK_GOVERNANCE;

    // Token
    address constant SPK = 0xc20059e0317DE91738d13af027DfC4a50781b066;

    // Constants from deployment
    uint48 constant BURNER_DELAY          = 31 days;
    uint48 constant EPOCH_DURATION        = 2 weeks;
    uint48 constant SLASHER_VETO_DURATION = 3 days;

    // Roles
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    // Constants based on forked state
    uint256 ACTIVE_STAKE;
    uint256 TOTAL_STAKE;

    // Test users
    address alice    = makeAddr("alice");
    address attacker = makeAddr("attacker");
    address bob      = makeAddr("bob");
    address charlie  = makeAddr("charlie");

    // Contract instances
    IBurnerRouter     burnerRouter     = IBurnerRouter(BURNER_ROUTER);
    IERC20Metadata    spk              = IERC20Metadata(SPK);
    IStakedSPK        stSpk            = IStakedSPK(STAKED_SPK_VAULT);  // For accessing ERC20 functions
    IVetoSlasher      slasher          = IVetoSlasher(VETO_SLASHER);
    INetworkRegistry  networkRegistry  = INetworkRegistry(NETWORK_REGISTRY);
    IOperatorRegistry operatorRegistry = IOperatorRegistry(OPERATOR_REGISTRY);

    INetworkRestakeDelegator delegator = INetworkRestakeDelegator(NETWORK_DELEGATOR);

    INetworkMiddlewareService middlewareService;

    bytes32 public subnetwork;

    /**********************************************************************************************/
    /*** Setup                                                                                  ***/
    /**********************************************************************************************/

    function setUp() public virtual {
        vm.createSelectFork(getChain("mainnet").rpcUrl, 22769489);  // June 14, 2025

        ACTIVE_STAKE = stSpk.activeStake();
        TOTAL_STAKE  = stSpk.totalStake();

        middlewareService = INetworkMiddlewareService(slasher.NETWORK_MIDDLEWARE_SERVICE());

        subnetwork = bytes32(uint256(uint160(NETWORK)) << 96 | 0);  // Subnetwork.subnetwork(network, 0)

        _setupTestUsers();

        _transferOwnershipFromSparkMultisigToSparkGovernance();
        _testOwnershipTransferredFromSparkMultisigToSparkGovernance();

        /***********************************/
        /*** Do Hyperlane configuration  ***/
        /***********************************/

        // --- Step 1: Do configurations as network, DO NOT SET middleware, max network limit, and resolver

        vm.startPrank(SPARK_GOVERNANCE);
        networkRegistry.registerNetwork();
        delegator.setMaxNetworkLimit(0, 2_000_000e18);
        slasher.setResolver(0, SPARK_GOVERNANCE, "");

        // --- Step 2: Configure the network and operator to take control of 2m SPK stake as the vault owner

        delegator.setNetworkLimit(subnetwork, 2_000_000e18);
        delegator.setOperatorNetworkShares(
            subnetwork,
            OPERATOR,
            1e18  // 100% shares
        );
        delegator.setHook(RESET_HOOK);
        IAccessControl(address(delegator)).grantRole(delegator.OPERATOR_NETWORK_SHARES_SET_ROLE(), RESET_HOOK);

        assertEq(delegator.totalOperatorNetworkSharesAt(subnetwork, uint48(block.timestamp), ""), 1e18);

        // --- Step 3: Opt in to the vault as the operator

        operatorRegistry.registerOperator();
        IOptInService(delegator.OPERATOR_NETWORK_OPT_IN_SERVICE()).optIn(NETWORK);
        IOptInService(delegator.OPERATOR_VAULT_OPT_IN_SERVICE()).optIn(address(stSpk));

        // --- Step 4: Check that points requirements are met

        assertEq(delegator.stake(subnetwork, OPERATOR), 2_000_000e18);
        vm.stopPrank();
    }

    function _setupTestUsers() internal {
        deal(SPK, alice,    10_000e18);
        deal(SPK, bob,      10_000e18);
        deal(SPK, charlie,  10_000e18);
        deal(SPK, attacker, 10_000e18);
    }

    function _transferOwnershipFromSparkMultisigToSparkGovernance() internal {
        vm.startPrank(SPARK_CONTROLLED_MULTISIG);

        // 1: BurnerRouter
        assertEq(OwnableUpgradeable(address(burnerRouter)).owner(), SPARK_CONTROLLED_MULTISIG);
        OwnableUpgradeable(address(burnerRouter)).transferOwnership(SPARK_GOVERNANCE);
        // After-tests are done separately

        // 2. Vault
        assertEq(OwnableUpgradeable(address(stSpk)).owner(), SPARK_CONTROLLED_MULTISIG);
        OwnableUpgradeable(address(stSpk)).transferOwnership(SPARK_GOVERNANCE);

        stSpk.renounceRole(stSpk.DEPOSIT_WHITELIST_SET_ROLE(), SPARK_CONTROLLED_MULTISIG);
        stSpk.renounceRole(stSpk.DEPOSITOR_WHITELIST_ROLE(),   SPARK_CONTROLLED_MULTISIG);
        stSpk.renounceRole(stSpk.IS_DEPOSIT_LIMIT_SET_ROLE(),  SPARK_CONTROLLED_MULTISIG);
        stSpk.renounceRole(stSpk.DEPOSIT_LIMIT_SET_ROLE(),     SPARK_CONTROLLED_MULTISIG);

        stSpk.grantRole(stSpk.DEPOSIT_WHITELIST_SET_ROLE(), SPARK_GOVERNANCE);
        stSpk.grantRole(stSpk.DEPOSITOR_WHITELIST_ROLE(),   SPARK_GOVERNANCE);
        stSpk.grantRole(stSpk.IS_DEPOSIT_LIMIT_SET_ROLE(),  SPARK_GOVERNANCE);
        stSpk.grantRole(stSpk.DEPOSIT_LIMIT_SET_ROLE(),     SPARK_GOVERNANCE);

        stSpk.grantRole(DEFAULT_ADMIN_ROLE,    SPARK_GOVERNANCE);
        stSpk.renounceRole(DEFAULT_ADMIN_ROLE, SPARK_CONTROLLED_MULTISIG);

        // 3. Delegator
        delegator.renounceRole(delegator.HOOK_SET_ROLE(),                    SPARK_CONTROLLED_MULTISIG);
        delegator.renounceRole(delegator.NETWORK_LIMIT_SET_ROLE(),           SPARK_CONTROLLED_MULTISIG);
        delegator.renounceRole(delegator.OPERATOR_NETWORK_SHARES_SET_ROLE(), SPARK_CONTROLLED_MULTISIG);

        delegator.grantRole(delegator.HOOK_SET_ROLE(),                    SPARK_GOVERNANCE);
        delegator.grantRole(delegator.NETWORK_LIMIT_SET_ROLE(),           SPARK_GOVERNANCE);
        delegator.grantRole(delegator.OPERATOR_NETWORK_SHARES_SET_ROLE(), SPARK_GOVERNANCE);

        delegator.grantRole(DEFAULT_ADMIN_ROLE, SPARK_GOVERNANCE);
        delegator.renounceRole(DEFAULT_ADMIN_ROLE, SPARK_CONTROLLED_MULTISIG);

        // 4. Slasher
        // Nothing.
    }

    function _testOwnershipTransferredFromSparkMultisigToSparkGovernance() public {
        // 1: BurnerRouter
        // Correct owner
        assertEq(OwnableUpgradeable(address(burnerRouter)).owner(), SPARK_GOVERNANCE);

        // No admin()
        (bool success, ) = address(burnerRouter).call(abi.encodeWithSignature("admin()"));
        assertFalse(success);

        // No admin slot
        assertEq(vm.load(address(burnerRouter), ADMIN_SLOT), bytes32(0));

        // 2. Vault
        // Correct owner
        assertEq(OwnableUpgradeable(address(stSpk)).owner(), SPARK_GOVERNANCE);

        // Admin is Vault Factory (not Multisig)
        bytes32 adminSlot = vm.load(address(stSpk), ADMIN_SLOT);
        address admin = address(uint160(uint256(adminSlot))); // lower 20 bytes
        assertEq(admin, VAULT_FACTORY);

        // Correct roles
        assertTrue(stSpk.hasRole(stSpk.DEPOSIT_WHITELIST_SET_ROLE(), SPARK_GOVERNANCE));
        assertTrue(stSpk.hasRole(stSpk.DEPOSITOR_WHITELIST_ROLE(),   SPARK_GOVERNANCE));
        assertTrue(stSpk.hasRole(stSpk.IS_DEPOSIT_LIMIT_SET_ROLE(),  SPARK_GOVERNANCE));
        assertTrue(stSpk.hasRole(stSpk.DEPOSIT_LIMIT_SET_ROLE(),     SPARK_GOVERNANCE));

        assertFalse(stSpk.hasRole(stSpk.DEPOSIT_WHITELIST_SET_ROLE(), SPARK_CONTROLLED_MULTISIG));
        assertFalse(stSpk.hasRole(stSpk.DEPOSITOR_WHITELIST_ROLE(),   SPARK_CONTROLLED_MULTISIG));
        assertFalse(stSpk.hasRole(stSpk.IS_DEPOSIT_LIMIT_SET_ROLE(),  SPARK_CONTROLLED_MULTISIG));
        assertFalse(stSpk.hasRole(stSpk.DEPOSIT_LIMIT_SET_ROLE(),     SPARK_CONTROLLED_MULTISIG));

        assertTrue(stSpk.hasRole(DEFAULT_ADMIN_ROLE,  SPARK_GOVERNANCE));
        assertFalse(stSpk.hasRole(DEFAULT_ADMIN_ROLE, SPARK_CONTROLLED_MULTISIG));

        // 3. Delegator
        // No owner
        (bool success2, ) = address(delegator).call(abi.encodeWithSignature("owner()"));
        assertFalse(success2);

        // No admin()
        (bool success3, ) = address(delegator).call(abi.encodeWithSignature("admin()"));
        assertFalse(success3);

        // No admin slot
        assertEq(vm.load(address(delegator), ADMIN_SLOT), bytes32(0));

        // Correct roles
        assertTrue(delegator.hasRole(delegator.HOOK_SET_ROLE(),                    SPARK_GOVERNANCE));
        assertTrue(delegator.hasRole(delegator.NETWORK_LIMIT_SET_ROLE(),           SPARK_GOVERNANCE));
        assertTrue(delegator.hasRole(delegator.OPERATOR_NETWORK_SHARES_SET_ROLE(), SPARK_GOVERNANCE));

        assertFalse(delegator.hasRole(delegator.HOOK_SET_ROLE(),                    SPARK_CONTROLLED_MULTISIG));
        assertFalse(delegator.hasRole(delegator.NETWORK_LIMIT_SET_ROLE(),           SPARK_CONTROLLED_MULTISIG));
        assertFalse(delegator.hasRole(delegator.OPERATOR_NETWORK_SHARES_SET_ROLE(), SPARK_CONTROLLED_MULTISIG));

        assertTrue(delegator.hasRole(DEFAULT_ADMIN_ROLE,  SPARK_GOVERNANCE));
        assertFalse(delegator.hasRole(DEFAULT_ADMIN_ROLE, SPARK_CONTROLLED_MULTISIG));

        // 4. Slasher
        // No owner
        (bool success4, ) = address(slasher).call(abi.encodeWithSignature("owner()"));
        assertFalse(success4);

        // No admin()
        (bool success5, ) = address(slasher).call(abi.encodeWithSignature("admin()"));
        assertFalse(success5);

        // No admin slot
        assertEq(vm.load(address(slasher), ADMIN_SLOT), bytes32(0));

        // No roles
        (bool success6, ) = address(slasher).call(abi.encodeWithSignature("hasRole(bytes32,address)", DEFAULT_ADMIN_ROLE, SPARK_GOVERNANCE));
        assertFalse(success6);
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
        spk.approve(address(stSpk), 1e18);
        stSpk.deposit(initialDepositor, 1e18);
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
