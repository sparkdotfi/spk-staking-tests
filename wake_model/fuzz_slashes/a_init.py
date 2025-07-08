from copy import deepcopy
from ..common import *

@dataclass
class Request:
    time_cap: int
    time_req: int
    amount: int
    executed: bool = False

@dataclass
class Execution:
    time_cap: int
    time_req: int
    time_exec: int
    cumulative_slash: int
    amount: int

@dataclass
class Stats:
    request_slash: Dict[bool, int] = field(default_factory=lambda: defaultdict(int))
    execute_slash: Dict[bool, int] = field(default_factory=lambda: defaultdict(int))

class Init(FuzzTest):

    def __init__(s):
        super().__init__()
        s.stats = Stats()

    def cumulative_slash_at(s, time_cap: int) -> int:
        # To detemrine whether to use bisect_left or bisect_right, consider this example:
        # l = [1,2,3]
        # bisect.bisect_left(l, 1.5) == 1 ==bisect.bisect_right(l, 1.5)
        # bisect.bisect_left(l, 1) == 0, but bisect.bisect_right(l, 1) == 1
        # since we end up using i_idx - 1, w need bisect.bisect_right (to align with upperLookupRecent).
        i_idx = bisect.bisect_right([exec.time_exec for exec in s.executed_slashes], time_cap)
        print(f"cumulative_slash_at: i_idx: {i_idx}, time_cap: {time_cap}")
        assert i_idx == 0 or s.executed_slashes[i_idx - 1].time_exec <= time_cap
        assert i_idx == len(s.executed_slashes) or s.executed_slashes[i_idx].time_exec >= time_cap
        ret = s.executed_slashes[i_idx - 1].cumulative_slash if i_idx > 0 else 0
        return ret

    @override
    def pre_sequence(s):
        s.requested_slashes: List[Request] = []
        s.executed_slashes: List[Execution] = []
        # Unless we need otherwise, think of these as EOAs:
        s.DEPLOYER, s.SPARK_MULTISIG, s.SPARK_GOVERNANCE, s.OPERATOR, s.HYPERLANE_NETWORK, s.ALICE = (
            chain.accounts[:6]
        )
        s.DEPLOYER.label = "'DEPLOYER'"
        s.SPARK_MULTISIG.label = "'SPARK MULTISIG'"
        s.SPARK_GOVERNANCE.label = "'SPARK GOVERNANCE'"
        s.OPERATOR.label = "'OPERATOR'"
        s.HYPERLANE_NETWORK.label = "'HYPERLANE NETWORK'"
        s.SUBNETWORK = bytes.fromhex(
            s.HYPERLANE_NETWORK.address._address.removeprefix("0x")
        ) + bytes(12) # Subnetwork.subnetwork(network, 0)

        s.SPK = ERC20Mock.deploy()
        s.SPK.label = "'SPK'"

        s.BURNER_ROUTER_IMPL = BurnerRouter.deploy()
        s.BURNER_ROUTER_IMPL.label = "'BURNER ROUTER IMPL'"
        s.BURNER_ROUTER_FAC = BurnerRouterFactory.deploy(s.BURNER_ROUTER_IMPL)
        s.BURNER_ROUTER_FAC.label = "'BURNER ROUTER FACTORY'"
        tx_burner = s.BURNER_ROUTER_FAC.create(IBurnerRouter.InitParams(
            owner=s.SPARK_MULTISIG.address,
            collateral=s.SPK.address,
            delay=31 * 24 * 60 * 60,  # 31 days in seconds
            globalReceiver=s.SPARK_GOVERNANCE.address,
            networkReceivers=[],
            operatorNetworkReceivers=[],
        ))
        s.BURNER_ROUTER = BurnerRouter(tx_burner.return_value)
        s.BURNER_ROUTER.label = "'BURNER ROUTER'"

        # First deploy 3 factories.
        s.VAULT_FACTORY = VaultFactory.deploy(s.DEPLOYER) # owner_
        s.VAULT_FACTORY.label = "'VAULT FACTORY'"
        s.DELEGATOR_FACTORY = DelegatorFactory.deploy(s.DEPLOYER) # owner_
        s.DELEGATOR_FACTORY.label = "'DELEGATOR FACTORY'"
        s.SLASHER_FACTORY = SlasherFactory.deploy(s.DEPLOYER) # owner_
        s.SLASHER_FACTORY.label = "'SLASHER FACTORY'"

        # Next, deploy Vault implementation
        s.VAULT_IMPL = Vault.deploy(s.DELEGATOR_FACTORY, s.SLASHER_FACTORY, s.VAULT_FACTORY)
        s.VAULT_IMPL.label = "'VAULT IMPL'"
        s.TOKENIZED_VAULT_IMPL = VaultTokenized.deploy(s.DELEGATOR_FACTORY, s.SLASHER_FACTORY, s.VAULT_FACTORY)
        s.TOKENIZED_VAULT_IMPL.label = "'TOKENIZED VAULT IMPL'"

        # Then, whitelist this in the factory
        s.VAULT_FACTORY.whitelist(s.VAULT_IMPL)
        s.VAULT_FACTORY.whitelist(s.TOKENIZED_VAULT_IMPL)

        # Deploy OperatorVaultOptInService and OperatorNetworkOptInService
        # They both need a Who Registry and a Where Registry.
        # On-chain, we have:
        #   VaultOptInService.WHO_REGISTRY == 0xAd817a6Bc954F678451A71363f04150FDD81Af9F (OperatorRegistry)
        #   VaultOptInService.WHERE_REGISTRY == VaultFactory == 0xAEb6bdd95c502390db8f52c8909F703E9Af6a346
        #   NetworkOptInService.WHO_REGISTRY == 0xAd817a6Bc954F678451A71363f04150FDD81Af9F (OperatorRegistry)
        #   NetworkOptInService.WHERE_REGISTRY == NetworkRegistry == 0xC773b1011461e7314CF05f97d95aa8e92C1Fd8aA
        # Hence we'll deploy just one Who registry.

        s.NETWORK_REGISTRY = NetworkRegistry.deploy()
        s.NETWORK_REGISTRY.label = "'NETWORK REGISTRY'"

        s.NETWORK_REGISTRY.registerNetwork(from_=s.HYPERLANE_NETWORK)

        s.OPERATOR_REGISTRY = OperatorRegistry.deploy()
        s.OPERATOR_REGISTRY.label = "'OPERATOR REGISTRY'"

        s.OPERATOR_REGISTRY.registerOperator(from_=s.OPERATOR)

        s.OPERATOR_VAULT_OPT_IN_SERVICE = OptInService.deploy(
            s.OPERATOR_REGISTRY.address, s.VAULT_FACTORY.address, ""
        )
        s.OPERATOR_VAULT_OPT_IN_SERVICE.label = "'OPERATOR VAULT OPT IN SERVICE'"

        s.OPERATOR_NETWORK_OPT_IN_SERVICE = OptInService.deploy(
            s.OPERATOR_REGISTRY.address, s.NETWORK_REGISTRY.address, ""
        )
        s.OPERATOR_NETWORK_OPT_IN_SERVICE.label = "'OPERATOR NETWORK OPT IN SERVICE'"

        # Whitelist
        s.NETWORK_RESTAKE_DELEGATOR_IMPL = NetworkRestakeDelegator.deploy(
            s.NETWORK_REGISTRY.address,
            s.VAULT_FACTORY.address,
            s.OPERATOR_VAULT_OPT_IN_SERVICE.address,
            s.OPERATOR_NETWORK_OPT_IN_SERVICE.address,
            s.DELEGATOR_FACTORY.address,
            0,
        )
        s.NETWORK_RESTAKE_DELEGATOR_IMPL.label = "'NETWORK RESTAKE DELEGATOR IMPL'"
        s.DELEGATOR_FACTORY.whitelist(s.NETWORK_RESTAKE_DELEGATOR_IMPL)

        # Network Middleware Service. Allows each network to set a middleware.
        s.MIDDLEWARE_SERVICE = NetworkMiddlewareService.deploy(s.NETWORK_REGISTRY.address)
        s.MIDDLEWARE_SERVICE.label = "'MIDDLEWARE SERVICE'"

        s.BASE_SLASHER_IMPL = Slasher.deploy(
            s.VAULT_FACTORY.address, s.MIDDLEWARE_SERVICE.address, s.SLASHER_FACTORY.address, 0
        )
        s.BASE_SLASHER_IMPL.label = "'BASE SLASHER IMPL'"
        s.VETO_SLASHER_IMPL = VetoSlasher.deploy(
            s.VAULT_FACTORY.address, s.MIDDLEWARE_SERVICE.address, s.NETWORK_REGISTRY.address, s.SLASHER_FACTORY.address, 1
        )
        s.VETO_SLASHER_IMPL.label = "'VETO SLASHER IMPL'"
        s.SLASHER_FACTORY.whitelist(s.BASE_SLASHER_IMPL)
        s.SLASHER_FACTORY.whitelist(s.VETO_SLASHER_IMPL)

        s.VAULT_CONFIGURATOR = VaultConfigurator.deploy(s.VAULT_FACTORY, s.DELEGATOR_FACTORY, s.SLASHER_FACTORY)
        s.VAULT_CONFIGURATOR.label = "'VAULT CONFIGURATOR'"
        tx_others = s.VAULT_CONFIGURATOR.create(IVaultConfigurator.InitParams(
            version = 2,
            owner = s.SPARK_MULTISIG.address,
            vaultParams = bytearray(abi.encode(IVaultTokenized.InitParamsTokenized(
                baseParams = IVault.InitParams(
                    collateral = s.SPK.address,
                    burner = s.BURNER_ROUTER.address,
                    epochDuration = 14 * 24 * 60 * 60,  # 14 days
                    depositWhitelist = False,
                    isDepositLimit = False,
                    depositLimit = 0,
                    defaultAdminRoleHolder = s.SPARK_MULTISIG.address,
                    depositWhitelistSetRoleHolder = s.SPARK_MULTISIG.address,
                    depositorWhitelistRoleHolder = s.SPARK_MULTISIG.address,
                    isDepositLimitSetRoleHolder = s.SPARK_MULTISIG.address,
                    depositLimitSetRoleHolder = s.SPARK_MULTISIG.address,
                ),
                name = "Staked Spark",
                symbol = "stSPK",
            ))),
            delegatorIndex = 0,
            delegatorParams = bytearray(abi.encode(INetworkRestakeDelegator.InitParams(
                baseParams = IBaseDelegator.BaseParams(
                    defaultAdminRoleHolder = s.SPARK_MULTISIG.address,
                    hook = Address(0),
                    hookSetRoleHolder = s.SPARK_MULTISIG.address,
                ),
                networkLimitSetRoleHolders = [s.SPARK_MULTISIG.address],
                operatorNetworkSharesSetRoleHolders = [s.SPARK_MULTISIG.address],
            ))),
            withSlasher = True,
            slasherIndex = 1,
            slasherParams = bytearray(abi.encode(IVetoSlasher.InitParams(
                baseParams = IBaseSlasher.BaseParams(
                    isBurnerHook = True,
                ),
                vetoDuration = 3 * 24 * 60 * 60, # 3 days
                resolverSetEpochsDelay = 3,
            )))
        ))
        s.TOKENIZED_VAULT = VaultTokenized(tx_others.return_value[0])
        s.TOKENIZED_VAULT.label = "'TOKENIZED VAULT'"
        s.NETWORK_DELEGATOR = NetworkRestakeDelegator(tx_others.return_value[1])
        s.NETWORK_DELEGATOR.label = "'NETWORK DELEGATOR'"
        s.VETO_SLASHER = VetoSlasher(tx_others.return_value[2])
        s.VETO_SLASHER.label = "'VETO SLASHER'"

        assert s.MIDDLEWARE_SERVICE.address == s.VETO_SLASHER.NETWORK_MIDDLEWARE_SERVICE()

        # --- Step 1: Do configurations as network, setting middleware, max network limit, and resolver

        # From/As the Network, set its Middleware to be itself. (NetworkMiddlewareService.sol)
        s.MIDDLEWARE_SERVICE.setMiddleware(s.HYPERLANE_NETWORK, from_=s.HYPERLANE_NETWORK)
        # As the Network, set the network limit of the Subnetwork with identifier 0. (BaseDelegator.sol)
        s.NETWORK_DELEGATOR.setMaxNetworkLimit(0, int(Decimal("100_000e18")), from_=s.HYPERLANE_NETWORK);
        # As the Network, set the resolver. (VetoSlasher.sol)
        s.VETO_SLASHER.setResolver(0, s.SPARK_MULTISIG.address, bytes(), from_=s.HYPERLANE_NETWORK);

        # --- Step 2: Configure the network and operator to take control of 100k SPK stake as the vault owner

        # Owner Multisig has NETWORK_LIMIT_SET_ROLE == 0x008b9b1e5fa9cf3b14f87f435649268146305ddf689f082e5961a335b07a9abf
        # (NetworkRestakeDelegator.sol)
        s.NETWORK_DELEGATOR.setNetworkLimit(s.SUBNETWORK, int(Decimal("100_000e18")), from_ = s.SPARK_MULTISIG);
        # Owner Multisig has OPERATOR_NETWORK_SHARES_SET_ROLE
        # == 0x1312a1cf530e56add9be4fd84db9051dcc7635952f09f735f9a29405b5584625 (NetworkRestakeDelegator.sol)
        s.NETWORK_DELEGATOR.setOperatorNetworkShares(
            s.SUBNETWORK,
            s.OPERATOR,
            int(1e18),  # 100% shares
            from_ = s.SPARK_MULTISIG
        )

        time_now = chain.blocks[-1].timestamp
        # (NetworkRestakeDelegator.sol)
        assert s.NETWORK_DELEGATOR.totalOperatorNetworkSharesAt(s.SUBNETWORK, time_now, bytes()) == 1e18

        # --- Step 3: Opt in to the vault as the operator
        # optIn(where=TOKENIZED_VAULT), calls _optIn(who=msg.sender, where=where) in OptInService.sol
        IOptInService(s.NETWORK_DELEGATOR.OPERATOR_VAULT_OPT_IN_SERVICE()).optIn(s.TOKENIZED_VAULT, from_=s.OPERATOR)
        IOptInService(s.NETWORK_DELEGATOR.OPERATOR_NETWORK_OPT_IN_SERVICE()).optIn(s.HYPERLANE_NETWORK, from_=s.OPERATOR)

        mint_erc20(s.SPK, s.ALICE, int(Decimal("10_000_000e18")))
        s.SPK.approve(s.TOKENIZED_VAULT, int(Decimal("10_000_000e18")), from_ = s.ALICE)
        s.TOKENIZED_VAULT.deposit(s.ALICE, int(Decimal("10_000_000e18")), from_=s.ALICE)

        timestamp = chain.blocks[-1].timestamp
        chain.mine(lambda x: x+1)
        assert s.NETWORK_DELEGATOR.totalOperatorNetworkSharesAt(s.SUBNETWORK, timestamp, bytes()) == 1e18
        assert s.NETWORK_DELEGATOR.operatorNetworkSharesAt(s.SUBNETWORK, s.OPERATOR, timestamp, bytes()) == int(1e18)
        assert s.TOKENIZED_VAULT.activeStakeAt(timestamp, bytes()) == int(Decimal("10_000_000e18"))
        assert s.NETWORK_DELEGATOR.networkLimitAt(s.SUBNETWORK, timestamp, bytes()) == int(Decimal("100_000e18"))
        assert s.OPERATOR_VAULT_OPT_IN_SERVICE.isOptedInAt(s.OPERATOR, s.TOKENIZED_VAULT, timestamp, bytes())
        assert s.OPERATOR_NETWORK_OPT_IN_SERVICE.isOptedInAt(s.OPERATOR, s.HYPERLANE_NETWORK, timestamp, bytes())
        assert s.NETWORK_DELEGATOR.stakeAt(s.SUBNETWORK, s.OPERATOR, timestamp, bytes()) == int(Decimal("100_000e18"))
        assert s.VETO_SLASHER.slashableStake(s.SUBNETWORK, s.OPERATOR, timestamp, bytes()) == int(Decimal("100_000e18"))
        # Advance 11 days
        chain.mine(lambda x: x + 11 * 24 * 60 * 60)

    @override
    def pre_flow(s, flow: Callable[..., None]):
        with open(P_FLOWS_AND_TRANSACTIONS, 'a') as f:
            _ = f.write(f'{s.sequence_num},{s.flow_num},{flow.__name__}\n')
        print("-" * 40)
        print(f"Starting flow #{s.flow_num}: `{flow.__name__}`")

    @override
    def post_flow(s, flow: Callable[..., None]):
        print("-" * 40)

    # @override
    # def post_sequence(s):
    #
