"""Tests for hyperdrive_math.rs wrappers"""
from hyperdrive_math_py import HyperdriveState
from hyperdrive_math_py.types import Fees, PoolConfig, PoolInfo

sample_pool_config = PoolConfig(
    base_token="0x1234567890abcdef1234567890abcdef12345678",
    initial_share_price="1000000000000000000",
    minimum_share_reserves="100000000000000000",
    position_duration="604800",
    checkpoint_duration="86400",
    time_stretch="100000000000000000",
    governance="0xabcdef1234567890abcdef1234567890abcdef12",
    fee_collector="0xfedcba0987654321fedcba0987654321fedcba09",
    fees=Fees(curve="0", flat="0", governance="0"),
    oracle_size="10",
    update_gap="3600",
)


sample_pool_info = PoolInfo(
    share_reserves="1000000000000000000",
    bond_reserves="2000000000000000000",
    lp_total_supply="3000000000000000000",
    share_price="4000000000000000000",
    longs_outstanding="5000000000000000000",
    long_average_maturity_time="6000000000000000000",
    shorts_outstanding="7000000000000000000",
    short_average_maturity_time="8000000000000000000",
    short_base_volume="9000000000000000000",
    withdrawal_shares_ready_to_withdraw="2500000000000000000",
    withdrawal_shares_proceeds="3500000000000000000",
    lp_share_price="1000000000000000000",
)


def test_initialization():
    """test initialization."""
    state = HyperdriveState(sample_pool_config, sample_pool_info)
    assert state is not None, "State initialization failed."


def test_get_spot_price():
    """test get_spot_price."""
    state = HyperdriveState(sample_pool_config, sample_pool_info)
    spot_price = state.get_spot_price()
    assert spot_price is not None, "Failed to get spot price."
    assert isinstance(spot_price, str), "Expected spot price to be a string."
