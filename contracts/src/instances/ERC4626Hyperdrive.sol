// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC4626 } from "../interfaces/IERC4626.sol";
import { Hyperdrive } from "../Hyperdrive.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { Errors } from "../libraries/Errors.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

contract ERC4626Hyperdrive is Hyperdrive {
    using FixedPointMath for uint256;

    // The yield source contract for this hyperdrive
    IERC4626 internal immutable pool;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _dataProvider The address of the data provider.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The factory which is used to deploy the ERC20
    ///        linker contracts.
    /// @param _pool The ERC4626 compatible yield source
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC4626 _pool
    ) Hyperdrive(_config, _dataProvider, _linkerCodeHash, _linkerFactory) {
        // Ensure that the Hyperdrive pool was configured properly.
        // WARN - 4626 implementations should be checked that if they use an asset
        //        with decimals less than 18 that the preview deposit is scale
        //        invariant. EG - because this line uses a very large query to load
        //        price for USDC if the price per share changes based on size of deposit
        //        then this line will read an incorrect and possibly dangerous price.
        if (
            _config.initialSharePrice !=
            _pool.previewDeposit(FixedPointMath.ONE_18)
        ) {
            revert Errors.InvalidInitialSharePrice();
        }

        // Set immutables and prepare for deposits by setting immutables
        pool = _pool;
        _config.baseToken.approve(address(pool), type(uint256).max);
    }

    /// Yield Source ///

    /// @notice Transfers amount of 'token' from the user and commits it to the yield source.
    /// @param amount The amount of token to transfer
    /// @param asUnderlying If true the yield source will transfer underlying tokens
    ///                     if false it will transfer the yielding asset directly
    /// @return sharesMinted The shares this deposit creates
    /// @return sharePrice The share price at time of deposit
    function _deposit(
        uint256 amount,
        bool asUnderlying
    ) internal override returns (uint256 sharesMinted, uint256 sharePrice) {
        if (asUnderlying) {
            // Transfer from user
            bool success = _baseToken.transferFrom(
                msg.sender,
                address(this),
                amount
            );
            if (!success) {
                revert Errors.TransferFailed();
            }
            // Supply for the user
            sharesMinted = pool.deposit(amount, address(this));
            sharePrice = amount.divDown(sharesMinted);
        } else {
            // Calculate the current exchange rate for these
            // WARN - IF an ERC4626 has significant differences between a
            //        price perShare in aggregate vs one for individual users
            //        then this can create bugs.
            uint256 converted = pool.convertToShares(amount);
            // Transfer erc4626 shares from the user
            bool success = IERC20(address(pool)).transferFrom(
                msg.sender,
                address(this),
                converted
            );
            if (!success) {
                revert Errors.TransferFailed();
            }
            sharesMinted = converted;
            sharePrice = amount.divDown(converted);
        }
    }

    /// @notice Withdraws shares from the yield source and sends the resulting tokens to the destination
    /// @param shares The shares to withdraw from the yield source
    /// @param asUnderlying If true the yield source will transfer underlying tokens
    ///                     if false it will transfer the yielding asset directly
    /// @param destination The address which is where to send the resulting tokens
    /// @return amountWithdrawn the amount of 'token' produced by this withdraw
    /// @return sharePrice The share price on withdraw.
    function _withdraw(
        uint256 shares,
        address destination,
        bool asUnderlying
    ) internal override returns (uint256 amountWithdrawn, uint256 sharePrice) {
        if (asUnderlying) {
            // In this case we simply withdraw
            amountWithdrawn = pool.redeem(shares, destination, address(this));
            sharePrice = amountWithdrawn.divDown(shares);
        } else {
            // Transfer erc4626 shares to the user
            bool success = IERC20(address(pool)).transfer(destination, shares);
            if (!success) {
                revert Errors.TransferFailed();
            }
            // Now we calculate the price per share
            uint256 estimated = pool.convertToAssets(shares);
            sharePrice = estimated.divDown(shares);
            amountWithdrawn = estimated;
        }
    }

    ///@notice Loads the share price from the yield source.
    ///@return The current share price.
    function _pricePerShare() internal view override returns (uint256) {
        uint256 shareEstimate = pool.convertToShares(FixedPointMath.ONE_18);
        return (FixedPointMath.ONE_18.divDown(shareEstimate));
    }
}
