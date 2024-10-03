from __future__ import annotations

from typing import NamedTuple

import eth_abi
from fixedpointmath import FixedPoint
from hyperdrivetypes import (
    ERC20ForwarderFactoryContract,
    HyperdriveFactoryContract,
    HyperdriveFactoryTypes,
    IERC20Contract,
    IHyperdriveTypes,
    IMorphoBlueHyperdriveTypes,
    LPMathContract,
    MorphoBlueConversionsContract,
    MorphoBlueHyperdriveCoreDeployerContract,
    MorphoBlueHyperdriveDeployerCoordinatorContract,
    MorphoBlueTarget0DeployerContract,
    MorphoBlueTarget1DeployerContract,
    MorphoBlueTarget2DeployerContract,
    MorphoBlueTarget3DeployerContract,
    MorphoBlueTarget4DeployerContract,
)
from hyperdrivetypes.types.utilities import dataclass_to_tuple
from web3 import Web3
from web3.constants import ADDRESS_ZERO

from agent0 import LocalChain, LocalHyperdrive
from agent0.ethpy.base import smart_contract_preview_transaction, smart_contract_transact
from agent0.ethpy.base.receipts import get_transaction_logs

# from hyperdrivetypes import HyperdriveFactoryTypes


# Args
RPC_URI = "https://eth-mainnet.g.alchemy.com/v2/2qg4GOrWeAwTChEehEMKVeDSRWBctvPT"

# Test Constants
MORPHO = Web3.to_checksum_address("0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb")
LOAN_TOKEN = Web3.to_checksum_address("0x6B175474E89094C44Da98b954EedeAC495271d0F")
COLLATERAL_TOKEN = Web3.to_checksum_address("0x4c9EDD5852cd905f086C759E8383e09bff1E68B3")
ORACLE = Web3.to_checksum_address("0xaE4750d0813B5E37A51f7629beedd72AF1f9cA35")
IRM = Web3.to_checksum_address("0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC")
LLTV = 860000000000000000

FIXED_RATE = FixedPoint("0.05")


# Whale accounts
LOAN_TOKEN_WHALE = Web3.to_checksum_address("0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb")

# Added constants
LPMATH = Web3.to_checksum_address("0xdf5d682404b0611f46f2626d9d5a37eb6a6fd27d")
MORPHO_BLUE_CONVERSIONS = Web3.to_checksum_address("0x1a4cee4e32ea51ec7671a0fd7333ca64fbf004f0")


# Test instance configuration
class InstanceTestConfig(NamedTuple):
    name: str = "Morpho Blue USDe DAI Hyperdrive"
    kind: str = "MorhpoBlueHyperdrive"
    # TODO support different decimals
    decimals: int = 18
    base_token_whale_accounts: list[str] = [LOAN_TOKEN_WHALE]
    vault_shares_token_whale_accounts: list[str] = []
    base_token: str = LOAN_TOKEN
    vault_shares_token: str = ADDRESS_ZERO
    shares_tolerance: FixedPoint = FixedPoint(scaled_value=int(1e15))
    minimum_share_reserves: FixedPoint = FixedPoint(scaled_value=int(1e15))
    minimum_transaction_amount: FixedPoint = FixedPoint(scaled_value=int(1e15))
    position_duration = 365 * 24 * 3600  # 365 days
    fees = IHyperdriveTypes.Fees(
        curve=0,
        flat=0,
        governanceLP=0,
        governanceZombie=0,
    )
    enable_base_deposits = True
    enable_share_deposits = False
    enable_base_withdraws = True
    enable_share_withdraws = False
    base_withdraw_error = IHyperdriveTypes.UnsupportedTokenError.selector
    is_rebasing = False

    # TODO add test tolerances


TEST_CONFIG = InstanceTestConfig()


