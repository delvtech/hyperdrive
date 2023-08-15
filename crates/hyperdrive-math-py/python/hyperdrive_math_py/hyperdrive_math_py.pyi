"""Stubs for hyperdrive math."""
from . import types

class HyperdriveState:
    """A class representing the hyperdrive contract state."""

    def __init__(
        self, pool_config: types.PoolConfig, pool_info: types.PoolInfo
    ) -> None:
        """Initializes the hyperdrive state.

        Arguments
        ---------
        pool_config : PoolConfig
            Static configuration for the hyperdrive contract.  Set at deploy time.
        pool_info : PoolInfo
            Current state information of the hyperdrive contract.  Includes things like reserve levels and share prices.

        Returns
        -------
        Self
            An instance of a HyperdriveState class.
        """
    def get_spot_price(self) -> str:
        """Gets the spot price of the bond.

        Returns
        -------
        str
            The spot price as a string representation of a solidity uint256 value.
        """
