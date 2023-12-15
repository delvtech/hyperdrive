// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "../interfaces/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../libraries/HyperdriveMath.sol";
import { LPMath } from "../libraries/LPMath.sol";
import { SafeCast } from "../libraries/SafeCast.sol";
import { HyperdriveStorage } from "./HyperdriveStorage.sol";

/// @author DELV
/// @title HyperdriveBase
/// @notice The Hyperdrive base contract that provides a set of helper methods
///         and defines the functions that must be overridden by implementations.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveBase is HyperdriveStorage {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    event Initialize(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 sharePrice,
        uint256 apr
    );

    event AddLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 sharePrice,
        uint256 lpSharePrice
    );

    event RemoveLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 sharePrice,
        uint256 withdrawalShareAmount,
        uint256 lpSharePrice
    );

    event RedeemWithdrawalShares(
        address indexed provider,
        uint256 withdrawalShareAmount,
        uint256 baseAmount,
        uint256 sharePrice
    );

    event OpenLong(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 sharePrice,
        uint256 bondAmount
    );

    event OpenShort(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 sharePrice,
        uint256 bondAmount
    );

    event CloseLong(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 sharePrice,
        uint256 bondAmount
    );

    event CloseShort(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 sharePrice,
        uint256 bondAmount
    );

    event CreateCheckpoint(
        uint256 indexed checkpointTime,
        uint256 sharePrice,
        uint256 maturedShorts,
        uint256 maturedLongs,
        uint256 lpSharePrice
    );

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    event ApprovalForAll(
        address indexed account,
        address indexed operator,
        bool approved
    );

    /// Yield Source ///

    /// @dev A YieldSource dependent check that prevents ether from being
    ///         transferred to Hyperdrive instances that don't accept ether.
    function _checkMessageValue() internal view virtual;

    /// @dev Transfers base from the user and commits it to the yield source.
    /// @param _amount The amount of base to deposit.
    /// @param _options The options that configure how the withdrawal is
    ///        settled. In particular, the currency used in the deposit is
    ///        specified here. Aside from those options, yield sources can
    ///        choose to implement additional options.
    /// @return sharesMinted The shares created by this deposit.
    /// @return sharePrice The share price.
    function _deposit(
        uint256 _amount,
        IHyperdrive.Options calldata _options
    ) internal virtual returns (uint256 sharesMinted, uint256 sharePrice);

    /// @dev Withdraws shares from the yield source and sends the base
    ///         released to the destination.
    /// @param _shares The shares to withdraw from the yield source.
    /// @param _options The options that configure how the withdrawal is
    ///        settled. In particular, the destination and currency used in the
    ///        withdrawal are specified here. Aside from those options, yield
    ///        sources can choose to implement additional options.
    /// @return amountWithdrawn The amount of base released by the withdrawal.
    function _withdraw(
        uint256 _shares,
        IHyperdrive.Options calldata _options
    ) internal virtual returns (uint256 amountWithdrawn);

    /// @dev Loads the share price from the yield source.
    /// @return sharePrice The current share price.
    function _pricePerShare()
        internal
        view
        virtual
        returns (uint256 sharePrice);

    /// Pause ///

    /// @dev Blocks a function execution if the contract is paused.
    modifier isNotPaused() {
        if (_marketState.isPaused) revert IHyperdrive.Paused();
        _;
    }

    /// Checkpoint ///

    /// @dev Creates a new checkpoint if necessary.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @param _sharePrice The current share price.
    /// @return openSharePrice The open share price of the latest checkpoint.
    function _applyCheckpoint(
        uint256 _checkpointTime,
        uint256 _sharePrice
    ) internal virtual returns (uint256 openSharePrice);

    /// Helpers ///

    /// @dev Calculates the normalized time remaining of a position.
    /// @param _maturityTime The maturity time of the position.
    /// @return timeRemaining The normalized time remaining (in [0, 1]).
    function _calculateTimeRemaining(
        uint256 _maturityTime
    ) internal view returns (uint256 timeRemaining) {
        uint256 latestCheckpoint = _latestCheckpoint();
        timeRemaining = _maturityTime > latestCheckpoint
            ? _maturityTime - latestCheckpoint
            : 0;
        timeRemaining = (timeRemaining).divDown(_positionDuration);
    }

    /// @dev Calculates the normalized time remaining of a position when the
    ///      maturity time is scaled up 18 decimals.
    /// @param _maturityTime The maturity time of the position.
    function _calculateTimeRemainingScaled(
        uint256 _maturityTime
    ) internal view returns (uint256 timeRemaining) {
        uint256 latestCheckpoint = _latestCheckpoint() * ONE;
        timeRemaining = _maturityTime > latestCheckpoint
            ? _maturityTime - latestCheckpoint
            : 0;
        timeRemaining = (timeRemaining).divDown(_positionDuration * ONE);
    }

    /// @dev Gets the most recent checkpoint time.
    /// @return latestCheckpoint The latest checkpoint.
    function _latestCheckpoint()
        internal
        view
        returns (uint256 latestCheckpoint)
    {
        latestCheckpoint =
            block.timestamp -
            (block.timestamp % _checkpointDuration);
    }

    /// @dev Gets the effective share reserves.
    /// @return The effective share reserves. This is the share reserves used
    ///         by the YieldSpace pricing model.
    function _effectiveShareReserves() internal view returns (uint256) {
        return
            HyperdriveMath.calculateEffectiveShareReserves(
                _marketState.shareReserves,
                _marketState.shareAdjustment
            );
    }

    /// @dev Gets the amount of non-netted longs with a given maturity.
    /// @param _maturityTime The maturity time of the longs.
    /// @return The amount of non-netted longs. This is a signed value that
    ///         can be negative. This is convenient for updating the long
    ///         exposure when closing positions.
    function _nonNettedLongs(
        uint256 _maturityTime
    ) internal view returns (int256) {
        // The amount of non-netted longs is the difference between the amount
        // of longs and the amount of shorts with a given maturity time. If the
        // difference is negative, the amount of non-netted longs is zero.
        return
            int256(
                _totalSupply[
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Long,
                        _maturityTime
                    )
                ]
            ) -
            int256(
                _totalSupply[
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Short,
                        _maturityTime
                    )
                ]
            );
    }

    /// @dev Gets the distribute excess idle parameters from the current state.
    /// @param _sharePrice The current share price.
    /// @return params The distribute excess idle parameters.
    function _getDistributeExcessIdleParams(
        uint256 _idle,
        uint256 _withdrawalSharesTotalSupply,
        uint256 _sharePrice
    ) internal view returns (LPMath.DistributeExcessIdleParams memory params) {
        LPMath.PresentValueParams
            memory presentValueParams = _getPresentValueParams(_sharePrice);
        uint256 startingPresentValue = LPMath.calculatePresentValue(
            presentValueParams
        );
        int256 netCurveTrade = int256(
            presentValueParams.longsOutstanding.mulDown(
                presentValueParams.longAverageTimeRemaining
            )
        ) -
            int256(
                presentValueParams.shortsOutstanding.mulDown(
                    presentValueParams.shortAverageTimeRemaining
                )
            );
        params = LPMath.DistributeExcessIdleParams({
            presentValueParams: presentValueParams,
            startingPresentValue: startingPresentValue,
            activeLpTotalSupply: _totalSupply[AssetId._LP_ASSET_ID],
            withdrawalSharesTotalSupply: _withdrawalSharesTotalSupply,
            idle: _idle,
            netCurveTrade: netCurveTrade,
            originalShareReserves: presentValueParams.shareReserves,
            originalShareAdjustment: presentValueParams.shareAdjustment,
            originalBondReserves: presentValueParams.bondReserves
        });
    }

    /// @dev Gets the present value parameters from the current state.
    /// @param _sharePrice The current share price.
    /// @return params The present value parameters.
    function _getPresentValueParams(
        uint256 _sharePrice
    ) internal view returns (LPMath.PresentValueParams memory params) {
        params = LPMath.PresentValueParams({
            shareReserves: _marketState.shareReserves,
            shareAdjustment: _marketState.shareAdjustment,
            bondReserves: _marketState.bondReserves,
            sharePrice: _sharePrice,
            initialSharePrice: _initialSharePrice,
            minimumShareReserves: _minimumShareReserves,
            timeStretch: _timeStretch,
            longsOutstanding: _marketState.longsOutstanding,
            longAverageTimeRemaining: _calculateTimeRemainingScaled(
                _marketState.longAverageMaturityTime
            ),
            shortsOutstanding: _marketState.shortsOutstanding,
            shortAverageTimeRemaining: _calculateTimeRemainingScaled(
                _marketState.shortAverageMaturityTime
            )
        });
    }

    /// @dev Checks if any of the bonds the trader purchased on the curve
    ///      were purchased above price of 1 base per bonds.
    /// @param _shareCurveDelta The amount of shares the trader pays the curve.
    /// @param _bondCurveDelta The amount of bonds the trader receives from the
    ///        curve.
    /// @param _maxSpotPrice The maximum allowable spot price for the trade.
    /// @return A flag indicating whether the trade was negative interest.
    function _isNegativeInterest(
        uint256 _shareCurveDelta,
        uint256 _bondCurveDelta,
        uint256 _maxSpotPrice
    ) internal view returns (bool) {
        // Calculate the spot price after making the trade on the curve but
        // before accounting for fees. Compare this to the max spot price to
        // determine if the trade is negative interest.
        uint256 endingSpotPrice = HyperdriveMath.calculateSpotPrice(
            _effectiveShareReserves() + _shareCurveDelta,
            _marketState.bondReserves - _bondCurveDelta,
            _initialSharePrice,
            _timeStretch
        );
        return endingSpotPrice > _maxSpotPrice;
    }

    /// @dev Check solvency by verifying that the share reserves are greater
    ///      than the exposure plus the minimum share reserves.
    /// @param _sharePrice The current share price.
    /// @return True if the share reserves are greater than the exposure plus
    ///         the minimum share reserves.
    function _isSolvent(uint256 _sharePrice) internal view returns (bool) {
        return
            int256((uint256(_marketState.shareReserves).mulDown(_sharePrice))) -
                int128(_marketState.longExposure) >=
            int256(_minimumShareReserves.mulDown(_sharePrice));
    }

    /// @dev Updates the global long exposure.
    /// @param _before The long exposure before the update.
    /// @param _after The long exposure after the update.
    function _updateLongExposure(int256 _before, int256 _after) internal {
        // The global long exposure is the sum of the non-netted longs in each
        // checkpoint. To update this value, we subtract the current value
        // (`_before.max(0)`) and add the new value (`_after.max(0)`).
        int128 delta = (int256(_after.max(0)) - int256(_before.max(0)))
            .toInt128();
        if (delta > 0) {
            _marketState.longExposure += uint128(delta);
        } else if (delta < 0) {
            _marketState.longExposure -= uint128(-delta);
        }
    }

    /// @dev Collect the interest earned by closed positions
    ///      that haven't been redeemed.
    /// @param _amount The amount in shares that earned the zombie interest.
    /// @param _oldSharePrice The share price at the time of the last checkpoint.
    /// @param _newSharePrice The current share price.
    function _collectZombieInterest(
        uint256 _amount,
        uint256 _oldSharePrice,
        uint256 _newSharePrice
    ) internal {
        if (_newSharePrice > _oldSharePrice && _oldSharePrice > 0) {
            // dz * (c1 - c0)/c1
            uint256 zombieInterest = _amount.mulDivDown(
                _newSharePrice - _oldSharePrice,
                _newSharePrice
            );
            _marketState.zombieShareReserves -= zombieInterest.toUint128();
            _marketState.shareReserves += zombieInterest.toUint128();
            _marketState.shareAdjustment += int128(zombieInterest.toUint128());
        }
    }

    /// @dev Calculates the number of share reserves that are not reserved by
    ///      open positions.
    /// @param _sharePrice The current share price.
    /// @return idleShares The amount of shares that are available for LPs to
    ///         withdraw.
    function _calculateIdleShareReserves(
        uint256 _sharePrice
    ) internal view returns (uint256 idleShares) {
        uint256 longExposure = uint256(_marketState.longExposure).divDown(
            _sharePrice
        );
        if (_marketState.shareReserves > longExposure + _minimumShareReserves) {
            idleShares =
                _marketState.shareReserves -
                longExposure -
                _minimumShareReserves;
        }
        return idleShares;
    }

    /// @dev Calculates the LP share price.
    /// @param _sharePrice The current share price.
    /// @return lpSharePrice The LP share price.
    function _calculateLPSharePrice(
        uint256 _sharePrice
    ) internal view returns (uint256 lpSharePrice) {
        uint256 presentValue = _sharePrice > 0
            ? LPMath
                .calculatePresentValue(_getPresentValueParams(_sharePrice))
                .mulDown(_sharePrice)
            : 0;
        uint256 lpTotalSupply = _totalSupply[AssetId._LP_ASSET_ID] +
            _totalSupply[AssetId._WITHDRAWAL_SHARE_ASSET_ID] -
            _withdrawPool.readyToWithdraw;
        lpSharePrice = lpTotalSupply == 0
            ? 0
            : presentValue.divDown(lpTotalSupply);
        return lpSharePrice;
    }

    /// @dev Calculates the fees that go to the LPs and governance.
    /// @param _shareAmount The amount of shares exchanged for bonds.
    /// @param _spotPrice The price without slippage of bonds in terms of base
    ///         (base/bonds).
    /// @param _sharePrice The current price of shares in terms of base
    ///        (base/shares).
    /// @return curveFee The curve fee. The fee is in terms of bonds.
    /// @return governanceCurveFee The curve fee that goes to governance. The
    ///         fee is in terms of bonds.
    function _calculateFeesGivenShares(
        uint256 _shareAmount,
        uint256 _spotPrice,
        uint256 _sharePrice
    ) internal view returns (uint256 curveFee, uint256 governanceCurveFee) {
        // Fixed Rate (r) = (value at maturity - purchase price)/(purchase price)
        //                = (1-p)/p
        //                = ((1 / p) - 1)
        //                = the ROI at maturity of a bond purchased at price p
        //
        // Another way to think about it:
        //
        // p (spot price) tells us how many base a bond is worth -> p = base/bonds
        // 1/p tells us how many bonds a base is worth -> 1/p = bonds/base
        // 1/p - 1 tells us how many additional bonds we get for each
        // base -> (1/p - 1) = additional bonds/base
        //
        // The curve fee is taken from the additional bonds the user gets for
        // each base:
        //
        // curve fee = ((1 / p) - 1) * phi_curve * c * dz
        //           = r * phi_curve * base/shares * shares
        //           = bonds/base * phi_curve * base
        //           = bonds * phi_curve
        curveFee = (ONE.divDown(_spotPrice) - ONE)
            .mulDown(_curveFee)
            .mulDown(_sharePrice)
            .mulDown(_shareAmount);

        // We leave the governance fee in terms of bonds:
        // governanceCurveFee = curve_fee * p * phi_gov
        //                    = bonds * phi_gov
        governanceCurveFee = curveFee.mulDown(_governanceFee);
    }

    /// @dev Calculates the fees that go to the LPs and governance.
    /// @param _bondAmount The amount of bonds being exchanged for shares.
    /// @param _normalizedTimeRemaining The normalized amount of time until maturity.
    /// @param _spotPrice The price without slippage of bonds in terms of base
    ///        (base/bonds).
    /// @param _sharePrice The current price of shares in terms of base (base/shares).
    /// @return curveFee The curve fee. The fee is in terms of shares.
    /// @return flatFee The flat fee. The fee is in terms of shares.
    /// @return governanceCurveFee The curve fee that goes to governance. The
    ///         fee is in terms of shares.
    function _calculateFeesGivenBonds(
        uint256 _bondAmount,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _sharePrice
    )
        internal
        view
        returns (
            uint256 curveFee,
            uint256 flatFee,
            uint256 governanceCurveFee,
            uint256 totalGovernanceFee
        )
    {
        // p (spot price) tells us how many base a bond is worth -> p = base/bonds
        // 1 - p tells us how many additional base a bond is worth at
        // maturity -> (1 - p) = additional base/bonds

        // The curve fee is taken from the additional base the user gets for
        // each bond at maturity:
        //
        // curve fee = ((1 - p) * phi_curve * d_y * t)/c
        //           = (base/bonds * phi_curve * bonds * t) / (base/shares)
        //           = (base/bonds * phi_curve * bonds * t) * (shares/base)
        //           = (base * phi_curve * t) * (shares/base)
        //           = phi_curve * t * shares
        curveFee = _curveFee
            .mulDown(ONE - _spotPrice)
            .mulDown(_bondAmount)
            .mulDivDown(_normalizedTimeRemaining, _sharePrice);

        // Calculate the curve portion of the governance fee:
        //
        // governanceCurveFee = curve_fee * phi_gov
        //                    = shares * phi_gov
        governanceCurveFee = curveFee.mulDown(_governanceFee);

        // The flat portion of the fee is taken from the matured bonds.
        // Since a matured bond is worth 1 base, it is appropriate to consider
        // d_y in units of base:
        //
        // flat fee = (d_y * (1 - t) * phi_flat) / c
        //          = (base * (1 - t) * phi_flat) / (base/shares)
        //          = (base * (1 - t) * phi_flat) * (shares/base)
        //          = shares * (1 - t) * phi_flat
        uint256 flat = _bondAmount.mulDivDown(
            ONE - _normalizedTimeRemaining,
            _sharePrice
        );
        flatFee = flat.mulDown(_flatFee);

        // We calculate the flat portion of the governance fee as:
        //
        // governance_flat_fee = flat_fee * phi_gov
        //                     = shares * phi_gov
        //
        // The totalGovernanceFee is the sum of the curve and flat governance fees.
        totalGovernanceFee =
            governanceCurveFee +
            flatFee.mulDown(_governanceFee);
    }

    /// @dev Converts input to base if necessary according to what is specified
    ///      in options.
    /// @param _amount The amount to convert.
    /// @param _sharePrice The current share price.
    /// @param _options The options that configure the conversion.
    /// @return The converted amount.
    function _convertToBaseFromOption(
        uint256 _amount,
        uint256 _sharePrice,
        IHyperdrive.Options calldata _options
    ) internal pure returns (uint256) {
        if (_options.asBase) {
            return _amount;
        } else {
            return _amount.mulDown(_sharePrice);
        }
    }

    /// @dev Converts input to what is specified in the options from base.
    /// @param _amount The amount to convert.
    /// @param _sharePrice The current share price.
    /// @param _options The options that configure the conversion.
    /// @return The converted amount.
    function _convertToOptionFromBase(
        uint256 _amount,
        uint256 _sharePrice,
        IHyperdrive.Options calldata _options
    ) internal pure returns (uint256) {
        if (_options.asBase) {
            return _amount;
        } else {
            return _amount.divDown(_sharePrice);
        }
    }
}
