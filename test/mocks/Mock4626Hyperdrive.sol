// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626Hyperdrive, IERC4626, IHyperdrive } from "contracts/src/instances/ERC4626Hyperdrive.sol";

// We make a contract which can directly access the underlying yield source
// functions so that we can test them directly

contract MockERC4626Hyperdrive is ERC4626Hyperdrive {
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC4626 _pool
    )
        ERC4626Hyperdrive(
            _config,
            _dataProvider,
            _linkerCodeHash,
            _linkerFactory,
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
