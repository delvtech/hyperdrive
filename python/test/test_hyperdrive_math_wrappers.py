"""Tests for hyperdrive_math.rs wrappers"""
from typing import NamedTuple

from hyperdrive_math import State


class Fees(NamedTuple):
    """Protocal Fees"""

    curve: str
    flat: str
    governance: str


class PoolConfig(NamedTuple):
    """Sample Pool Config"""

    base_token: str
    initial_share_price: str
    minimum_share_reserves: str
    position_duration: str
    checkpoint_duration: str
    time_stretch: str
    governance: str
    fee_collector: str
    fees: Fees
    oracle_size: str
    update_gap: str


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


class PoolInfo(NamedTuple):
    """Sample Pool Info"""

    share_reserves: str
    bond_reserves: str
    lp_total_supply: str
    share_price: str
    longs_outstanding: str
    long_average_maturity_time: str
    shorts_outstanding: str
    short_average_maturity_time: str
    short_base_volume: str
    withdrawal_shares_ready_to_withdraw: str
    withdrawal_shares_proceeds: str
    lp_share_price: str


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
    state = State(sample_pool_config, sample_pool_info)
    assert state is not None, "State initialization failed."


def test_get_spot_price():
    """test get_spot_price."""
    state = State(sample_pool_config, sample_pool_info)
    spot_price = state.get_spot_price()
    assert spot_price is not None, "Failed to get spot price."
    assert isinstance(spot_price, str), "Expected spot price to be a string."
