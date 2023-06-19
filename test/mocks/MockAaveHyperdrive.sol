// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { AaveHyperdrive, IHyperdrive, IERC20 } from "contracts/src/instances/AaveHyperdrive.sol";
import { IPool } from "@aave/interfaces/IPool.sol";

// We make a contract which can directly access the underlying yield source
// functions so that we can test them directly

contract MockAaveHyperdrive is AaveHyperdrive {
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20 _aToken,
        IPool _pool
    )
        AaveHyperdrive(
            _config,
            _dataProvider,
            _linkerCodeHash,
            _linkerFactory,
            _aToken,
            _pool
        )
    {}

    function deposit(
        uint256 amount,
        bool asUnderlying
    ) public returns (uint256 sharesMinted, uint256 sharePrice) {
        return _deposit(amount, asUnderlying);
    }

    function withdraw(
        uint256 shares,
        address destination,
        bool asUnderlying
    ) public returns (uint256 amountWithdrawn) {
        return _withdraw(shares, destination, asUnderlying);
    }

    /// @notice Loads the share price from the yield source
    /// @return sharePrice The current share price.
    function pricePerShare() public view returns (uint256 sharePrice) {
        return _pricePerShare();
    }
}
