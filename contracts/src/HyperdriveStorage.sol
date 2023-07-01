// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "./interfaces/IERC20.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { Errors } from "./libraries/Errors.sol";
import { MultiTokenStorage } from "./token/MultiTokenStorage.sol";

/// @author DELV
/// @title HyperdriveStorage
/// @notice The storage contract of the Hyperdrive inheritance hierarchy.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveStorage is MultiTokenStorage {
    /// Tokens ///

    // @notice The base asset.
    IERC20 internal immutable _baseToken;

    /// Time ///

    // @notice The amount of seconds between share price checkpoints.
    uint256 internal immutable _checkpointDuration;

    // @notice The amount of seconds that elapse before a bond can be redeemed.
    uint256 internal immutable _positionDuration;

    // @notice A parameter that decreases slippage around a target rate.
    uint256 internal immutable _timeStretch;

    /// Market State ///

    // @notice The share price at the time the pool was created.
    uint256 internal immutable _initialSharePrice;

    /// @notice The state of the market. This includes the reserves, buffers,
    ///         and other data used to price trades and maintain solvency.
    IHyperdrive.MarketState internal _marketState;

    /// @notice The state corresponding to the withdraw pool.
    IHyperdrive.WithdrawPool internal _withdrawPool;

    /// @dev The LP fee applied to the curve portion of a trade.
    uint256 internal immutable _curveFee;
    /// @dev The LP fee applied to the flat portion of a trade.
    uint256 internal immutable _flatFee;
    /// @dev The portion of the LP fee that goes to governance.
    uint256 internal immutable _governanceFee;

    /// @notice Hyperdrive positions are bucketed into checkpoints, which
    ///         allows us to avoid poking in any period that has LP or trading
    ///         activity. The checkpoints contain the starting share price from
    ///         the checkpoint as well as aggregate volume values.
    mapping(uint256 checkpointNumber => IHyperdrive.Checkpoint checkpoint)
        internal _checkpoints;

    /// @notice Addresses approved in this mapping can pause all deposits into
    ///         the contract and other non essential functionality.
    mapping(address user => bool isPauser) internal _pausers;

    // Governance fees that haven't been collected yet denominated in shares.
    uint256 internal _governanceFeesAccrued;

    // The address that can pause the contract
    address internal _governance;

    /// The address which collects governance fees
    address internal immutable _feeCollector;

    /// TWAP ///

    /// @notice The amount of time between oracle data sample updates
    uint256 internal immutable _updateGap;

    /// @notice A struct to hold packed oracle entries
    struct OracleData {
        // The timestamp this data was added at
        uint32 timestamp;
        // The running sun of all previous data entries weighted by time
        uint224 data;
    }

    /// @notice This buffer contains the timestamps and data recorded in the oracle
    OracleData[] internal _buffer;

    /// @notice The struct holding the head and last timestamp
    IHyperdrive.OracleState internal _oracle;

    /// @notice Initializes Hyperdrive's storage.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(IHyperdrive.PoolConfig memory _config) {
        // Initialize the base token address.
        _baseToken = _config.baseToken;

        // Initialize the time configurations. There must be at least one
        // checkpoint per term to avoid having a position duration of zero.
        if (_config.checkpointDuration == 0) {
            revert Errors.InvalidCheckpointDuration();
        }
        _checkpointDuration = _config.checkpointDuration;
        if (
            _config.positionDuration < _config.checkpointDuration ||
            _config.positionDuration % _config.checkpointDuration != 0
        ) {
            revert Errors.InvalidPositionDuration();
        }
        _positionDuration = _config.positionDuration;
        _timeStretch = _config.timeStretch;
        _initialSharePrice = _config.initialSharePrice;
        _governance = _config.governance;
        _feeCollector = _config.feeCollector;

        if (
            _config.fees.curve > 1e18 ||
            _config.fees.flat > 1e18 ||
            _config.fees.governance > 1e18
        ) {
            revert Errors.InvalidFeeAmounts();
        }
        _curveFee = _config.fees.curve;
        _flatFee = _config.fees.flat;
        _governanceFee = _config.fees.governance;

        // Initialize the oracle.
        _updateGap = _config.updateGap;
    }
}
