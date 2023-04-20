// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "./IMultiToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IHyperdrive is IMultiToken {
    // TODO: Add documentation
    struct MarketState {
        uint128 shareReserves;
        uint128 bondReserves;
        uint128 longsOutstanding;
        uint128 shortsOutstanding;
        bool isInitialized;
        bool isPaused;
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
        uint128 withdrawalSharesReadyToWithdraw;
        uint128 capital;
        uint128 interest;
    }

    // TODO: Add documentation
    struct Fees {
        uint256 curve;
        uint256 flat;
        uint256 governance;
    }

    struct PoolConfig {
        /// @dev The initial share price of the base asset.
        uint256 initialSharePrice;
        /// @dev The duration of a long or short trade.
        uint256 positionDuration;
        /// @dev The duration of a checkpoint.
        uint256 checkpointDuration;
        /// @dev A parameter which decreases slippage around a target rate.
        uint256 timeStretch;
        /// @dev The LP fee applied to the flat portion of a trade.
        uint256 flatFee;
        /// @dev The LP fee applied to the curve portion of a trade.
        uint256 curveFee;
        /// @dev The percentage fee applied to the LP fees.
        uint256 governanceFee;
    }

    struct PoolInfo {
        /// @dev The reserves of shares held by the pool.
        uint256 shareReserves;
        /// @dev The reserves of bonds held by the pool.
        uint256 bondReserves;
        /// @dev The total supply of LP shares.
        uint256 lpTotalSupply;
        /// @dev The current share price.
        uint256 sharePrice;
        /// @dev An amount of bonds representating outstanding unmatured longs.
        uint256 longsOutstanding;
        /// @dev The average maturity time of the outstanding longs.
        uint256 longAverageMaturityTime;
        /// @dev The cumulative amount of base paid for oustanding longs.
        uint256 longBaseVolume;
        /// @dev An amount of bonds representating outstanding unmatured shorts.
        uint256 shortsOutstanding;
        /// @dev The average maturity time of the outstanding shorts.
        uint256 shortAverageMaturityTime;
        /// @dev The cumulative amount of base paid for oustanding shorts.
        uint256 shortBaseVolume;
        /// @dev The amount of withdrawal shares that are ready to be redeemed.
        uint256 withdrawalSharesReadyToWithdraw;
        /// @dev The amount of margin recovered by the withdrawal pool.
        uint256 capital;
        /// @dev The amount of interest accrued to the withdrawal pool.
        uint256 interest;
    }

    function baseToken() external view returns (address);

    function checkpoints(
        uint256 _checkpoint
    ) external view returns (Checkpoint memory);

    function withdrawPool() external view returns (WithdrawPool memory);

    function getPoolConfig() external view returns (PoolConfig memory);

    function getPoolInfo() external view returns (PoolInfo memory);

    function checkpoint(uint256 _checkpointTime) external;

    function setPauser(address who, bool status) external;

    function pause(bool status) external;

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
