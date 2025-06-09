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
    address constant BURNER_ROUTER     = 0xe244C36C8D6831829590c05F49bBb98B11965efb;
    address constant NETWORK_DELEGATOR = 0x20ba8C54B62F1F4653289DCdf316d68199158Fb6;
    address constant SPARK_GOVERNANCE  = 0x3300f198988e4C9C63F75dF86De36421f06af8c4;
    address constant SPK               = 0xc20059e0317DE91738d13af027DfC4a50781b066;
    address constant STAKED_SPK_VAULT  = 0x0542206DAD09b1b58f29155b4317F9Bf92CD2701;
    address constant VETO_SLASHER      = 0xeF4fa9b4529A9e983B18F223A284025f24d2F18B;

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
        // Fork mainnet at a recent block - requires MAINNET_RPC_URL to be set
        string memory rpcUrl = vm.envString("MAINNET_RPC_URL");

        uint256 forkId = vm.createFork(rpcUrl, 22632309);
        vm.selectFork(forkId);

        // Initialize contract instances
        burnerRouter = IBurnerRouter(BURNER_ROUTER);

        spk  = IERC20Metadata(SPK);
        sSpk = IStakedSPK(STAKED_SPK_VAULT);

        // Setup test users with SPK tokens
        _setupTestUsers();
    }

    function _setupTestUsers() internal {
        // TODO: Deal
        // Use the helper function to give tokens to test users
        _giveTokens(alice,    10000 * 1e18);   // 10k SPK
        _giveTokens(bob,      10000 * 1e18);     // 10k SPK
        _giveTokens(charlie,  10000 * 1e18); // 10k SPK
        _giveTokens(attacker, 10000 * 1e18); // 10k SPK for attack tests
    }

    // ============ HELPER FUNCTIONS ============

    /**
     * @notice Helper function to initialize the epoch system with a deposit
     * @dev The epoch system starts when the first deposit is made
     */
    function _initializeEpochSystem() internal {
        // Make a small deposit to start the epoch system
        address initialDepositor = makeAddr("epochInitializer");
        _giveTokens(initialDepositor, 1 * 1e18); // 1 SPK

        vm.startPrank(initialDepositor);
        spk.approve(address(sSpk), 1 * 1e18);
        sSpk.deposit(initialDepositor, 1 * 1e18);
        vm.stopPrank();
    }

    /**
     * @notice Internal helper function to give SPK tokens to any address
     * @param to Address to send tokens to
     * @param amount Amount of SPK tokens to send (in wei)
     */
    function _giveTokens(address to, uint256 amount) internal {
        address whale = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB; // 6.5 billion SPK whale

        vm.startPrank(whale);
        spk.transfer(to, amount);
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
