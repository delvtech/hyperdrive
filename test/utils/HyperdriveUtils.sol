// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";

library HyperdriveUtils {
    using HyperdriveUtils for *;
    using FixedPointMath for uint256;

    function latestCheckpoint(
        IHyperdrive hyperdrive
    ) internal view returns (uint256) {
        return
            block.timestamp -
            (block.timestamp % hyperdrive.getPoolConfig().checkpointDuration);
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
                poolInfo.shareReserves,
                poolInfo.bondReserves,
                poolConfig.initialSharePrice,
                poolConfig.timeStretch
            );
    }

    function calculateAPRFromReserves(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        return
            HyperdriveMath.calculateAPRFromReserves(
                poolInfo.shareReserves,
                poolInfo.bondReserves,
                poolConfig.initialSharePrice,
                poolConfig.positionDuration,
                poolConfig.timeStretch
            );
    }

    function calculateAPRFromRealizedPrice(
        uint256 baseAmount,
        uint256 bondAmount,
        uint256 timeRemaining
    ) internal pure returns (uint256) {
        // price = dx / dy
        //       =>
        // rate = (1 - p) / (p * t) = (1 - dx / dy) * (dx / dy * t)
        //       =>
        // apr = (dy - dx) / (dx * t)
        require(
            timeRemaining <= 1e18 && timeRemaining > 0,
            "Expecting NormalizedTimeRemaining"
        );
        return
            (bondAmount.sub(baseAmount)).divDown(
                baseAmount.mulDown(timeRemaining)
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
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.Checkpoint memory checkpoint = _hyperdrive.getCheckpoint(_hyperdrive.latestCheckpoint());
        (baseAmount, ) = HyperdriveMath.calculateMaxLong(
            HyperdriveMath.MaxTradeParams({
                shareReserves: poolInfo.shareReserves,
                bondReserves: poolInfo.bondReserves,
                longsOutstanding: poolInfo.longsOutstanding,
                timeStretch: poolConfig.timeStretch,
                sharePrice: poolInfo.sharePrice,
                initialSharePrice: poolConfig.initialSharePrice,
                minimumShareReserves: poolConfig.minimumShareReserves
            }),
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
    /// @return The maximum amount of bonds that can be shorted.
    function calculateMaxShort(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        return
            HyperdriveMath.calculateMaxShort(
                HyperdriveMath.MaxTradeParams({
                    shareReserves: poolInfo.shareReserves,
                    bondReserves: poolInfo.bondReserves,
                    longsOutstanding: poolInfo.longsOutstanding,
                    timeStretch: poolConfig.timeStretch,
                    sharePrice: poolInfo.sharePrice,
                    initialSharePrice: poolConfig.initialSharePrice,
                    minimumShareReserves: poolConfig.minimumShareReserves
                })
            );
    }

    /// @dev Calculates the non-compounded interest over a period.
    /// @param _principal The principal amount that will accrue interest.
    /// @param _apr Annual percentage rate
    /// @param _time Amount of time in seconds over which interest accrues.
    /// @return totalAmount The total amount of capital after interest accrues.
    /// @return interest The interest that accrued.
    function calculateInterest(
        uint256 _principal,
        int256 _apr,
        uint256 _time
    ) internal pure returns (uint256 totalAmount, int256 interest) {
        // Adjust time to a fraction of a year
        uint256 normalizedTime = _time.divDown(365 days);
        interest = _apr >= 0
            ? int256(_principal.mulDown(uint256(_apr).mulDown(normalizedTime)))
            : -int256(
                _principal.mulDown(uint256(-_apr).mulDown(normalizedTime))
            );
        totalAmount = uint256(int256(_principal) + interest);
        return (totalAmount, interest);
    }

    /// @dev Calculates principal + compounded rate of interest over a period
    ///      principal * e ^ (rate * time)
    /// @param _principal The initial amount interest will be accrued on
    /// @param _apr Annual percentage rate
    /// @param _time Number of seconds compounding will occur for
    /// @return totalAmount The total amount of capital after interest accrues.
    /// @return interest The interest that accrued.
    function calculateCompoundInterest(
        uint256 _principal,
        int256 _apr,
        uint256 _time
    ) internal pure returns (uint256 totalAmount, int256 interest) {
        // Adjust time to a fraction of a year
        uint256 normalizedTime = _time.divDown(365 days);
        uint256 rt = uint256(_apr < 0 ? -_apr : _apr).mulDown(normalizedTime);

        if (_apr > 0) {
            totalAmount = _principal.mulDown(
                uint256(FixedPointMath.exp(int256(rt)))
            );
            interest = int256(totalAmount - _principal);
            return (totalAmount, interest);
        } else if (_apr < 0) {
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

    function calculateTimeStretch(uint256 apr) internal pure returns (uint256) {
        uint256 timeStretch = uint256(5.24592e18).divDown(
            uint256(0.04665e18).mulDown(apr * 100)
        );
        return FixedPointMath.ONE_18.divDown(timeStretch);
    }

    // FIXME: This should be removed.
    function calculateOpenShortDeposit(
        IHyperdrive _hyperdrive,
        uint256 _bondAmount
    ) internal view returns (uint256) {
        // Retrieve hyperdrive pool state
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        uint256 openSharePrice;
        uint256 timeRemaining;
        {
            uint256 checkpoint = latestCheckpoint(_hyperdrive);
            uint256 maturityTime = checkpoint + poolConfig.positionDuration;
            timeRemaining = calculateTimeRemaining(_hyperdrive, maturityTime);
            openSharePrice = _hyperdrive.getCheckpoint(checkpoint).sharePrice;
        }

        // Calculate the openShort trade
        uint256 shareProceeds = HyperdriveMath.calculateOpenShort(
            poolInfo.shareReserves,
            poolInfo.bondReserves,
            _bondAmount,
            poolConfig.timeStretch,
            poolInfo.sharePrice,
            poolConfig.initialSharePrice
        );

        // Price without slippage of bonds in terms of shares
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            poolInfo.shareReserves,
            poolInfo.bondReserves,
            poolConfig.initialSharePrice,
            poolConfig.timeStretch
        );

        // Calculate and attribute fees
        uint256 curveFee = FixedPointMath
            .ONE_18
            .sub(spotPrice)
            .mulDown(poolConfig.fees.curve)
            .mulDown(_bondAmount)
            .mulDivDown(timeRemaining, poolInfo.sharePrice);
        uint256 flatFee = (
            _bondAmount.mulDivDown(
                FixedPointMath.ONE_18.sub(timeRemaining),
                poolInfo.sharePrice
            )
        ).mulDown(poolConfig.fees.flat);
        shareProceeds -= curveFee + flatFee;

        // Return the proceeds of the short
        return
            HyperdriveMath
                .calculateShortProceeds(
                    _bondAmount,
                    shareProceeds,
                    openSharePrice,
                    poolInfo.sharePrice,
                    poolInfo.sharePrice
                )
                .mulDown(poolInfo.sharePrice);
    }

    function presentValue(
        IHyperdrive hyperdrive
    ) internal view returns (uint256) {
        IHyperdrive.PoolConfig memory poolConfig = hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        return
            HyperdriveMath
                .calculatePresentValue(
                    HyperdriveMath.PresentValueParams({
                        shareReserves: poolInfo.shareReserves,
                        bondReserves: poolInfo.bondReserves,
                        sharePrice: poolInfo.sharePrice,
                        initialSharePrice: poolConfig.initialSharePrice,
                        minimumShareReserves: poolConfig.minimumShareReserves,
                        timeStretch: poolConfig.timeStretch,
                        longsOutstanding: poolInfo.longsOutstanding,
                        longAverageTimeRemaining: calculateTimeRemaining(
                            hyperdrive,
                            uint256(poolInfo.longAverageMaturityTime).divUp(
                                1e36
                            )
                        ),
                        shortsOutstanding: poolInfo.shortsOutstanding,
                        shortAverageTimeRemaining: calculateTimeRemaining(
                            hyperdrive,
                            uint256(poolInfo.shortAverageMaturityTime).divUp(
                                1e36
                            )
                        ),
                        shortBaseVolume: poolInfo.shortBaseVolume
                    })
                )
                .mulDown(poolInfo.sharePrice);
    }

    function lpSharePrice(
        IHyperdrive hyperdrive
    ) internal view returns (uint256) {
        return hyperdrive.presentValue().divDown(hyperdrive.lpTotalSupply());
    }

    function lpTotalSupply(
        IHyperdrive hyperdrive
    ) internal view returns (uint256) {
        return
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID) +
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID) -
            hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw;
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
        if (_selector == IHyperdrive.InvalidApr.selector) {
            return "InvalidApr";
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
        if (_selector == IHyperdrive.InvalidFeeAmounts.selector) {
            return "InvalidFeeAmounts";
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
        if (_selector == IHyperdrive.ZeroAmount.selector) {
            return "ZeroAmount";
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
        if (_selector == IHyperdrive.FixedPointMath_AddOverflow.selector) {
            return "FixedPointMath_AddOverflow";
        }
        if (_selector == IHyperdrive.FixedPointMath_SubOverflow.selector) {
            return "FixedPointMath_SubOverflow";
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
