import pytest
from fixedpointmath import FixedPoint
from hyperdrivetypes.types import IHyperdrive, IMorphoBlueHyperdrive
from web3 import Web3
from web3.constants import ADDRESS_ZERO

from .morpho_hyperdrive import TestMorphoHyperdrive

# Test Constants
MORPHO = Web3.to_checksum_address("0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb")
LOAN_TOKEN = Web3.to_checksum_address("0x6B175474E89094C44Da98b954EedeAC495271d0F")
COLLATERAL_TOKEN = Web3.to_checksum_address("0x4c9EDD5852cd905f086C759E8383e09bff1E68B3")
ORACLE = Web3.to_checksum_address("0xaE4750d0813B5E37A51f7629beedd72AF1f9cA35")
IRM = Web3.to_checksum_address("0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC")
LLTV = 860000000000000000

# Whale accounts
LOAN_TOKEN_WHALE = Web3.to_checksum_address("0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb")


class TestMorphoUsdeDaiHyperdrive(TestMorphoHyperdrive):

    @pytest.fixture
    def get_test_config(self) -> TestMorphoHyperdrive.InstanceConfig:
        return TestMorphoHyperdrive.InstanceConfig(
            name="Morpho Blue USDe DAI Hyperdrive",
            kind="MorhpoBlueHyperdrive",
            # TODO support different decimals
            decimals=18,
            base_token_whale_accounts=[LOAN_TOKEN_WHALE],
            vault_shares_token_whale_accounts=[],
            base_token=LOAN_TOKEN,
            vault_shares_token=ADDRESS_ZERO,
            minimum_share_reserves=FixedPoint(scaled_value=int(1e15)),
            minimum_transaction_amount=FixedPoint(scaled_value=int(1e15)),
            position_duration=365 * 24 * 3600,  # 365 days
            fees=IHyperdrive.Fees(
                curve=0,
                flat=0,
                governanceLP=0,
                governanceZombie=0,
            ),
            enable_base_deposits=True,
            enable_share_deposits=False,
            enable_base_withdraws=True,
            enable_share_withdraws=False,
            # TODO figure out this error
            # base_withdraw_error = IHyperdriveTypes.UnsupportedTokenError.selector,
            is_rebasing=False,
            initial_fixed_rate=FixedPoint("0.05"),
            # TODO add in tolerances
            # shares_tolerance = FixedPoint(scaled_value=int(1e15)),
        )

    def get_morpho_params(self) -> IMorphoBlueHyperdrive.MorphoBlueParams:
        return IMorphoBlueHyperdrive.MorphoBlueParams(
            MORPHO,
            COLLATERAL_TOKEN,
            ORACLE,
            IRM,
            LLTV,
        )
