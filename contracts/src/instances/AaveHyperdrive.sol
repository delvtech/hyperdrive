// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Hyperdrive } from "../Hyperdrive.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { Errors } from "../libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

interface Pool {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(address asset, uint256 amount, address to) external;
}

contract AaveHyperdrive is Hyperdrive {
    using FixedPointMath for uint256;

    // The aave deployment details, the a token for this asset and the aave pool
    IERC20 public immutable aToken;
    Pool public immutable pool;
    // The shares created by this pool, starts at 1 to one with deposits and increases
    uint256 public totalShares;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The factory which is used to deploy the ERC20
    ///        linker contracts.
    /// @param _baseToken The base token contract.
    /// @param _checkpointsPerTerm The number of checkpoints that elapses before
    ///        bonds can be redeemed one-to-one for base.
    /// @param _checkpointDuration The time in seconds between share price
    ///        checkpoints. Position duration must be a multiple of checkpoint
    ///        duration.
    /// @param _timeStretch The time stretch of the pool.
    /// @param _fees The fees to apply to trades.
    /// @param _governance The governance address.
    constructor(
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20 _baseToken,
        uint256 _checkpointsPerTerm,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        IERC20 _aToken,
        Pool _pool,
        IHyperdrive.Fees memory _fees,
        address _governance
    )
        Hyperdrive(
            _linkerCodeHash,
            _linkerFactory,
            _baseToken,
            FixedPointMath.ONE_18,
            _checkpointsPerTerm,
            _checkpointDuration,
            _timeStretch,
            _fees,
            _governance
        )
    {
        aToken = _aToken;
        pool = _pool;
    }

    ///@notice Transfers amount of 'token' from the user and commits it to the yield source.
    ///@param amount The amount of token to transfer
    /// @param asUnderlying If true the yield source will transfer underlying tokens
    ///                     if false it will transfer the yielding asset directly
    ///@return sharesMinted The shares this deposit creates
    ///@return sharePrice The share price at time of deposit
    function _deposit(
        uint256 amount,
        bool asUnderlying
    ) internal override returns (uint256 sharesMinted, uint256 sharePrice) {
        // Load the balance of this pool
        uint256 assets = aToken.balanceOf(address(this));

        if (asUnderlying) {
            // Transfer from user
            bool success = baseToken.transferFrom(
                msg.sender,
                address(this),
                amount
            );
            if (!success) {
                revert Errors.TransferFailed();
            }
            // Supply for the user
            pool.supply(address(baseToken), amount, address(this), 0);
        } else {
            // aTokens are known to be revert on failed transfer tokens
            aToken.transferFrom(msg.sender, address(this), amount);
        }

        // Do share calculations
        if (totalShares == 0) {
            totalShares = amount;
            return (amount, FixedPointMath.ONE_18);
        } else {
            uint256 newShares = totalShares.mulDivDown(amount, assets);
            totalShares += newShares;
            return (newShares, amount.divDown(newShares));
        }
    }

    ///@notice Withdraws shares from the yield source and sends the resulting tokens to the destination
    ///@param shares The shares to withdraw from the yield source
    /// @param asUnderlying If true the yield source will transfer underlying tokens
    ///                     if false it will transfer the yielding asset directly
    ///@param destination The address which is where to send the resulting tokens
    ///@return amountWithdrawn the amount of 'token' produced by this withdraw
    ///@return sharePrice The share price on withdraw.
    function _withdraw(
        uint256 shares,
        address destination,
        bool asUnderlying
    ) internal override returns (uint256 amountWithdrawn, uint256 sharePrice) {
        // The withdrawer receives a proportional amount of the assets held by
        // the contract to the amount of shares that they are redeeming. Small
        // numerical errors can result in the shares value being slightly larger
        // than the total shares, so we clamp the shares to the total shares to
        // avoid reverts.
        shares = shares > totalShares ? totalShares : shares;
        uint256 assets = aToken.balanceOf(address(this));
        uint256 withdrawValue = assets != 0
            ? assets.mulDivDown(shares, totalShares)
            : 0;

        // Remove the shares from the total share supply
        totalShares -= shares;

        // If the user wants underlying we withdraw for them otherwise send the base
        if (asUnderlying) {
            // Now we call aave to fulfill this withdraw for the user
            pool.withdraw(address(baseToken), withdrawValue, destination);
        } else {
            // Otherwise we simply transfer to them
            aToken.transfer(destination, withdrawValue);
        }

        // Return the amount and implied share price
        sharePrice = withdrawValue != 0 ? shares.divDown(withdrawValue) : 0;
        return (withdrawValue, sharePrice);
    }

    ///@notice Loads the share price from the yield source.
    ///@return sharePrice The current share price.
    function _pricePerShare()
        internal
        view
        override
        returns (uint256 sharePrice)
    {
        uint256 assets = aToken.balanceOf(address(this));
        sharePrice = totalShares != 0 ? assets.divDown(totalShares) : 0;
        return sharePrice;
    }
}
