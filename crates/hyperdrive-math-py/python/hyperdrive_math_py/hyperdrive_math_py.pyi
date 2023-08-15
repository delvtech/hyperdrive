"""Stubs for hyperdrive math."""
from __future__ import annotations

from . import types

class HyperdriveState:
    """A class representing the hyperdrive contract state."""

    def __new__(
        cls, pool_config: types.PoolConfig, pool_info: types.PoolInfo
    ) -> HyperdriveState:
        """Create the HyperdriveState instance."""
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
        """
    def get_spot_price(self) -> str:
        """Gets the spot price of the bond.

        Returns
        -------
        str
            The spot price as a string representation of a solidity uint256 value.
        """
    def get_max_long(self, budget: str, maybe_max_iterations: int) -> str:
        """Gets the max amount of bonds that can be purchased for the given budget.

        Parameters
        ----------
        budget : str
            The account budget in base for making a long.
        maybe_max_iterations : int
            The number of iterations to use for the Newtonian method.

        Returns
        -------
        str
            The maximum long as a string representation of a solidity uint256 value.
        """
    def get_max_short(
        self, budget: str, open_share_price: str, maybe_max_iterations: int
    ) -> str:
        """Gets the max amount of bonds that can be shorted for the given budget.
        Parameters

        ----------
        budget : str
            The account budget in base for making a short.
        open_share_price : str
            The share price of underlying vault.
        maybe_max_iterations : int
            The number of iterations to use for the Newtonian method.

        Returns
        -------
        str
            The maximum short as a string representation of a solidity uint256 value.
        """
