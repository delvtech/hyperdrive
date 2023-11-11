// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ERC4626Hyperdrive } from "contracts/src/instances/ERC4626Hyperdrive.sol";

// This contract stubs out the yield source implementations of `ERC4626Hyperdrive`
// so that we can test the `ERC4626Hyperdrive` contract in isolation.
contract MockERC4626Hyperdrive is ERC4626Hyperdrive {
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _target0,
        address _target1,
        IERC4626 _pool,
        address[] memory _sweepTargets
    ) ERC4626Hyperdrive(_config, _target0, _target1, _pool, _sweepTargets) {}

    function deposit(
        uint256 _amount,
        IHyperdrive.Options calldata _options
    ) public returns (uint256 sharesMinted, uint256 sharePrice) {
        return _deposit(_amount, _options);
    }

    function withdraw(
        uint256 _shares,
        IHyperdrive.Options calldata _options
    ) public returns (uint256 amountWithdrawn) {
        return _withdraw(_shares, _options);
    }

    /// @notice Loads the share price from the yield source
    /// @return sharePrice The current share price.
    function pricePerShare() public view returns (uint256 sharePrice) {
        return _pricePerShare();
    }
}
