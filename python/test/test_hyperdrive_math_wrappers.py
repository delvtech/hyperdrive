"""Tests for hyperdrive_math.rs wrappers"""
import pytest
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
    share_reserves=str(int(1_000_000 * 1e18)),
    bond_reserves=str(int(2_000_000 * 1e18)),
    lp_total_supply=str(int(3_000_000 * 1e18)),
    share_price=str(int(1e18)),
    longs_outstanding="0",
    long_average_maturity_time="0",
    shorts_outstanding="0",
    short_average_maturity_time="0",
    short_base_volume="0",
    withdrawal_shares_ready_to_withdraw="0",
    withdrawal_shares_proceeds="0",
    lp_share_price=str(int(1e18)),
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


def test_max_long():
    """test get_max_long."""
    state = HyperdriveState(sample_pool_config, sample_pool_info)
    budget = "1000000000000000000"  # 1 base
    max_iterations = 20
    max_long = state.get_max_long(budget, max_iterations)
    expected_max_long = "1000000000000000000"  # 1 base
    assert max_long == expected_max_long


def test_max_long_fail_conversion():
    """test get_max_long."""
    state = HyperdriveState(sample_pool_config, sample_pool_info)
    max_iterations = 20

    # bad string
    budget = "asdf"
    with pytest.raises(ValueError, match="Failed to convert budget string to U256"):
        state.get_max_long(budget, max_iterations)

    # bad string
    budget = "1.23"
    with pytest.raises(ValueError, match="Failed to convert budget string to U256"):
        state.get_max_long(budget, max_iterations)


def test_max_short():
    """test get_max_short."""
    state = HyperdriveState(sample_pool_config, sample_pool_info)
    budget = "10000000000000000000000"  # 10k base
    open_share_price = "1000000000000000000"  # 1 base
    max_iterations = 20
    max_short = state.get_max_short(budget, open_share_price, max_iterations)
    expected_max_short = "2583754033693357393077"  # apprx 2583 base
    assert max_short == expected_max_short


def test_max_short_fail_conversion():
    """test get_max_short."""
    state = HyperdriveState(sample_pool_config, sample_pool_info)
    open_share_price = "1000000000000000000"  # 1 base
    max_iterations = 20

    # bad string
    budget = "asdf"
    with pytest.raises(ValueError, match="Failed to convert budget string to U256"):
        state.get_max_short(budget, open_share_price, max_iterations)

    # bad string
    budget = "1.23"
    with pytest.raises(ValueError, match="Failed to convert budget string to U256"):
        state.get_max_short(budget, open_share_price, max_iterations)

    budget = "10000000000000000000000"  # 10k base
    # bad string
    open_share_price = "asdf"
    with pytest.raises(
        ValueError, match="Failed to convert open_share_price string to U256"
    ):
        state.get_max_short(budget, open_share_price, max_iterations)


def test_max_short_fail_budge():
    """test get_max_short."""
    state = HyperdriveState(sample_pool_config, sample_pool_info)
    open_share_price = "1000000000000000000"  # 1 base
    max_iterations = 20

    # too small, max short requires too much
    budget = "100000000000000000000"  # 100 base
    with pytest.raises(BaseException, match="max short exceeded budget"):
        state.get_max_short(budget, open_share_price, max_iterations)
