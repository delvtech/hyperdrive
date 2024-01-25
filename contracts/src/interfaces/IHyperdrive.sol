// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "./IERC20.sol";
import { IHyperdriveCore } from "./IHyperdriveCore.sol";
import { IHyperdriveEvents } from "./IHyperdriveEvents.sol";
import { IHyperdriveRead } from "./IHyperdriveRead.sol";
import { IMultiToken } from "./IMultiToken.sol";

interface IHyperdrive is
    IHyperdriveEvents,
    IHyperdriveRead,
    IHyperdriveCore,
    IMultiToken
{
    /// Structs ///

    struct MarketState {
        /// @dev The pool's share reserves.
        uint128 shareReserves;
        /// @dev The pool's bond reserves.
        uint128 bondReserves;
        /// @dev The global exposure of the pool due to open longs
        uint128 longExposure;
        /// @dev The amount of longs that are still open.
        uint128 longsOutstanding;
        /// @dev The net amount of shares that have been added and removed from
        ///      the share reserves due to flat updates.
        int128 shareAdjustment;
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
        /// @dev The proceeds in base of the unredeemed matured positions.
        uint112 zombieBaseProceeds;
        /// @dev The shares reserved for unredeemed matured positions.
        uint128 zombieShareReserves;
    }

    struct Checkpoint {
        /// @dev The vault share price during the first transaction in the
        ///      checkpoint. This is used to track the amount of interest
        ///      accrued by shorts as well as the vault share price at closing
        //       of matured longs and shorts.
        uint128 vaultSharePrice;
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
        uint256 governanceLP;
        /// @dev The portion of the zombie interest that goes to governance.
        uint256 governanceZombie;
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
        /// @dev The initial vault share price.
        uint256 initialVaultSharePrice;
        /// @dev The minimum share reserves.
        uint256 minimumShareReserves;
        /// @dev The minimum amount of tokens that a position can be opened or
        ///      closed with.
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
    }

    struct PoolInfo {
        /// @dev The reserves of shares held by the pool.
        uint256 shareReserves;
        /// @dev The adjustment applied to the share reserves when pricing
        ///      bonds. This is used to ensure that the pricing mechanism is
        ///      held invariant under flat updates for security reasons.
        int256 shareAdjustment;
        /// @dev The proceeds in base of the unredeemed matured positions.
        uint256 zombieBaseProceeds;
        /// @dev The shares reserved for unredeemed matured positions.
        uint256 zombieShareReserves;
        /// @dev The reserves of bonds held by the pool.
        uint256 bondReserves;
        /// @dev The total supply of LP shares.
        uint256 lpTotalSupply;
        /// @dev The current vault share price.
        uint256 vaultSharePrice;
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

    /// @notice Thrown when the inputs to a batch transfer don't match in
    ///         length.
    error BatchInputLengthMismatch();

    /// @notice Thrown when the initializer doesn't provide sufficient liquidity
    ///         to cover the minimum share reserves and the LP shares that are
    ///         burned on initialization.
    error BelowMinimumContribution();

    /// @notice Thrown when the exponent to `FixedPointMath.exp` would cause the
    ///         the result to be larger than the representable scale.
    error ExpInvalidExponent();

    /// @notice Thrown when a permit signature is expired.
    error ExpiredDeadline();

    /// @notice Thrown when the pool doesn't have sufficient liquidity to
    ///         complete the trade.
    error InsufficientLiquidity();

    /// @notice Thrown when the pool's APR is outside the bounds specified by
    ///         a LP when they are adding liquidity.
    error InvalidApr();

    /// @notice Thrown when the base token isn't valid. Each instance will have
    ///         different criteria for what constitutes a valid base token.
    error InvalidBaseToken();

    /// @notice Thrown when the checkpoint duration specified is zero.
    error InvalidCheckpointDuration();

    /// @notice Thrown when the checkpoint time provided to `checkpoint` is
    ///         larger than the current checkpoint or isn't divisible by the
    ///         checkpoint duration.
    error InvalidCheckpointTime();

    // FIXME: Replace this with a variant of InsufficientLiquidity
    //
    /// @notice Thrown when a trade causes the effective share reserves to fall
    ///         below the minimum share reserves.
    error InvalidEffectiveShareReserves();

    /// @notice Thrown when the caller of one of MultiToken's bridge-only
    ///         functions is not the corresponding bridge.
    error InvalidERC20Bridge();

    /// @notice Thrown when the curve fee, flat fee, governance LP fee, or
    ///         governance zombie fee is greater than 100%.
    error InvalidFeeAmounts();

    /// @notice Thrown when a destination other than the fee collector is
    ///         specified in `collectGovernanceFee`.
    error InvalidFeeDestination();

    /// @notice Thrown when the initial share price doesn't match the share
    ///         price of the underlying yield source on deployment.
    error InvalidInitialVaultSharePrice();

    /// @notice Thrown when the minimum share reserves is too small. The
    ///         absolute smallest allowable minimum share reserves is 1e3;
    ///         however, yield sources may require a larger minimum share
    ///         reserves.
    error InvalidMinimumShareReserves();

    /// @notice Thrown when the position duration is smaller than the checkpoint
    ///         duration or is not a multiple of the checkpoint duration.
    error InvalidPositionDuration();

    // FIXME: This is more of a fatal error, so it probably doesn't fall into
    //        the same bucket as `InsufficientLiquidity`.
    //
    /// @notice Thrown when update liquidity brings the share reserves below
    ///         the minimum share reserves.
    error InvalidShareReserves();

    /// @notice Thrown when an invalid signature is used provide permit access
    ///         to the MultiToken. A signature is considered to be invalid if
    ///         it fails to recover to the owner's address.
    error InvalidSignature();

    /// @notice Thrown when the timestamp used to construct an asset ID exceeds
    ///         the uint248 scale.
    error InvalidTimestamp();

    // FIXME: Replace this with a variant of InsufficientLiquidity
    //
    /// @notice Thrown when the pool doesn't have sufficient liquidity to
    ///         complete the trade.
    error InvalidTradeSize();

    /// @notice Thrown when the input to `FixedPointMath.ln` is less than or
    ///         equal to zero.
    error LnInvalidInput();

    /// @notice Thrown when vault share price is smaller than the minimum share
    ///         price. This protects traders from unknowingly opening a long or
    ///         short after negative interest has accrued.
    error MinimumSharePrice();

    /// @notice Thrown when the input or output amount of a trade is smaller
    ///         than the minimum transaction amount. This protects traders and
    ///         LPs from losses of precision that can occur at small scales.
    error MinimumTransactionAmount();

    // FIXME: Replace this with a variant of InsufficientLiquidity
    //
    /// @notice Thrown when part of the trade dips into the negative interest
    ///         domain.
    error NegativeInterest();

    /// @notice Thrown when the present value is negative. Whatever proceeded
    ///         a negative present value should be reverted.
    error NegativePresentValue();

    /// @notice Thrown when ether is sent to an instance that doesn't accept
    ///         ether as a deposit asset.
    error NotPayable();

    /// @notice Thrown when a slippage guard is violated.
    error OutputLimit();

    /// @notice Thrown when the pool is already initialized and a trader calls
    ///         `initialize`. This prevents the pool from being reinitialized
    ///         after it has been initialized.
    error PoolAlreadyInitialized();

    /// @notice Thrown when the pool is paused and a trader tries to add
    ///         liquidity, open a long, or open a short. Traders can still
    ///         close their existing positions while the pool is paused.
    error PoolIsPaused();

    /// @notice Thrown when the owner passed to permit is the zero address. This
    ///         prevents users from spending the funds in address zero by
    ///         sending an invalid signature to ecrecover.
    error RestrictedZeroAddress();

    /// @notice Thrown by a read-only function called by the proxy. Unlike a
    ///         normal error, this error actually indicates that a read-only
    ///         call succeeded. The data that it wraps is the return data from
    ///         the read-only call.
    error ReturnData(bytes data);

    /// @notice Thrown when an asset is swept from the pool and one of the
    ///         pool's depository assets changes.
    error SweepFailed();

    /// @notice Thrown when an ether transfer fails.
    error TransferFailed();

    /// @notice Thrown when an unauthorized user attempts to access admin
    ///         functionality.
    error Unauthorized();

    /// @notice Thrown when a read-only call succeeds. The proxy architecture
    ///         uses a force-revert delegatecall pattern to ensure that calls
    ///         that are intended to be read-only are actually read-only.
    error UnexpectedSuccess();

    /// @notice Thrown when casting a value to a uint112 that is outside of the
    ///         uint128 scale.
    error UnsafeCastToUint112();

    /// @notice Thrown when casting a value to a uint128 that is outside of the
    ///         uint128 scale.
    error UnsafeCastToUint128();

    /// @notice Thrown when casting a value to a int128 that is outside of the
    ///         int128 scale.
    error UnsafeCastToInt128();

    /// @notice Thrown when an unsupported option is passed to a function or
    ///         a user attempts to sweep an invalid token. The options and sweep
    ///         targets that are supported vary between instances.
    error UnsupportedToken();

    /// Getters ///

    function target0() external view returns (address);

    function target1() external view returns (address);

    function target2() external view returns (address);

    function target3() external view returns (address);
}
