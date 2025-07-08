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

import { BurnerRouterFactory } from "../lib/burners/src/contracts/router/BurnerRouterFactory.sol";

// For IBurnerRouter.InitParams
import { IBurnerRouter } from "../lib/burners/src/interfaces/router/IBurnerRouter.sol";
import { BurnerRouter } from "../lib/burners/src/contracts/router/BurnerRouter.sol";

// For IVaultConfigurator.InitParams
import { IVaultConfigurator } from "../lib/core/src/interfaces/IVaultConfigurator.sol";
import { VaultConfigurator } from "../lib/core/src/contracts/VaultConfigurator.sol";

// For IVaultTokenized.InitParams
import { IVault } from "../lib/core/src/interfaces/vault/IVault.sol";
import { Vault } from "../lib/core/src/contracts/vault/Vault.sol";

// For IVaultTokenized.InitParamsTokenized
import { IVaultTokenized } from "../lib/core/src/interfaces/vault/IVaultTokenized.sol";
import { VaultTokenized } from "../lib/core/src/contracts/vault/VaultTokenized.sol";

// For IBaseDelegator.BaseParams
import { IBaseDelegator } from "../lib/core/src/interfaces/delegator/IBaseDelegator.sol";

// For INetworkRestakeDelegator.InitParams
import { INetworkRestakeDelegator } from "../lib/core/src/interfaces/delegator/INetworkRestakeDelegator.sol";
import { NetworkRestakeDelegator } from "../lib/core/src/contracts/delegator/NetworkRestakeDelegator.sol";

// For IBaseSlasher.BaseParams
import { IBaseSlasher } from "../lib/core/src/interfaces/slasher/IBaseSlasher.sol";

import { Slasher } from "../lib/core/src/contracts/slasher/Slasher.sol";

// For IVetoSlasher.InitParams
import { IVetoSlasher } from "../lib/core/src/interfaces/slasher/IVetoSlasher.sol";
import { VetoSlasher } from "../lib/core/src/contracts/slasher/VetoSlasher.sol";

import { VaultFactory } from "../lib/core/src/contracts/VaultFactory.sol";
import { DelegatorFactory } from "../lib/core/src/contracts/DelegatorFactory.sol";
import { SlasherFactory } from "../lib/core/src/contracts/SlasherFactory.sol";

import { ERC20Mock } from "../lib/core/lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import { NetworkRegistry } from "../lib/core/src/contracts/NetworkRegistry.sol";
import { NetworkMiddlewareService } from "../lib/core/src/contracts/service/NetworkMiddlewareService.sol";

import { OptInService } from "../lib/core/src/contracts/service/OptInService.sol";

import { OperatorRegistry } from "../lib/core/src/contracts/OperatorRegistry.sol";

interface IStakedSPK is IERC20Metadata, IVaultTokenized, IAccessControl {}
