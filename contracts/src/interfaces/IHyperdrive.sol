// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "./IMultiToken.sol";

interface IHyperdrive is IMultiToken {
    // TODO: Add documentation
    struct MarketState {
        uint128 shareReserves;
        uint128 bondReserves;
        uint128 longsOutstanding;
        uint128 shortsOutstanding;
    }

    // TODO: Add documentation
    struct Aggregates {
        uint128 averageMaturityTime;
        uint128 baseVolume;
    }

    struct Checkpoint {
        /// @dev The share price of the first transaction in the checkpoint.
        ///      This is used to track the amount of interest accrued by shorts
        ///      as well as the share price at closing of matured longs and
        ///      shorts.
        uint128 sharePrice;
        /// @dev The weighted average of the share prices that all of the longs
        ///      in the checkpoint were opened at. This is used as the opening
        ///      share price of longs to properly attribute interest collected
        ///      on longs to the withdrawal pool and prevent dust from being
        ///      stuck in the contract.
        uint128 longSharePrice;
        /// @dev The aggregate amount of base that was paid to open longs in the
        ///      checkpoint.
        uint128 longBaseVolume;
        /// @dev The aggregate amount of base that was committed by LPs to pay
        ///      for the bonds that were sold short in the checkpoint.
        uint128 shortBaseVolume;
    }

    // TODO: Add documentation
    struct WithdrawPool {
        uint128 withdrawSharesReadyToWithdraw;
        uint128 capital;
        uint128 interest;
    }

    // TODO: Add documentation
    struct Fees {
        uint256 curve;
        uint256 flat;
        uint256 governance;
    }

    function baseToken() external view returns (address);

    function checkpoints(
        uint256 _checkpoint
    ) external view returns (Checkpoint memory);

    function withdrawPool() external view returns (WithdrawPool memory);

    function getPoolConfiguration()
        external
        view
        returns (
            uint256 _initialSharePrice_,
            uint256 _positionDuration,
            uint256 _checkpointDuration,
            uint256 _timeStretch,
            uint256 _flatFee,
            uint256 _curveFee,
            uint256 _governanceFee
        );

    function getPoolInfo()
        external
        view
        returns (
            uint256 _shareReserves,
            uint256 _bondReserves_,
            uint256 _lpTotalSupply,
            uint256 _sharePrice,
            uint256 _longsOutstanding,
            uint256 _longAverageMaturityTime,
            uint256 _longBaseVolume,
            uint256 _shortsOutstanding,
            uint256 _shortAverageMaturityTime,
            uint256 _shortBaseVolume
        );

    function checkpoint(uint256 _checkpointTime) external;

    function initialize(
        uint256 _contribution,
        uint256 _apr,
        address _destination,
        bool _asUnderlying
    ) external;

    function addLiquidity(
        uint256 _contribution,
        uint256 _minApr,
        uint256 _maxApr,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256);

    function removeLiquidity(
        uint256 _shares,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256, uint256);

    function redeemWithdrawalShares(
        uint256 _shares,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256 _proceeds);

    function openLong(
        uint256 _baseAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256);

    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256);

    function openShort(
        uint256 _bondAmount,
        uint256 _maxDeposit,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256);

    function closeShort(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256);
}
