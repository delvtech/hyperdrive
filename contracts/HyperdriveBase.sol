// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MultiToken } from "contracts/MultiToken.sol";
import { AssetId } from "contracts/libraries/AssetId.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";

/// @author Delve
/// @title HyperdriveBase
/// @notice The base contract of the Hyperdrive inheritance hierarchy.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveBase is MultiToken {
    using FixedPointMath for uint256;

    /// Tokens ///

    // @notice The base asset.
    IERC20 public immutable baseToken;

    /// Time ///

    // @notice The amount of seconds between share price checkpoints.
    uint256 public immutable checkpointDuration;

    // @notice The amount of seconds that elapse before a bond can be redeemed.
    uint256 public immutable positionDuration;

    // @notice A parameter that decreases slippage around a target rate.
    uint256 public immutable timeStretch;

    /// Market state ///

    // @notice The share price at the time the pool was created.
    uint256 public immutable initialSharePrice;

    /// @notice Checkpoints of historical share prices.
    mapping(uint256 => uint256) public checkpoints;

    // TODO: Optimize the storage layout.
    //
    /// @notice Checkpoints of historical base volume of long positions.
    mapping(uint256 => uint256) public longBaseVolumeCheckpoints;

    // TODO: Optimize the storage layout.
    //
    /// @notice Checkpoints of historical base volume of short positions.
    mapping(uint256 => uint256) public shortBaseVolumeCheckpoints;

    /// @notice The share reserves. The share reserves multiplied by the share
    ///         price give the base reserves, so shares are a mechanism of
    ///         ensuring that interest is properly awarded over time.
    uint256 public shareReserves;

    /// @notice The bond reserves. In Hyperdrive, the bond reserves aren't
    ///         backed by pre-minted bonds and are instead used as a virtual
    ///         value that ensures that the spot rate changes according to the
    ///         laws of supply and demand.
    uint256 public bondReserves;

    /// @notice The amount of longs that are still open.
    uint256 public longsOutstanding;

    /// @notice The amount of shorts that are still open.
    uint256 public shortsOutstanding;

    /// @notice The average maturity time of long positions.
    uint256 public longAverageMaturityTime;

    /// @notice The average maturity time of short positions.
    uint256 public shortAverageMaturityTime;

    /// @notice The amount of base paid by outstanding longs.
    uint256 public longBaseVolume;

    /// @notice The amount of base paid to outstanding shorts.
    uint256 public shortBaseVolume;

    /// @notice The amount of long withdrawal shares that haven't been paid out.
    uint256 public longWithdrawalSharesOutstanding;

    /// @notice The amount of short withdrawal shares that haven't been paid out.
    uint256 public shortWithdrawalSharesOutstanding;

    /// @notice The proceeds that have accrued to the long withdrawal shares.
    uint256 public longWithdrawalShareProceeds;

    /// @notice The proceeds that have accrued to the short withdrawal shares.
    uint256 public shortWithdrawalShareProceeds;

    // TODO: Should this be immutable?
    //
    /// @notice The fee paramater to apply to the curve portion of the
    ///         hyperdrive trade equation.
    uint256 public curveFee;

    // TODO: Should this be immutable?
    //
    /// @notice The fee paramater to apply to the flat portion of the hyperdrive
    ///         trade equation.
    uint256 public flatFee;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @param _baseToken The base token contract.
    /// @param _initialSharePrice The initial share price.
    /// @param _checkpointsPerTerm The number of checkpoints that elaspes before
    ///        bonds can be redeemed one-to-one for base.
    /// @param _checkpointDuration The time in seconds between share price
    ///        checkpoints. Position duration must be a multiple of checkpoint
    ///        duration.
    /// @param _timeStretch The time stretch of the pool.
    /// @param _curveFee The fee parameter for the curve portion of the hyperdrive trade equation.
    /// @param _flatFee The fee parameter for the flat portion of the hyperdrive trade equation.
    constructor(
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20 _baseToken,
        uint256 _initialSharePrice,
        uint256 _checkpointsPerTerm,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        uint256 _curveFee,
        uint256 _flatFee
    ) MultiToken(_linkerCodeHash, _linkerFactory) {
        // Initialize the base token address.
        baseToken = _baseToken;

        // Initialize the time configurations. There must be at least one
        // checkpoint per term to avoid having a position duration of zero.
        if (_checkpointsPerTerm == 0) {
            revert Errors.InvalidCheckpointsPerTerm();
        }
        positionDuration = _checkpointsPerTerm * _checkpointDuration;
        checkpointDuration = _checkpointDuration;
        timeStretch = _timeStretch;

        initialSharePrice = _initialSharePrice;

        curveFee = _curveFee;
        flatFee = _flatFee;
    }

    /// Yield Source ///

    /// @notice Transfers base from the user and commits it to the yield source.
    /// @param amount The amount of base to deposit.
    /// @return sharesMinted The shares this deposit creates.
    /// @return sharePrice The share price at time of deposit.
    function deposit(
        uint256 amount
    ) internal virtual returns (uint256 sharesMinted, uint256 sharePrice);

    /// @notice Withdraws shares from the yield source and sends the base
    ///         released to the destination.
    /// @param shares The shares to withdraw from the yieldsource.
    /// @param destination The recipient of the withdrawal.
    /// @return amountWithdrawn The amount of base released by the withdrawal.
    /// @return sharePrice The share price on withdraw.
    function withdraw(
        uint256 shares,
        address destination
    ) internal virtual returns (uint256 amountWithdrawn, uint256 sharePrice);

    ///@notice Loads the share price from the yield source
    ///@return sharePrice The current share price.
    function pricePerShare() internal view virtual returns (uint256 sharePrice);

    /// Checkpoint ///

    /// @notice Allows anyone to mint a new checkpoint.
    /// @param _checkpointTime The time of the checkpoint to create.
    function checkpoint(uint256 _checkpointTime) public virtual;

    /// @dev Creates a new checkpoint if necessary.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @param _sharePrice The current share price.
    /// @return openSharePrice The open share price of the latest checkpoint.
    function _applyCheckpoint(
        uint256 _checkpointTime,
        uint256 _sharePrice
    ) internal virtual returns (uint256 openSharePrice);

    /// Getters ///

    // TODO: The fee parameters aren't immutable right now, but arguably they
    //       should be.
    //
    /// @notice Gets the pool's configuration parameters.
    /// @dev These parameters are immutable, so this should only need to be
    ///      called once.
    /// @return initialSharePrice_ The initial share price.
    /// @return positionDuration_ The duration of positions.
    /// @return checkpointDuration_ The duration of checkpoints.
    /// @return timeStretch_ The time stretch configuration.
    /// @return flatFee_ The flat fee parameter.
    /// @return curveFee_ The flat fee parameter.
    function getPoolConfiguration()
        external
        view
        returns (
            uint256 initialSharePrice_,
            uint256 positionDuration_,
            uint256 checkpointDuration_,
            uint256 timeStretch_,
            uint256 flatFee_,
            uint256 curveFee_
        )
    {
        return (
            initialSharePrice,
            positionDuration,
            checkpointDuration,
            timeStretch,
            flatFee,
            curveFee
        );
    }

    /// @notice Gets info about the pool's reserves and other state that is
    ///         important to evaluate potential trades.
    /// @return shareReserves_ The share reserves.
    /// @return bondReserves_ The bond reserves.
    /// @return lpTotalSupply The total supply of LP shares.
    /// @return sharePrice The share price.
    /// @return longsOutstanding_ The outstanding longs that haven't matured.
    /// @return longAverageMaturityTime_ The average maturity time of the
    ///         outstanding longs.
    /// @return longBaseVolume_ The amount of base paid by longs on opening.
    /// @return shortsOutstanding_ The outstanding shorts that haven't matured.
    /// @return shortAverageMaturityTime_ The average maturity time of the
    ///         outstanding shorts.
    /// @return shortBaseVolume_ The amount of base paid to shorts on
    ///         opening.
    function getPoolInfo()
        external
        view
        returns (
            uint256 shareReserves_,
            uint256 bondReserves_,
            uint256 lpTotalSupply,
            uint256 sharePrice,
            uint256 longsOutstanding_,
            uint256 longAverageMaturityTime_,
            uint256 longBaseVolume_,
            uint256 shortsOutstanding_,
            uint256 shortAverageMaturityTime_,
            uint256 shortBaseVolume_
        )
    {
        return (
            shareReserves,
            bondReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            pricePerShare(),
            longsOutstanding,
            longAverageMaturityTime,
            longBaseVolume,
            shortsOutstanding,
            shortAverageMaturityTime,
            shortBaseVolume
        );
    }

    /// Helpers ///

    /// @dev Calculates the normalized time remaining of a position.
    /// @param _maturityTime The maturity time of the position.
    /// @return timeRemaining The normalized time remaining (in [0, 1]).
    function _calculateTimeRemaining(
        uint256 _maturityTime
    ) internal view returns (uint256 timeRemaining) {
        timeRemaining = _maturityTime > block.timestamp
            ? _maturityTime - block.timestamp
            : 0;
        timeRemaining = (timeRemaining).divDown(positionDuration);
        return timeRemaining;
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
            (block.timestamp % checkpointDuration);
        return latestCheckpoint;
    }
}
