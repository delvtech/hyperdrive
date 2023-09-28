// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "./IERC20.sol";
import { IHyperdriveRead } from "./IHyperdriveRead.sol";
import { IHyperdriveWrite } from "./IHyperdriveWrite.sol";
import { IMultiToken } from "./IMultiToken.sol";

interface IHyperdrive is IHyperdriveRead, IHyperdriveWrite, IMultiToken {
    /// Events ///

    event Initialize(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 apr
    );

    event AddLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount
    );

    event RemoveLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 withdrawalShareAmount
    );

    event RedeemWithdrawalShares(
        address indexed provider,
        uint256 withdrawalShareAmount,
        uint256 baseAmount
    );

    event OpenLong(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    event OpenShort(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    event CloseLong(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    event CloseShort(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    /// Structs ///

    // TODO: Re-evaluate the order of these fields to optimize gas usage.
    struct MarketState {
        /// @dev The pool's share reserves.
        uint128 shareReserves;
        /// @dev The pool's bond reserves.
        uint128 bondReserves;
        /// @dev The amount of longs that are still open.
        uint128 longsOutstanding;
        /// @dev The amount of shorts that are still open.
        uint128 shortsOutstanding;
        /// @dev The average maturity time of outstanding long positions.
        uint128 longAverageMaturityTime;
        /// @dev The average open share price of longs.
        uint128 longOpenSharePrice;
        /// @dev The average maturity time of outstanding short positions.
        uint128 shortAverageMaturityTime;
        /// FIXME: We need to think about this in the context of storage packing.
        /// @dev The net amount of shares that have been added and removed from
        ///      the share reserves due to flat updates.
        int128 shareAdjustment;
        /// @dev The global exposure of the pool due to open longs
        uint128 longExposure;
        /// @dev A flag indicating whether or not the pool has been initialized.
        bool isInitialized;
        /// @dev A flag indicating whether or not the pool is paused.
        bool isPaused;
    }

    // TODO: Re-evaluate the order of these fields to optimize gas usage.
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
        /// @dev The amount lp exposure on longs.
        int128 longExposure;
    }

    struct WithdrawPool {
        /// @dev The amount of withdrawal shares that are ready to be redeemed.
        uint128 readyToWithdraw;
        /// @dev The proceeds recovered by the withdrawal pool.
        uint128 proceeds;
    }

    struct Fees {
        /// @dev The LP fee applied to the curve portion of a trade.
        uint256 curve;
        /// @dev The LP fee applied to the flat portion of a trade.
        uint256 flat;
        /// @dev The portion of the LP fee that goes to governance.
        uint256 governance;
    }

    struct PoolConfig {
        /// @dev The address of the base token.
        IERC20 baseToken;
        /// @dev The initial share price.
        uint256 initialSharePrice;
        /// @dev The minimum share reserves.
        uint256 minimumShareReserves;
        /// @dev The minimum amount of tokens that a position can be opened/closed with.
        uint256 minimumTransactionAmount;
        /// @dev The duration of a position prior to maturity.
        uint256 positionDuration;
        /// @dev The duration of a checkpoint.
        uint256 checkpointDuration;
        /// @dev A parameter which decreases slippage around a target rate.
        uint256 timeStretch;
        /// @dev The address of the governance contract.
        address governance;
        /// @dev The address which collects governance fees
        address feeCollector;
        /// @dev The fees applied to trades.
        IHyperdrive.Fees fees;
        /// @dev The amount of TWAP entries to store.
        uint256 oracleSize;
        /// @dev The amount of time between TWAP updates.
        uint256 updateGap;
    }

    struct PoolInfo {
        /// @dev The reserves of shares held by the pool.
        uint256 shareReserves;
        /// @dev The adjustment applied to the share reserves when pricing
        ///      bonds. This is used to ensure that the pricing mechanism is
        ///      held invariant under flat updates for security reasons.
        int256 shareAdjustment;
        /// @dev The reserves of bonds held by the pool.
        uint256 bondReserves;
        /// @dev The total supply of LP shares.
        uint256 lpTotalSupply;
        /// @dev The current share price.
        uint256 sharePrice;
        /// @dev An amount of bonds representing outstanding unmatured longs.
        uint256 longsOutstanding;
        /// @dev The average maturity time of the outstanding longs.
        uint256 longAverageMaturityTime;
        /// @dev An amount of bonds representing outstanding unmatured shorts.
        uint256 shortsOutstanding;
        /// @dev The average maturity time of the outstanding shorts.
        uint256 shortAverageMaturityTime;
        /// @dev The amount of withdrawal shares that are ready to be redeemed.
        uint256 withdrawalSharesReadyToWithdraw;
        /// @dev The proceeds recovered by the withdrawal pool.
        uint256 withdrawalSharesProceeds;
        /// @dev The share price of LP shares. This can be used to mark LP
        ///      shares to market.
        uint256 lpSharePrice;
        /// @dev The global exposure of the pool due to open positions
        uint256 longExposure;
    }

    struct OracleState {
        /// @notice The pointer to the most recent buffer entry
        uint128 head;
        /// @notice The last timestamp we wrote to the buffer
        uint128 lastTimestamp;
    }

    /// IHyperdrive ///

    /// ##################
    /// ### Hyperdrive ###
    /// ##################
    error ApprovalFailed();
    error BaseBufferExceedsShareReserves();
    error BelowMinimumContribution();
    error BelowMinimumShareReserves();
    error InvalidApr();
    error InvalidBaseToken();
    error InvalidCheckpointTime();
    error InvalidCheckpointDuration();
    error InvalidInitialSharePrice();
    error InvalidMaturityTime();
    error InvalidMinimumShareReserves();
    error InvalidPositionDuration();
    error InvalidShareReserves();
    error InvalidFeeAmounts();
    error NegativeInterest();
    error NegativePresentValue();
    error NoAssetsToWithdraw();
    error NotPayable();
    error OutputLimit();
    error Paused();
    error PoolAlreadyInitialized();
    error ShareReservesDeltaExceedsBondReservesDelta();
    error TransferFailed();
    error UnexpectedAssetId();
    error UnexpectedSender();
    error UnsupportedToken();
    error MinimumTransactionAmount();
    error ZeroLpTotalSupply();

    /// ############
    /// ### TWAP ###
    /// ############
    error QueryOutOfRange();

    /// ####################
    /// ### DataProvider ###
    /// ####################
    error ReturnData(bytes data);
    error CallFailed(bytes4 underlyingError);
    error UnexpectedSuccess();

    /// ###############
    /// ### Factory ###
    /// ###############
    error Unauthorized();
    error InvalidContribution();
    error InvalidToken();
    error MaxFeeTooHigh();
    error FeeTooHigh();
    error NonPayableInitialization();

    /// ######################
    /// ### ERC20Forwarder ###
    /// ######################
    error BatchInputLengthMismatch();
    error ExpiredDeadline();
    error InvalidSignature();
    error InvalidERC20Bridge();
    error RestrictedZeroAddress();

    /// #####################
    /// ### BondWrapper ###
    /// #####################
    error AlreadyClosed();
    error BondMatured();
    error BondNotMatured();
    error InsufficientPrice();
    error MintPercentTooHigh();

    /// ###############
    /// ### AssetId ###
    /// ###############
    error InvalidTimestamp();

    /// ######################
    /// ### FixedPointMath ###
    /// ######################
    error FixedPointMath_InvalidExponent();
    error FixedPointMath_InvalidInput();
    error FixedPointMath_NegativeOrZeroInput();
    error FixedPointMath_NegativeInput();

    /// ######################
    /// ### YieldSpaceMath ###
    /// ######################
    error InvalidTradeSize();
}
