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

interface IStakedSPK is IERC20Metadata, IVaultTokenized, IAccessControl {}

abstract contract BaseTest is Test {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    // Mainnet addresses from deployment
    address constant BURNER_ROUTER     = 0x8BaB0b7975A3128D3D712A33Dc59eb5346e74BCd;
    address constant HYPERLANE_NETWORK = 0x59cf937Ea9FA9D7398223E3aA33d92F7f5f986A2;
    address constant NETWORK_DELEGATOR = 0x2C5bF9E8e16716A410644d6b4979d74c1951952d;
    address constant OWNER_MULTISIG    = 0x7a27a9f2A823190140cfb4027f4fBbfA438bac79;
    address constant SPARK_GOVERNANCE  = 0x3300f198988e4C9C63F75dF86De36421f06af8c4;
    address constant SPK               = 0xc20059e0317DE91738d13af027DfC4a50781b066;
    address constant STAKED_SPK_VAULT  = 0xc6132FAF04627c8d05d6E759FAbB331Ef2D8F8fD;
    address constant VETO_SLASHER      = 0x4BaaEB2Bf1DC32a2Fb2DaA4E7140efb2B5f8cAb7;
    address constant OPERATOR          = 0x087c25f83ED20bda587CFA035ED0c96338D4660f;  // TODO: Change

    // Constants from deployment
    uint48 constant BURNER_DELAY          = 31 days;
    uint48 constant EPOCH_DURATION        = 2 weeks;
    uint48 constant SLASHER_VETO_DURATION = 3 days;

    // Test users
    address alice    = makeAddr("alice");
    address attacker = makeAddr("attacker");
    address bob      = makeAddr("bob");
    address charlie  = makeAddr("charlie");

    // Contract instances
    IBurnerRouter   burnerRouter;
    IERC20Metadata  spk;
    IStakedSPK      sSpk;  // For accessing ERC20 functions
    IAccessControl  vaultAccess;

    // ============ SETUP ============

    function setUp() public virtual {
        vm.createSelectFork(getChain("mainnet").rpcUrl, 22698495);

        // Initialize contract instances
        burnerRouter = IBurnerRouter(BURNER_ROUTER);

        spk  = IERC20Metadata(SPK);
        sSpk = IStakedSPK(STAKED_SPK_VAULT);

        // Setup test users with SPK tokens
        _setupTestUsers();
    }

    function _setupTestUsers() internal {
        deal(SPK, alice,    10_000e18);
        deal(SPK, bob,      10_000e18);
        deal(SPK, charlie,  10_000e18);
        deal(SPK, attacker, 10_000e18);
    }

    // ============ HELPER FUNCTIONS ============

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
