// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";

library HyperdriveUtils {
    using HyperdriveUtils for *;
    using FixedPointMath for uint256;

    function latestCheckpoint(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        return
            block.timestamp -
            (block.timestamp % _hyperdrive.getPoolConfig().checkpointDuration);
    }

    function calculateTimeRemaining(
        IHyperdrive _hyperdrive,
        uint256 _maturityTime
    ) internal view returns (uint256 timeRemaining) {
        timeRemaining = _maturityTime > latestCheckpoint(_hyperdrive)
            ? _maturityTime - latestCheckpoint(_hyperdrive)
            : 0;
        timeRemaining = (timeRemaining).divDown(
            _hyperdrive.getPoolConfig().positionDuration
        );
        return timeRemaining;
    }

    function maturityTimeFromLatestCheckpoint(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        return
            latestCheckpoint(_hyperdrive) +
            _hyperdrive.getPoolConfig().positionDuration;
    }

    function calculateSpotPrice(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        return
            HyperdriveMath.calculateSpotPrice(
                HyperdriveMath.calculateEffectiveShareReserves(
                    poolInfo.shareReserves,
                    poolInfo.shareAdjustment
                ),
                poolInfo.bondReserves,
                poolConfig.initialSharePrice,
                poolConfig.timeStretch
            );
    }

    function calculateSpotRate(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        return
            HyperdriveMath.calculateSpotRate(
                HyperdriveMath.calculateEffectiveShareReserves(
                    poolInfo.shareReserves,
                    poolInfo.shareAdjustment
                ),
                poolInfo.bondReserves,
                poolConfig.initialSharePrice,
                poolConfig.positionDuration,
                poolConfig.timeStretch
            );
    }

    function calculateRateFromRealizedPrice(
        uint256 _baseAmount,
        uint256 _bondAmount,
        uint256 _timeRemaining
    ) internal pure returns (uint256) {
        // price = dx / dy
        //       =>
        // rate = (1 - p) / (p * t) = (1 - dx / dy) * (dx / dy * t)
        //       =>
        // rate = (dy - dx) / (dx * t)
        require(
            _timeRemaining <= 1e18 && _timeRemaining > 0,
            "Expecting NormalizedTimeRemaining"
        );
        return
            (_bondAmount - _baseAmount).divDown(
                _baseAmount.mulDown(_timeRemaining)
            );
    }

    /// @dev Calculates the maximum amount of longs that can be opened.
    /// @param _hyperdrive A Hyperdrive instance.
    /// @param _maxIterations The maximum number of iterations to use.
    /// @return baseAmount The cost of buying the maximum amount of longs.
    function calculateMaxLong(
        IHyperdrive _hyperdrive,
        uint256 _maxIterations
    ) internal view returns (uint256 baseAmount) {
        IHyperdrive.Checkpoint memory checkpoint = _hyperdrive.getCheckpoint(
            _hyperdrive.latestCheckpoint()
        );
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        (baseAmount, ) = HyperdriveMath.calculateMaxLong(
            HyperdriveMath.MaxTradeParams({
                shareReserves: poolInfo.shareReserves,
                shareAdjustment: poolInfo.shareAdjustment,
                bondReserves: poolInfo.bondReserves,
                longsOutstanding: poolInfo.longsOutstanding,
                longExposure: poolInfo.longExposure,
                timeStretch: poolConfig.timeStretch,
                sharePrice: poolInfo.sharePrice,
                initialSharePrice: poolConfig.initialSharePrice,
                minimumShareReserves: poolConfig.minimumShareReserves,
                curveFee: poolConfig.fees.curve,
                governanceFee: poolConfig.fees.governance
            }),
            checkpoint.longExposure,
            _maxIterations
        );
        return baseAmount;
    }

    /// @dev Calculates the maximum amount of longs that can be opened.
    /// @param _hyperdrive A Hyperdrive instance.
    /// @return baseAmount The cost of buying the maximum amount of longs.
    function calculateMaxLong(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256 baseAmount) {
        return calculateMaxLong(_hyperdrive, 7);
    }

    /// @dev Calculates the maximum amount of shorts that can be opened.
    /// @param _hyperdrive A Hyperdrive instance.
    /// @param _maxIterations The maximum number of iterations to use.
    /// @return The maximum amount of bonds that can be shorted.
    function calculateMaxShort(
        IHyperdrive _hyperdrive,
        uint256 _maxIterations
    ) internal view returns (uint256) {
        IHyperdrive.Checkpoint memory checkpoint = _hyperdrive.getCheckpoint(
            _hyperdrive.latestCheckpoint()
        );
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        return
            HyperdriveMath.calculateMaxShort(
                HyperdriveMath.MaxTradeParams({
                    shareReserves: poolInfo.shareReserves,
                    shareAdjustment: poolInfo.shareAdjustment,
                    bondReserves: poolInfo.bondReserves,
                    longsOutstanding: poolInfo.longsOutstanding,
                    longExposure: poolInfo.longExposure,
                    timeStretch: poolConfig.timeStretch,
                    sharePrice: poolInfo.sharePrice,
                    initialSharePrice: poolConfig.initialSharePrice,
                    minimumShareReserves: poolConfig.minimumShareReserves,
                    curveFee: poolConfig.fees.curve,
                    governanceFee: poolConfig.fees.governance
                }),
                checkpoint.longExposure,
                _maxIterations
            );
    }

    /// @dev Calculates the maximum amount of shorts that can be opened.
    /// @param _hyperdrive A Hyperdrive instance.
    /// @return The maximum amount of bonds that can be shorted.
    function calculateMaxShort(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        return calculateMaxShort(_hyperdrive, 7);
    }

    /// @dev Calculates the non-compounded interest over a period.
    /// @param _principal The principal amount that will accrue interest.
    /// @param _rate The interest rate.
    /// @param _time Amount of time in seconds over which interest accrues.
    /// @return totalAmount The total amount of capital after interest accrues.
    /// @return interest The interest that accrued.
    function calculateInterest(
        uint256 _principal,
        int256 _rate,
        uint256 _time
    ) internal pure returns (uint256 totalAmount, int256 interest) {
        // Adjust time to a fraction of a year
        uint256 normalizedTime = _time.divDown(365 days);
        interest = _rate >= 0
            ? int256(_principal.mulDown(uint256(_rate).mulDown(normalizedTime)))
            : -int256(
                _principal.mulDown(uint256(-_rate).mulDown(normalizedTime))
            );
        totalAmount = uint256(int256(_principal) + interest);
        return (totalAmount, interest);
    }

    /// @dev Calculates principal + compounded rate of interest over a period
    ///      principal * e ^ (rate * time)
    /// @param _principal The principal amount.
    /// @param _rate The interest rate.
    /// @param _time Number of seconds compounding will occur for
    /// @return totalAmount The total amount of capital after interest accrues.
    /// @return interest The interest that accrued.
    function calculateCompoundInterest(
        uint256 _principal,
        int256 _rate,
        uint256 _time
    ) internal pure returns (uint256 totalAmount, int256 interest) {
        // Adjust time to a fraction of a year
        uint256 normalizedTime = _time.divDown(365 days);
        uint256 rt = uint256(_rate < 0 ? -_rate : _rate).mulDown(
            normalizedTime
        );

        if (_rate > 0) {
            totalAmount = _principal.mulDown(
                uint256(FixedPointMath.exp(int256(rt)))
            );
            interest = int256(totalAmount - _principal);
            return (totalAmount, interest);
        } else if (_rate < 0) {
            // NOTE: Might not be the correct calculation for negatively
            // continuously compounded interest
            totalAmount = _principal.divDown(
                uint256(FixedPointMath.exp(int256(rt)))
            );
            interest = int256(totalAmount) - int256(_principal);
            return (totalAmount, interest);
        }
        return (_principal, 0);
    }

    function calculateTimeStretch(
        uint256 _rate
    ) internal pure returns (uint256) {
        uint256 timeStretch = uint256(5.24592e18).divDown(
            uint256(0.04665e18).mulDown(_rate * 100)
        );
        return FixedPointMath.ONE_18.divDown(timeStretch);
    }

    function presentValue(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        return
            HyperdriveMath
                .calculatePresentValue(
                    HyperdriveMath.PresentValueParams({
                        shareReserves: poolInfo.shareReserves,
                        shareAdjustment: poolInfo.shareAdjustment,
                        bondReserves: poolInfo.bondReserves,
                        sharePrice: poolInfo.sharePrice,
                        initialSharePrice: poolConfig.initialSharePrice,
                        minimumShareReserves: poolConfig.minimumShareReserves,
                        timeStretch: poolConfig.timeStretch,
                        longsOutstanding: poolInfo.longsOutstanding,
                        longAverageTimeRemaining: calculateTimeRemaining(
                            _hyperdrive,
                            uint256(poolInfo.longAverageMaturityTime).divUp(
                                1e36
                            )
                        ),
                        shortsOutstanding: poolInfo.shortsOutstanding,
                        shortAverageTimeRemaining: calculateTimeRemaining(
                            _hyperdrive,
                            uint256(poolInfo.shortAverageMaturityTime).divUp(
                                1e36
                            )
                        )
                    })
                )
                .mulDown(poolInfo.sharePrice);
    }

    function lpSharePrice(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        return _hyperdrive.presentValue().divDown(_hyperdrive.lpTotalSupply());
    }

    function lpTotalSupply(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        return
            _hyperdrive.totalSupply(AssetId._LP_ASSET_ID) +
            _hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID) -
            _hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw;
    }

    function solvency(IHyperdrive _hyperdrive) internal view returns (int256) {
        IHyperdrive.PoolConfig memory config = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory info = _hyperdrive.getPoolInfo();
        return
            int256(info.shareReserves) -
            int256(info.longExposure.divDown(info.sharePrice)) -
            int256(config.minimumShareReserves);
    }

    function decodeError(
        bytes memory _error
    ) internal pure returns (string memory) {
        // All of the Hyperdrive errors have a selector.
        if (_error.length < 4) {
            revert("Invalid error");
        }

        // Convert the selector to the correct error message.
        bytes4 selector;
        assembly {
            selector := mload(add(_error, 0x20))
        }
        return selector.decodeError();
    }

    function decodeError(
        bytes4 _selector
    ) internal pure returns (string memory) {
        // Convert the selector to the correct error message.
        if (_selector == IHyperdrive.BaseBufferExceedsShareReserves.selector) {
            return "BaseBufferExceedsShareReserves";
        }
        if (_selector == IHyperdrive.BelowMinimumContribution.selector) {
            return "BelowMinimumContribution";
        }
        if (_selector == IHyperdrive.BelowMinimumShareReserves.selector) {
            return "BelowMinimumShareReserves";
        }
        if (_selector == IHyperdrive.InvalidBaseToken.selector) {
            return "InvalidBaseToken";
        }
        if (_selector == IHyperdrive.InvalidCheckpointTime.selector) {
            return "InvalidCheckpointTime";
        }
        if (_selector == IHyperdrive.InvalidCheckpointDuration.selector) {
            return "InvalidCheckpointDuration";
        }
        if (_selector == IHyperdrive.InvalidFeeAmounts.selector) {
            return "InvalidFeeAmounts";
        }
        if (_selector == IHyperdrive.InvalidInitialSharePrice.selector) {
            return "InvalidInitialSharePrice";
        }
        if (_selector == IHyperdrive.InvalidMaturityTime.selector) {
            return "InvalidMaturityTime";
        }
        if (_selector == IHyperdrive.InvalidMinimumShareReserves.selector) {
            return "InvalidMinimumShareReserves";
        }
        if (_selector == IHyperdrive.InvalidPositionDuration.selector) {
            return "InvalidPositionDuration";
        }
        if (_selector == IHyperdrive.InvalidShareReserves.selector) {
            return "InvalidShareReserves";
        }
        if (_selector == IHyperdrive.InvalidSpotRate.selector) {
            return "InvalidSpotRate";
        }
        if (_selector == IHyperdrive.NegativeInterest.selector) {
            return "NegativeInterest";
        }
        if (_selector == IHyperdrive.OutputLimit.selector) {
            return "OutputLimit";
        }
        if (_selector == IHyperdrive.Paused.selector) {
            return "Paused";
        }
        if (_selector == IHyperdrive.PoolAlreadyInitialized.selector) {
            return "PoolAlreadyInitialized";
        }
        if (_selector == IHyperdrive.TransferFailed.selector) {
            return "TransferFailed";
        }
        if (_selector == IHyperdrive.UnexpectedAssetId.selector) {
            return "UnexpectedAssetId";
        }
        if (_selector == IHyperdrive.UnexpectedSender.selector) {
            return "UnexpectedSender";
        }
        if (_selector == IHyperdrive.UnsupportedToken.selector) {
            return "UnsupportedToken";
        }
        if (_selector == IHyperdrive.ApprovalFailed.selector) {
            return "ApprovalFailed";
        }
        if (_selector == IHyperdrive.MinimumTransactionAmount.selector) {
            return "MinimumTransactionAmount";
        }
        if (_selector == IHyperdrive.ZeroLpTotalSupply.selector) {
            return "ZeroLpTotalSupply";
        }
        if (_selector == IHyperdrive.NoAssetsToWithdraw.selector) {
            return "NoAssetsToWithdraw";
        }
        if (_selector == IHyperdrive.NotPayable.selector) {
            return "NotPayable";
        }
        if (_selector == IHyperdrive.QueryOutOfRange.selector) {
            return "QueryOutOfRange";
        }
        if (_selector == IHyperdrive.ReturnData.selector) {
            return "ReturnData";
        }
        if (_selector == IHyperdrive.CallFailed.selector) {
            return "CallFailed";
        }
        if (_selector == IHyperdrive.UnexpectedSuccess.selector) {
            return "UnexpectedSuccess";
        }
        if (_selector == IHyperdrive.Unauthorized.selector) {
            return "Unauthorized";
        }
        if (_selector == IHyperdrive.InvalidContribution.selector) {
            return "InvalidContribution";
        }
        if (_selector == IHyperdrive.InvalidToken.selector) {
            return "InvalidToken";
        }
        if (_selector == IHyperdrive.MaxFeeTooHigh.selector) {
            return "MaxFeeTooHigh";
        }
        if (_selector == IHyperdrive.FeeTooHigh.selector) {
            return "FeeTooHigh";
        }
        if (_selector == IHyperdrive.NonPayableInitialization.selector) {
            return "NonPayableInitialization";
        }
        if (_selector == IHyperdrive.BatchInputLengthMismatch.selector) {
            return "BatchInputLengthMismatch";
        }
        if (_selector == IHyperdrive.ExpiredDeadline.selector) {
            return "ExpiredDeadline";
        }
        if (_selector == IHyperdrive.ExpiredDeadline.selector) {
            return "InvalidSignature";
        }
        if (_selector == IHyperdrive.InvalidERC20Bridge.selector) {
            return "InvalidERC20Bridge";
        }
        if (_selector == IHyperdrive.RestrictedZeroAddress.selector) {
            return "RestrictedZeroAddress";
        }
        if (_selector == IHyperdrive.AlreadyClosed.selector) {
            return "AlreadyClosed";
        }
        if (_selector == IHyperdrive.BondMatured.selector) {
            return "BondMatured";
        }
        if (_selector == IHyperdrive.BondNotMatured.selector) {
            return "BondNotMatured";
        }
        if (_selector == IHyperdrive.InsufficientPrice.selector) {
            return "InsufficientPrice";
        }
        if (_selector == IHyperdrive.MintPercentTooHigh.selector) {
            return "MintPercentTooHigh";
        }
        if (_selector == IHyperdrive.InvalidTimestamp.selector) {
            return "InvalidTimestamp";
        }
        if (_selector == IHyperdrive.FixedPointMath_InvalidExponent.selector) {
            return "FixedPointMath_InvalidExponent";
        }
        if (
            _selector == IHyperdrive.FixedPointMath_NegativeOrZeroInput.selector
        ) {
            return "FixedPointMath_NegativeOrZeroInput";
        }
        if (_selector == IHyperdrive.FixedPointMath_NegativeInput.selector) {
            return "FixedPointMath_NegativeInput";
        }
        revert("Unknown selector");
    }
}
