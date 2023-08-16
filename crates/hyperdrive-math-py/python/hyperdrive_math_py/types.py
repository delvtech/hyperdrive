"""Types for the hyperdrive contract."""
from typing import NamedTuple


class Fees(NamedTuple):
    """Protocal Fees."""

    curve: str
    flat: str
    governance: str


class PoolConfig(NamedTuple):
    """Static configuration for the hyperdrive contract. Set at deploy time."""

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


class PoolInfo(NamedTuple):
    """Current state information of the hyperdrive contract. Includes things like reserve levels and share prices."""

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
    long_exposure: str
