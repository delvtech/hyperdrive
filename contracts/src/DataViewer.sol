// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { HyperdriveBase } from "./HyperdriveBase.sol";
import { Errors } from "./libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";

interface ILoad {
    function load(uint256[] calldata _slots) external view returns (bytes32[] memory);
}

/// @author Delve
/// @title DataViewer
/// @notice This contract uses the load function of a Hyperdrive instance to let you 
///         implement custom getters
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract DataViewer is HyperdriveBase {

    ILoad public hyperdrive;

    /// @notice These will still be set as immutables which we may expose here
    ///         but in that case they will only be accurate for one deployment.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @param _baseToken The base token contract.
    /// @param _initialSharePrice The initial share price.
    /// @param _checkpointsPerTerm The number of checkpoints that elapses before
    ///        bonds can be redeemed one-to-one for base.
    /// @param _checkpointDuration The time in seconds between share price
    ///        checkpoints. Position duration must be a multiple of checkpoint
    ///        duration.
    /// @param _timeStretch The time stretch of the pool.
    /// @param _fees The fees to apply to trades.
    /// @param _governance The address of the governance contract.
    /// @param _hyperdrive The hyperdrive instance to read from
    constructor(
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20 _baseToken,
        uint256 _initialSharePrice,
        uint256 _checkpointsPerTerm,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        IHyperdrive.Fees memory _fees,
        address _governance,
        address _hyperdrive
    )  HyperdriveBase(
            _linkerCodeHash,
            _linkerFactory,
            _baseToken,
            _initialSharePrice,
            _checkpointsPerTerm,
            _checkpointDuration,
            _timeStretch,
            _fees,
            _governance
        )
    {
        hyperdrive = ILoad(_hyperdrive);
    }

    // Extra view functions for immutables, these reference only the data from
    // the constructor of THIS contract and so must be deploy linked with the other one.

    // @notice The amount of seconds between share price checkpoints.
    function getCheckpointDuration() external view returns(uint256) {
        return checkpointDuration;
    }

    // @notice The amount of seconds that elapse before a bond can be redeemed.
    function getPositionDuration() external view returns(uint256) {
        return positionDuration;
    }

    // @notice A parameter that decreases slippage around a target rate.
    function getTimeStretch() external view returns(uint256) {
        return timeStretch;
    }

    // @notice The share price at the time the pool was created.
    function getInitialSharePrice() external view returns(uint256) {
        return initialSharePrice;
    }

    // Extra view functions for state

    /// @notice The reserves and the buffers. This is the primary state used for
    ///         pricing trades and maintaining solvency.
    function getMarketState() external view returns(IHyperdrive.MarketState memory current) {
        uint256 slot;
        assembly ("memory-safe") {
            slot := marketState.slot
        }

        uint256[] memory slots = new uint256[](3);
        slots[0] = slot;
        slots[1] = slot + 1;
        slots[2] = slot + 2;

        bytes32[] memory data = hyperdrive.load(slots);

        uint256 packed = hardCast(data[0]);
        current.shareReserves = (uint128)((packed << 128) >> 128);
        current.bondReserves =  (uint128)(packed >> 128);

        packed = hardCast(data[1]);
        current.longsOutstanding = (uint128)((packed << 128) >> 128);
        current.shortsOutstanding = (uint128)(packed >> 128);

        current.isInitialized = hardCast(data[2]) == 1;
    }

    function hardCast(bytes32 i) internal pure returns(uint256 o) {
        assembly ("memory-safe"){
            o := i
        }
    }

    /// @notice Aggregate values for long positions that are used to enforce
    ///         fairness guarantees.
    function getLongAggregates() external view returns(IHyperdrive.Aggregates memory current) {
        uint256 slot;
        assembly ("memory-safe") {
            slot := longAggregates.slot
        }

        uint256[] memory slots = new uint256[](1);
        slots[0] = slot;

        bytes32[] memory data = hyperdrive.load(slots);

        uint256 packed = hardCast(data[0]);
        current.averageMaturityTime = (uint128)((packed << 128) >> 128);
        current.baseVolume = (uint128)(packed >> 128); 
    }

    /// @notice Aggregate values for short positions that are used to enforce
    ///         fairness guarantees.
    function getShortAggregates() external view returns(IHyperdrive.Aggregates memory current) {
        uint256 slot;
        assembly ("memory-safe") {
            slot := shortAggregates.slot
        }

        uint256[] memory slots = new uint256[](1);
        slots[0] = slot;

        bytes32[] memory data = hyperdrive.load(slots);

        uint256 packed = hardCast(data[0]);
        current.averageMaturityTime = (uint128)((packed << 128) >> 128);
        current.baseVolume = (uint128)(packed >> 128);
    }


    /// @notice The state corresponding to the withdraw pool, expressed as a struct.
    function getWithdrawPool() external view returns(IHyperdrive.WithdrawPool memory current) {
        uint256 slot;
        assembly ("memory-safe") {
            slot := withdrawPool.slot
        }

        uint256[] memory slots = new uint256[](2);
        slots[0] = slot;
        slots[1] = slot + 1;

        bytes32[] memory data = hyperdrive.load(slots);

        uint256 packed = hardCast(data[0]);
        current.withdrawalSharesReadyToWithdraw = (uint128)((packed << 128) >> 128);
        current.capital = (uint128)(packed >> 128);

        packed = hardCast(data[1]);
        current.interest = (uint128)((packed << 128) >> 128);
    }

    /// @notice The fee percentages to be applied to the trade equation
    function getFees() external view returns(IHyperdrive.Fees memory current) {
        uint256 slot;
        assembly ("memory-safe") {
            slot := fees.slot
        }

        uint256[] memory slots = new uint256[](3);
        slots[0] = slot;
        slots[1] = slot + 1;
        slots[2] = slot + 2;

        bytes32[] memory data = hyperdrive.load(slots);

        current.curve = hardCast(data[0]);
        current.flat = hardCast(data[1]);
        current.governance = hardCast(data[2]);
    }

    // Note - we only inherit so that the solidity compiler will tell us slot data for the 
    // state layout. Therefore we override all of these functions to reverts
    function _deposit( uint256, bool) internal pure override returns (uint256, uint256) {
        revert Errors.Unimplemented();
    }

    function _withdraw(uint256, address, bool) internal pure override returns (uint256, uint256) {
        revert Errors.Unimplemented();
    }

    function _pricePerShare() internal pure override  returns (uint256) {
        revert Errors.Unimplemented();
    }

    function checkpoint(uint256) public pure override {
        revert Errors.Unimplemented();
    }

    function _applyCheckpoint(uint256, uint256) internal override pure returns (uint256) {
        revert Errors.Unimplemented();
    } 
}