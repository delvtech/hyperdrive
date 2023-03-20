// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "./IMultiToken.sol";

interface IHyperdrive is IMultiToken {
    struct MarketState {
        uint128 shareReserves;
        uint128 bondReserves;
        uint128 longsOutstanding;
        uint128 shortsOutstanding;
    }

    struct Aggregates {
        uint128 averageMaturityTime;
        uint128 baseVolume;
    }

    struct Checkpoint {
        uint256 sharePrice;
        uint128 longBaseVolume;
        uint128 shortBaseVolume;
    }

    struct WithdrawPool {
        uint128 withdrawSharesReadyToWithdraw;
        uint128 capital;
        uint128 interest;
    }

    struct Fees {
        uint256 curve;
        uint256 flat;
        uint256 governance;
    }

    function baseToken() external view returns (address);

    function checkpointDuration() external view returns (uint256);

    function positionDuration() external view returns (uint256);

    function timeStretch() external view returns (uint256);

    function initialSharePrice() external view returns (uint256);

    function checkpoint(uint256 _checkpointTime) external;

    function checkpoints(
        uint256 _checkpoint
    ) external view returns (Checkpoint memory);

    function longAggregates() external view returns (Aggregates memory);

    function shortAggregates() external view returns (Aggregates memory);

    function withdrawPool() external view returns (WithdrawPool memory);

    function marketState() external view returns (MarketState memory);

    function fees() external view returns (Fees memory);

    function getPoolConfiguration()
        external
        view
        returns (
            uint256 _initialSharePrice_,
            uint256 _positionDuration,
            uint256 _checkpointDuration,
            uint256 _timeStretch,
            IHyperdrive.Fees memory _fees
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
    ) external returns (uint256, uint256, uint256);

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
