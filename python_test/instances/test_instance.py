from typing import NamedTuple

import pytest
from fixedpointmath import FixedPoint
from hyperdrivetypes import IHyperdriveTypes


class TestInstance():
    """This is the base pytest class that defines test variables and what tests to run."""
    # Test instance configuration
    class InstanceConfig(NamedTuple):
        name: str = ""
        kind: str = ""
        # TODO support different decimals
        decimals: int = 18
        base_token_whale_accounts: list[str] = []
        vault_shares_token_whale_accounts: list[str] = []
        base_token: str = ""
        vault_shares_token: str = ""
        shares_tolerance = FixedPoint(scaled_value=int(1e15)),
        minimum_share_reserves = FixedPoint(scaled_value=int(1e15)),
        minimum_transaction_amount = FixedPoint(scaled_value=int(1e15)),
        position_duration = 365 * 24 * 3600,  # 365 days
        fees = IHyperdriveTypes.Fees(
            curve=0,
            flat=0,
            governanceLP=0,
            governanceZombie=0,
        ),
        enable_base_deposits = True,
        enable_share_deposits = False,
        enable_base_withdraws = True,
        enable_share_withdraws = False,
        # TODO figure out this error
        # base_withdraw_error = IHyperdriveTypes.UnsupportedTokenError.selector,
        is_rebasing = False,
        # Added params
        initial_fixed_rate = FixedPoint("0.05")

        # TODO add test tolerances
    
    @pytest.fixture
    def config(self) -> InstanceConfig:
        return self.InstanceConfig()
    
    def test_test(config: InstanceConfig):
        assert config.name == ""