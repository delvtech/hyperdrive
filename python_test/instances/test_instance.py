import os
from typing import NamedTuple

from agent0 import LocalChain, LocalHyperdrive
from agent0.core.hyperdrive.interactive.local_hyperdrive_agent import LocalHyperdriveAgent
from agent0.ethpy.base import ETH_CONTRACT_ADDRESS
from fixedpointmath import FixedPoint
from hyperdrivetypes.types import (
    ERC20ForwarderFactoryContract,
    HyperdriveFactory,
    HyperdriveFactoryContract,
    IERC20Contract,
    IHyperdrive,
    LPMathContract,
)
from web3 import Web3
from web3.constants import ADDRESS_ZERO
from web3.contract import Contract

DEFAULT_DEPLOYMENT_ID = bytes(28) + bytes.fromhex("deadbeef")
DEFAULT_DEPLOYMENT_SALT = bytes(28) + bytes.fromhex("deadbabe")


class TestInstance:
    """This is the base pytest class that defines test variables and what tests to run."""

    # Test instance configuration

    class InstanceConfig(NamedTuple):
        name: str
        kind: str
        initial_fixed_rate: FixedPoint
        position_duration: int
        # TODO support different decimals
        decimals: int
        base_token_whale_accounts: list[str]
        vault_shares_token_whale_accounts: list[str]
        base_token: str
        vault_shares_token: str
        minimum_share_reserves: FixedPoint
        minimum_transaction_amount: FixedPoint
        fees: IHyperdrive.Fees
        enable_base_deposits: bool
        enable_share_deposits: bool
        enable_base_withdraws: bool
        enable_share_withdraws: bool
        # TODO figure out this error
        # base_withdraw_error = IHyperdriveTypes.UnsupportedTokenError.selector,
        is_rebasing: bool

        # TODO add test tolerances

    def __init__(self, test_config: InstanceConfig):
        self.test_config = self.get_test_config()
        self.is_base_eth = self.test_config.base_token == ETH_CONTRACT_ADDRESS

    def create_user(self, name: str):
        return self.chain.init_agent(name=name, eth=FixedPoint(100))

    def fund_accounts(
        self,
        base_token_contract: IERC20Contract,
        whale_account: str,
        agents: list[LocalHyperdriveAgent],
    ) -> None:
        source_balance = base_token_contract.functions.balanceOf(whale_account).call()
        for agent in agents:
            agent.fund_from_whale(
                base_token_contract,
                whale_account,
                amount=source_balance / len(agents),
                fund_whale_with_eth=True,
            )

    def cleanup(self):
        self.chain.cleanup()

    def setup(self):
        # TODO this function is setting lots of member variables.
        # We may want to clean this up and pass variables around,
        # and only set variables needed by subclasses

        rpc_uri = os.environ["MAINNET_RPC_URL"]

        # Fork mainnet
        self.chain = LocalChain(
            fork_uri=rpc_uri,
            fork_block_number=20_276_503,
            # We don't use db backend in these tests.
            config=LocalChain.Config(verbose=True, no_postgres=True),
        )
        self.web3 = self.chain._web3

        # Initialize agents
        # We fund these accounts with eth
        self.alice = self.create_user("alice")
        self.bob = self.create_user("bob")
        self.celine = self.create_user("celine")

        self.deployer = self.create_user("deployer")
        self.sweep_collector = self.create_user("sweep_collector")

        self.base_token = IERC20Contract.factory(self.web3)(Web3.to_checksum_address(self.test_config.base_token))
        self.vault_shares_token = IERC20Contract.factory(self.web3)(
            Web3.to_checksum_address(self.test_config.vault_shares_token)
        )

        # Fund alice and bob from whales
        for base_whale in self.test_config.base_token_whale_accounts:
            self.fund_accounts(self.base_token, base_whale, [self.alice, self.bob])
        for vault_shares_whale in self.test_config.vault_shares_token_whale_accounts:
            self.fund_accounts(self.vault_shares_token, vault_shares_whale, [self.alice, self.bob])

        self.deploy_factory()

        # Deployer coordinators need the LPMath contract to link against,
        # we deploy it here
        lp_math = LPMathContract.deploy(self.web3, self.alice.account)

        self.deployer_coordinator: Contract = self.deploy_coordinator(self.factory, lp_math)
        _ = self.factory.functions.addDeployerCoordinator(self.deployer_coordinator.address).sign_transact_and_wait(
            self.alice.account,
            validate_transaction=True,
        )

        # Contribution amount is based on specific test config params
        contribution: FixedPoint

        # If share deposits are enabled and the vault shares token isn't a
        # rebasing token, the contribution is the minimum of a tenth of Alice's
        # vault shares balance and 1000 vault shares in units of vault shares.
        if self.test_config.enable_share_deposits and not self.test_config.is_rebasing:
            contribution = min(
                FixedPoint(scaled_value=self.vault_shares_token.functions.balanceOf(self.alice.address).call()) / 10,
                FixedPoint(1_000),
            )
        # If share deposits are enabled and the vault shares token is a
        # rebasing token, the contribution is the minimum of a tenth of Alice's
        # vault shares balance and 1000 vault shares in units of base.
        elif self.test_config.enable_share_deposits:
            contribution = self.convert_to_shares(
                min(
                    FixedPoint(scaled_value=self.vault_shares_token.functions.balanceOf(self.alice.address).call())
                    / 10,
                    FixedPoint(1_000),
                )
            )
        # If share deposits are enabled and the vault shares token is a
        # rebasing token, the contribution is the minimum of a tenth of Alice's
        # vault shares balance and 1000 vault shares in units of base.
        elif self.is_base_eth:
            contribution = min(
                FixedPoint(scaled_value=self.base_token.functions.balanceOf(self.alice.address).call()) / 10,
                FixedPoint(1_000),
            )
        # If share deposits are disabled and the base token is ETH, the
        # contribution is the minimum of a tenth of Alice's ETH balance and
        # 1000 base.
        else:
            contribution = min(
                self.alice.get_eth(),
                FixedPoint(1_000),
            )

        hyperdrive_address = self.deploy_hyperdrive(
            deployment_id=DEFAULT_DEPLOYMENT_ID,
            deployment_salt=DEFAULT_DEPLOYMENT_SALT,
            contribution=contribution,
            as_base=not self.test_config.enable_share_deposits,
        )

        # Create a hyperdrive object with this address to interact with rest of agent0
        self.hyperdrive_pool = LocalHyperdrive(self.chain, hyperdrive_address=hyperdrive_address, deploy=False)

        # No need to approve, interactions with `hyperdrive_pool` will automatically max approve

        # TODO add test to ensure lp amounts are correct

    def deploy_factory(self):
        forwarder_factory = ERC20ForwarderFactoryContract.deploy(
            self.web3,
            account=self.alice.account,
            constructor_args=ERC20ForwarderFactoryContract.ConstructorArgs(name="ForwarderFactory"),
        )

        self.factory = HyperdriveFactoryContract.deploy(
            self.web3,
            account=self.deployer.account,
            constructor_args=HyperdriveFactoryContract.ConstructorArgs(
                factoryConfig=HyperdriveFactory.FactoryConfig(
                    governance=self.alice.address,
                    deployerCoordinatorManager=self.celine.address,
                    hyperdriveGovernance=self.bob.address,
                    feeCollector=self.celine.address,
                    sweepCollector=self.sweep_collector.address,
                    checkpointRewarder=ADDRESS_ZERO,
                    defaultPausers=[self.bob.address],
                    checkpointDurationResolution=3600,  # 1 hour
                    minCheckpointDuration=8 * 3600,  # 8 hours
                    maxCheckpointDuration=24 * 3600,  # 1 day
                    minPositionDuration=7 * 24 * 3600,  # 7 days
                    maxPositionDuration=10 * 365 * 24 * 3600,  # 10 years
                    minCircuitBreakerDelta=FixedPoint(0.15).scaled_value,
                    maxCircuitBreakerDelta=FixedPoint(2).scaled_value,
                    minFixedAPR=FixedPoint("0.001").scaled_value,
                    maxFixedAPR=FixedPoint("0.5").scaled_value,
                    minTimeStretchAPR=FixedPoint("0.005").scaled_value,
                    maxTimeStretchAPR=FixedPoint("0.5").scaled_value,
                    minFees=IHyperdrive.Fees(
                        curve=0,
                        flat=0,
                        governanceLP=0,
                        governanceZombie=0,
                    ),
                    maxFees=IHyperdrive.Fees(
                        curve=FixedPoint(1).scaled_value,
                        flat=FixedPoint(1).scaled_value,
                        governanceLP=FixedPoint(1).scaled_value,
                        governanceZombie=FixedPoint(1).scaled_value,
                    ),
                    linkerFactory=forwarder_factory.address,
                    linkerCodeHash=forwarder_factory.functions.ERC20LINK_HASH().call(),
                ),
                name="HyperdriveFactory",
            ),
        )

        # Update pool configuration
        self.pool_deploy_config = IHyperdrive.PoolDeployConfig(
            baseToken=self.test_config.base_token,
            vaultSharesToken=self.test_config.vault_shares_token,
            linkerFactory=self.factory.functions.linkerFactory().call(),
            linkerCodeHash=self.factory.functions.linkerCodeHash().call(),
            minimumShareReserves=self.test_config.minimum_share_reserves.scaled_value,
            minimumTransactionAmount=self.test_config.minimum_transaction_amount.scaled_value,
            circuitBreakerDelta=FixedPoint(2).scaled_value,
            positionDuration=self.test_config.position_duration,
            checkpointDuration=24 * 3600,  # 1 day
            timeStretch=0,
            governance=self.factory.functions.hyperdriveGovernance().call(),
            feeCollector=self.factory.functions.feeCollector().call(),
            sweepCollector=self.factory.functions.sweepCollector().call(),
            checkpointRewarder=ADDRESS_ZERO,
            fees=self.test_config.fees,
        )

    def deploy_hyperdrive(
        self,
        deployment_id: bytes,
        deployment_salt: bytes,
        contribution: FixedPoint,
        as_base: bool,
    ) -> str:
        for i in range(self.deployer_coordinator.functions.getNumberOfTargets().call()):
            _ = self.factory.functions.deployTarget(
                _deploymentId=deployment_id,
                _deployerCoordinator=self.deployer_coordinator.address,
                _config=self.pool_deploy_config,
                _extraData=self.get_extra_data(),
                _fixedAPR=self.test_config.initial_fixed_rate.scaled_value,
                _timeStretchAPR=self.test_config.initial_fixed_rate.scaled_value,
                _targetIndex=i,
                _salt=deployment_salt,
            ).sign_transact_and_wait(self.alice.account, validate_transaction=True)

        approve_fn = None
        # If base is being used and the base token isn't ETH, we set an
        # approval on the deployer coordinator with the contribution in base.
        if as_base and not self.is_base_eth:
            token = self.base_token
            approve_fn = token.functions.approve(self.deployer_coordinator.address, contribution.scaled_value)

        # If vault shares is being used and the vault shares token isn't a
        # rebasing token, we set an approval on the deployer coordinator
        # with the contribution in vault shares.
        elif not as_base and not self.test_config.is_rebasing:
            token = self.vault_shares_token
            approve_fn = token.functions.approve(self.deployer_coordinator.address, contribution.scaled_value)
        # If vault shares is being used and the vault shares token is a
        # rebasing token, we set an approval on the deployer coordinator
        # with the contribution in base.
        elif not as_base:
            token = self.vault_shares_token
            approve_fn = token.functions.approve(
                self.deployer_coordinator.address, self.convert_to_base(contribution).scaled_value
            )

        assert approve_fn is not None

        approve_fn.sign_transact_and_wait(self.alice.account, validate_transaction=True)

        # TODO catch expected reverts with unsupportedtoken error if depositing
        # not supported.

        # TODO test alice eth balance

        # Deploy hyperdrive
        txn_receipt = self.factory.functions.deployAndInitialize(
            _deploymentId=deployment_id,
            _deployerCoordinator=self.deployer_coordinator.address,
            __name=self.test_config.name,
            _config=self.pool_deploy_config,
            _extraData=self.get_extra_data(),
            _contribution=contribution.scaled_value,
            _fixedAPR=self.test_config.initial_fixed_rate.scaled_value,
            _timeStretchAPR=self.test_config.initial_fixed_rate.scaled_value,
            _options=IHyperdrive.Options(destination=self.alice.address, asBase=as_base, extraData=bytes()),
            _salt=deployment_salt,
        ).sign_transact_and_wait(self.alice.account, validate_transaction=True)

        events = list(self.factory.events.Deployed().process_receipt_typed(txn_receipt))
        assert len(events) == 1
        hyperdrive_address = events[0].args.hyperdrive
        return hyperdrive_address

    #### Abstract functions
    def deploy_coordinator(self, factory: HyperdriveFactoryContract, lp_math_contract: LPMathContract) -> Contract:
        raise NotImplementedError

    def get_extra_data(self) -> bytes:
        raise NotImplementedError

    def convert_to_shares(self, base_amount: FixedPoint) -> FixedPoint:
        raise NotImplementedError

    def convert_to_base(self, share_amount: FixedPoint) -> FixedPoint:
        raise NotImplementedError

    def get_test_config(self) -> InstanceConfig:
        raise NotImplementedError
