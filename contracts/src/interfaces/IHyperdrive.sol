// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "./IERC20.sol";
import { IHyperdriveCore } from "./IHyperdriveCore.sol";
import { IHyperdriveRead } from "./IHyperdriveRead.sol";
import { IMultiToken } from "./IMultiToken.sol";

interface IHyperdrive is IHyperdriveRead, IHyperdriveCore, IMultiToken {
    /// Events ///

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

    event CollectGovernanceFee(
        address indexed collector,
        uint256 baseFees,
        uint256 sharePrice
    );

    /// Structs ///

    struct MarketState {
        /// @dev The pool's share reserves.
        uint128 shareReserves;
        /// @dev The pool's bond reserves.
        uint128 bondReserves;
        /// @dev The net amount of shares that have been added and removed from
        ///      the share reserves due to flat updates.
        int128 shareAdjustment;
        /// @dev The global exposure of the pool due to open longs
        uint128 longExposure;
        /// @dev The amount of longs that are still open.
        uint128 longsOutstanding;
        /// @dev The amount of shorts that are still open.
        uint128 shortsOutstanding;
        /// @dev The average maturity time of outstanding long positions.
        uint128 longAverageMaturityTime;
        /// @dev The average maturity time of outstanding short positions.
        uint128 shortAverageMaturityTime;
        /// @dev A flag indicating whether or not the pool has been initialized.
        bool isInitialized;
        /// @dev A flag indicating whether or not the pool is paused.
        bool isPaused;
    }

    struct Checkpoint {
        /// @dev The share price of the first transaction in the checkpoint.
        ///      This is used to track the amount of interest accrued by shorts
        ///      as well as the share price at closing of matured longs and
        ///      shorts.
        uint128 sharePrice;
        /// @dev If exposure is positive, then we have net long exposure, otherwise
        ///      we have net short exposure in the checkpoint.
        int128 exposure;
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

    struct PoolDeployConfig {
        /// @dev The address of the base token.
        IERC20 baseToken;
        /// @dev The linker factory used by this Hyperdrive instance.
        address linkerFactory;
        /// @dev The hash of the ERC20 linker's code. This is used to derive the
        ///      create2 addresses of the ERC20 linkers used by this instance.
        bytes32 linkerCodeHash;
        /// @dev The minimum share reserves.
        uint256 minimumShareReserves;
        /// @dev The minimum amount of tokens that a position can be opened or
        ///      closed with.
        uint256 minimumTransactionAmount;
        /// @dev The amount of precision expected to lose due to exponentiation
        ///      implementation.
        uint256 precisionThreshold;
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
    }

    struct PoolConfig {
        /// @dev The address of the base token.
        IERC20 baseToken;
        /// @dev The linker factory used by this Hyperdrive instance.
        address linkerFactory;
        /// @dev The hash of the ERC20 linker's code. This is used to derive the
        ///      create2 addresses of the ERC20 linkers used by this instance.
        bytes32 linkerCodeHash;
        /// @dev The minimum share reserves.
        uint256 minimumShareReserves;
        /// @dev The minimum amount of tokens that a position can be opened or
        ///      closed with.
        uint256 minimumTransactionAmount;
        /// @dev The amount of precision expected to lose due to exponentiation
        ///      implementation.
        uint256 precisionThreshold;
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
        /// @dev The initial share price.
        uint256 initialSharePrice;
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

    struct Options {
        /// @dev The address that receives the proceeds of a trade or LP action.
        address destination;
        /// @dev A boolean indicating that the trade or LP action should be
        ///      settled in base if true and in the yield source shares if false.
        bool asBase;
        /// @dev Additional data that can be used to implement custom logic in
        ///      implementation contracts.
        bytes extraData;
    }

    /// Errors ///

    /// ##################
    /// ### Hyperdrive ###
    /// ##################
    error ApprovalFailed();
    // TODO: We should rename this so that it's clear that it pertains to
    // solvency.
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
    error InvalidFeeDestination();
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
    error MinimumSharePrice();
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
    error InvalidIndexes();
    error EndIndexTooLarge();

    /// ######################
    /// ### ERC20Forwarder ###
    /// ######################
    error BatchInputLengthMismatch();
    error ExpiredDeadline();
    error InvalidSignature();
    error InvalidERC20Bridge();
    error RestrictedZeroAddress();

    /// #############################
    /// ### ERC20ForwarderFactory ###
    /// #############################
    error InvalidForwarderAddress();

    /// ###################
    /// ### BondWrapper ###
    /// ###################
    error InvalidRecipient(address recipient);
    error AlreadyClosed();
    error BondMatured();
    error BondNotMatured();
    error InsufficientPrice();
    error InputLengthMismatch();
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

    /// ################
    /// ### SafeCast ###
    /// ################
    error UnsafeCastToUint128();
    error UnsafeCastToInt128();

    /// Getters ///

    function target0() external view returns (address);

    function target1() external view returns (address);
}