# Fork mainnet
with LocalChain(
    fork_uri=RPC_URI,
    # fork_block_number=20_276_503,
    config=LocalChain.Config(verbose=True),
) as chain:

    # Initialize deployer
    # Deployer is anvil account 0
    deployer = chain.init_agent(private_key=chain.get_deployer_account_private_key(), name="deployer")

    # Initialize accounts
    # We fund these accounts with eth
    alice = chain.init_agent(name="alice", eth=FixedPoint(100))
    bob = chain.init_agent(name="bob", eth=FixedPoint(100))
    celine = chain.init_agent(name="celine", eth=FixedPoint(100))
    sweep_collector = chain.init_agent(name="sweep_collector", eth=FixedPoint(100))

    # We fund alice and bob from whales
    base_token_contract = IERC20Contract.factory(chain._web3)(Web3.to_checksum_address(TEST_CONFIG.base_token))
    alice.fund_from_whale(base_token_contract, LOAN_TOKEN_WHALE, amount=FixedPoint(10000), fund_whale_with_eth=True)
    bob.fund_from_whale(base_token_contract, LOAN_TOKEN_WHALE, amount=FixedPoint(10000), fund_whale_with_eth=True)

    # Deploy hyperdrive
    forwarder_factory = ERC20ForwarderFactoryContract.deploy(
        chain._web3,
        account=deployer.account,
        constructor_args=ERC20ForwarderFactoryContract.ConstructorArgs(name="ForwarderFactory"),
    )

    factory = HyperdriveFactoryContract.deploy(
        chain._web3,
        account=deployer.account,
        constructor_args=HyperdriveFactoryContract.ConstructorArgs(
            factoryConfig=HyperdriveFactoryTypes.FactoryConfig(
                governance=alice.address,
                deployerCoordinatorManager=celine.address,
                hyperdriveGovernance=bob.address,
                feeCollector=celine.address,
                sweepCollector=sweep_collector.address,
                checkpointRewarder=ADDRESS_ZERO,
                defaultPausers=[bob.address],
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
                minFees=IHyperdriveTypes.Fees(
                    curve=0,
                    flat=0,
                    governanceLP=0,
                    governanceZombie=0,
                ),
                maxFees=IHyperdriveTypes.Fees(
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
    pool_deploy_config = IHyperdriveTypes.PoolDeployConfig(
        baseToken=TEST_CONFIG.base_token,
        vaultSharesToken=TEST_CONFIG.vault_shares_token,
        linkerFactory=factory.functions.linkerFactory().call(),
        linkerCodeHash=factory.functions.linkerCodeHash().call(),
        minimumShareReserves=TEST_CONFIG.minimum_share_reserves.scaled_value,
        minimumTransactionAmount=TEST_CONFIG.minimum_transaction_amount.scaled_value,
        circuitBreakerDelta=FixedPoint(2).scaled_value,
        positionDuration=TEST_CONFIG.position_duration,
        checkpointDuration=24 * 3600,  # 1 day
        timeStretch=0,
        governance=factory.functions.hyperdriveGovernance().call(),
        feeCollector=factory.functions.feeCollector().call(),
        sweepCollector=factory.functions.sweepCollector().call(),
        checkpointRewarder=ADDRESS_ZERO,
        fees=TEST_CONFIG.fees,
    )

    # Set the deployer coordinator address and add to the factory
    lpmath_contract = LPMathContract.factory(chain._web3)(LPMATH)

    # TODO linking to existing contract on mainnet here doesn't work
    # morpho_blue_conversions_contract = MorphoBlueConversionsContract.deploy(chain._web3, account=alice.account)
    morpho_blue_conversions_contract = MorphoBlueConversionsContract.factory(chain._web3)(MORPHO_BLUE_CONVERSIONS)

    deployer_coordinator = MorphoBlueHyperdriveDeployerCoordinatorContract.deploy(
        chain._web3,
        account=alice.account,
        constructor_args=MorphoBlueHyperdriveDeployerCoordinatorContract.ConstructorArgs(
            name=TEST_CONFIG.name + "DeployerCoordinator",
            factory=factory.address,
            coreDeployer=MorphoBlueHyperdriveCoreDeployerContract.deploy(
                chain._web3,
                account=alice.account,
            ).address,
            target0Deployer=MorphoBlueTarget0DeployerContract.deploy(
                chain._web3,
                account=alice.account,
                link_references=MorphoBlueTarget0DeployerContract.LinkReferences(
                    MorphoBlueConversions=morpho_blue_conversions_contract, LPMath=lpmath_contract
                ),
            ).address,
            target1Deployer=MorphoBlueTarget1DeployerContract.deploy(
                chain._web3,
                account=alice.account,
                link_references=MorphoBlueTarget1DeployerContract.LinkReferences(
                    MorphoBlueConversions=morpho_blue_conversions_contract, LPMath=lpmath_contract
                ),
            ).address,
            target2Deployer=MorphoBlueTarget2DeployerContract.deploy(
                chain._web3,
                account=alice.account,
                link_references=MorphoBlueTarget2DeployerContract.LinkReferences(
                    MorphoBlueConversions=morpho_blue_conversions_contract, LPMath=lpmath_contract
                ),
            ).address,
            target3Deployer=MorphoBlueTarget3DeployerContract.deploy(
                chain._web3,
                account=alice.account,
                link_references=MorphoBlueTarget3DeployerContract.LinkReferences(
                    MorphoBlueConversions=morpho_blue_conversions_contract, LPMath=lpmath_contract
                ),
            ).address,
            target4Deployer=MorphoBlueTarget4DeployerContract.deploy(
                chain._web3,
                account=alice.account,
                link_references=MorphoBlueTarget4DeployerContract.LinkReferences(
                    MorphoBlueConversions=morpho_blue_conversions_contract, LPMath=lpmath_contract
                ),
            ).address,
        ),
        link_references=MorphoBlueHyperdriveDeployerCoordinatorContract.LinkReferences(
            MorphoBlueConversions=morpho_blue_conversions_contract,
        ),
    )

    txn_func = factory.functions.addDeployerCoordinator(deployer_coordinator.address)
    # TODO make it easier to send transactions via pypechain
    txn_receipt = smart_contract_transact(
        chain._web3,
        factory,
        alice.account,
        txn_func.fn_name,
        *txn_func.args,
    )
    assert txn_receipt["status"] == 1

    # Deploy hyperdrive
    deployment_id = bytes(28) + bytes.fromhex("deadbeef")
    salt = bytes(28) + bytes.fromhex("deadbabe")

    # TODO encoded market id isn't matching up with MARKET_ID in test
    morpho_blue_params = IMorphoBlueHyperdriveTypes.MorphoBlueParams(MORPHO, COLLATERAL_TOKEN, ORACLE, IRM, LLTV)
    morpho_blue_params = dataclass_to_tuple(morpho_blue_params)
    encoded_market_id = eth_abi.encode(  # type: ignore
        ("address", "address", "address", "address", "uint256"), morpho_blue_params
    )

    for i in range(deployer_coordinator.functions.getNumberOfTargets().call()):
        # TODO make it easier to send transactions via pypechain
        txn_func = factory.functions.deployTarget(
            deploymentId=deployment_id,
            deployerCoordinator=deployer_coordinator.address,
            config=pool_deploy_config,
            extraData=encoded_market_id,
            fixedAPR=FIXED_RATE.scaled_value,
            timeStretchAPR=FIXED_RATE.scaled_value,
            targetIndex=i,
            salt=salt,
        )

        txn_receipt = smart_contract_transact(
            chain._web3,
            factory,
            alice.account,
            txn_func.fn_name,
            *txn_func.args,
        )
        assert txn_receipt["status"] == 1

    # TODO add cases for contribution
    contribution = FixedPoint(1000)

    # TODO make it easier to send transactions via pypechain
    txn_func = base_token_contract.functions.approve(deployer_coordinator.address, contribution.scaled_value)
    txn_receipt = smart_contract_transact(
        chain._web3,
        base_token_contract,
        alice.account,
        txn_func.fn_name,
        *txn_func.args,
    )
    assert txn_receipt["status"] == 1

    # Deploy hyperdrive
    txn_func = factory.functions.deployAndInitialize(
        deploymentId=deployment_id,
        deployerCoordinator=deployer_coordinator.address,
        name=TEST_CONFIG.name,
        config=pool_deploy_config,
        extraData=encoded_market_id,
        contribution=contribution.scaled_value,
        fixedAPR=FIXED_RATE.scaled_value,
        timeStretchAPR=FIXED_RATE.scaled_value,
        options=IHyperdriveTypes.Options(destination=alice.address, asBase=True, extraData=bytes()),
        salt=salt,
    )
    txn_receipt = smart_contract_transact(
        chain._web3,
        factory,
        alice.account,
        txn_func.fn_name,
        *txn_func.args,
    )
    assert txn_receipt["status"] == 1

    logs = get_transaction_logs(factory, txn_receipt)
    hyperdrive_address: str | None = None
    for log in logs:
        if log["event"] == "Deployed":
            hyperdrive_address = log["args"]["hyperdrive"]
    if hyperdrive_address is None:
        raise AssertionError("Generating hyperdrive contract didn't return address")

    # Create a hyperdrive object with this address to interact with rest of agent0
    hyperdrive_pool = LocalHyperdrive(chain, hyperdrive_address=hyperdrive_address, deploy=False)

    # Make trades
    event = bob.add_liquidity(base=FixedPoint(1), pool=hyperdrive_pool)
    pass
