// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC4626Hyperdrive } from "contracts/src/instances/erc4626/ERC4626Hyperdrive.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";

// This contract stubs out the yield source implementations of `ERC4626Hyperdrive`
// so that we can test the `ERC4626Hyperdrive` contract in isolation.
contract MockERC4626Hyperdrive is ERC4626Hyperdrive {
    constructor(
        string memory __name,
        IHyperdrive.PoolConfig memory _config,
        address _target0,
        address _target1,
        address _target2,
        address _target3
    )
        ERC4626Hyperdrive(
            __name,
            _config,
            _target0,
            _target1,
            _target2,
            _target3
        )
    {}

    function deposit(
        uint256 _amount,
        IHyperdrive.Options calldata _options
    ) public returns (uint256 sharesMinted, uint256 vaultSharePrice) {
        return _deposit(_amount, _options);
    }

    function withdraw(
        uint256 _shares,
        uint256 _sharePrice,
        IHyperdrive.Options calldata _options
    ) public returns (uint256 amountWithdrawn) {
        return _withdraw(_shares, _sharePrice, _options);
    }

    /// @notice Loads the share price from the yield source
    /// @return vaultSharePrice The current share price.
    function pricePerVaultShare()
        public
        view
        returns (uint256 vaultSharePrice)
    {
        return _pricePerVaultShare();
    }
}
