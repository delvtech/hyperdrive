// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IPool } from "@aave/interfaces/IPool.sol";
import { Hyperdrive } from "../Hyperdrive.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { Errors } from "../libraries/Errors.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

/// @author DELV
/// @title AaveHyperdrive
/// @notice An instance of Hyperdrive that utilizes Aave's lending pool as a yield source.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.

contract AaveHyperdrive is Hyperdrive {
    using FixedPointMath for uint256;

    // The aave deployment details, the a token for this asset and the aave pool
    IERC20 internal immutable aToken;
    IPool internal immutable pool;

    // The shares created by this pool, starts at one to one with deposits and increases
    uint256 internal totalShares;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _dataProvider The address of the data provider.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The factory which is used to deploy the ERC20
    ///        linker contracts.
    /// @param _aToken The assets aToken.
    /// @param _pool The aave pool.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20 _aToken,
        IPool _pool
    ) Hyperdrive(_config, _dataProvider, _linkerCodeHash, _linkerFactory) {
        // Ensure that the Hyperdrive pool was configured properly.
        if (_config.initialSharePrice != FixedPointMath.ONE_18) {
            revert Errors.InvalidInitialSharePrice();
        }

        aToken = _aToken;
        pool = _pool;
        _config.baseToken.approve(address(pool), type(uint256).max);
    }

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
        // Load the balance of this pool
        uint256 assets = aToken.balanceOf(address(this));

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
            pool.supply(address(_baseToken), amount, address(this), 0);
        } else {
            // aTokens are known to be revert on failed transfer tokens
            aToken.transferFrom(msg.sender, address(this), amount);
        }

        // Do share calculations
        uint256 totalShares_ = totalShares;
        if (totalShares_ == 0) {
            totalShares = amount;
            return (amount, FixedPointMath.ONE_18);
        } else {
            uint256 newShares = totalShares_.mulDivDown(amount, assets);
            totalShares += newShares;
            return (newShares, _pricePerShare());
        }
    }

    /// @notice Withdraws shares from the yield source and sends the resulting tokens to the destination
    /// @param shares The shares to withdraw from the yield source
    /// @param asUnderlying If true the yield source will transfer underlying tokens
    ///                     if false it will transfer the yielding asset directly
    /// @param destination The address which is where to send the resulting tokens
    /// @return amountWithdrawn the amount of 'token' produced by this withdraw
    function _withdraw(
        uint256 shares,
        address destination,
        bool asUnderlying
    ) internal override returns (uint256 amountWithdrawn) {
        // The withdrawer receives a proportional amount of the assets held by
        // the contract to the amount of shares that they are redeeming. Small
        // numerical errors can result in the shares value being slightly larger
        // than the total shares, so we clamp the shares to the total shares to
        // avoid reverts.
        uint256 totalShares_ = totalShares;
        if (shares > totalShares_) {
            shares = totalShares_;
        }
        uint256 assets = aToken.balanceOf(address(this));
        uint256 withdrawValue = assets != 0
            ? shares.mulDown(assets.divDown(totalShares_))
            : 0;

        if (withdrawValue == 0) {
            revert Errors.NoAssetsToWithdraw();
        }

        // Remove the shares from the total share supply
        totalShares -= shares;

        // If the user wants underlying we withdraw for them otherwise send the base
        if (asUnderlying) {
            // Now we call aave to fulfill this withdraw for the user
            pool.withdraw(address(_baseToken), withdrawValue, destination);
        } else {
            // Otherwise we simply transfer to them
            aToken.transfer(destination, withdrawValue);
        }

        return withdrawValue;
    }

    /// @notice Loads the share price from the yield source.
    /// @dev This must remain consistent with the impl inside of the DataProvider
    /// @return The current share price.
    function _pricePerShare() internal view override returns (uint256) {
        uint256 assets = aToken.balanceOf(address(this));
        uint256 totalShares_ = totalShares;
        if (totalShares_ != 0) {
            return assets.divDown(totalShares_);
        }
        return 0;
    }
}
