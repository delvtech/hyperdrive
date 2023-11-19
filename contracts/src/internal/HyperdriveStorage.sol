// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { FixedPointMath, ONE } from "../libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../libraries/HyperdriveMath.sol";

/// @author DELV
/// @title HyperdriveStorage
/// @notice Hyperdrive's storage contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveStorage is ReentrancyGuard {
    using FixedPointMath for uint256;

    /// Tokens ///

    /// @dev The base asset.
    IERC20 internal immutable _baseToken;

    /// Time ///

    /// @dev The amount of seconds between share price checkpoints.
    uint256 internal immutable _checkpointDuration;

    /// @dev The amount of seconds that elapse before a bond can be redeemed.
    uint256 internal immutable _positionDuration;

    /// @dev A parameter that decreases slippage around a target rate.
    uint256 internal immutable _timeStretch;

    /// Fees ///

    /// @dev The LP fee applied to the curve portion of a trade.
    uint256 internal immutable _curveFee;

    /// @dev The LP fee applied to the flat portion of a trade.
    uint256 internal immutable _flatFee;

    /// @dev The portion of the LP fee that goes to governance.
    uint256 internal immutable _governanceFee;

    /// Market State ///

    /// @dev The share price at the time the pool was created.
    uint256 internal immutable _initialSharePrice;

    /// @dev The minimum amount of share reserves that must be maintained at all
    ///      times. This is used to enforce practical limits on the share
    ///      reserves to avoid numerical issues that can occur if the share
    ///      reserves become very small or equal to zero.
    uint256 internal immutable _minimumShareReserves;

    /// @dev The minimum amount of tokens that a position can be opened or
    ///      closed with.
    uint256 internal immutable _minimumTransactionAmount;

    /// @dev The amount of precision expected to lose due to exponentiation
    ///      implementation.
    uint256 internal immutable _precisionThreshold;

    /// @dev The state of the market. This includes the reserves, buffers, and
    ///      other data used to price trades and maintain solvency.
    IHyperdrive.MarketState internal _marketState;

    /// @dev The state corresponding to the withdraw pool.
    IHyperdrive.WithdrawPool internal _withdrawPool;

    /// @dev Hyperdrive positions are bucketed into checkpoints, which allows us
    ///      to avoid poking in any period that has LP or trading activity. The
    ///      checkpoints contain the starting share price from the checkpoint as
    ///      well as aggregate volume values.
    mapping(uint256 checkpointNumber => IHyperdrive.Checkpoint checkpoint)
        internal _checkpoints;

    /// Admin ///

    /// @dev The address which collects governance fees.
    address internal immutable _feeCollector;

    /// @dev The address that can pause the contract.
    address internal _governance;

    /// @dev Governance fees that haven't been collected yet denominated in shares.
    uint256 internal _governanceFeesAccrued;

    /// @dev Addresses approved in this mapping can pause all deposits into the
    ///      contract and other non essential functionality.
    mapping(address user => bool isPauser) internal _pausers;

    /// MultiToken ///

    /// @dev The forwarder factory that deploys ERC20 forwarders for this
    ///      instance.
    address internal immutable _linkerFactory;

    /// @dev The bytecode hash of the contract which forwards purely ERC20 calls
    ///      to this contract.
    bytes32 internal immutable _linkerCodeHash;

    /// @dev Allows loading of each balance.
    mapping(uint256 tokenId => mapping(address user => uint256 balance))
        internal _balanceOf;

    /// @dev Allows loading of each total supply.
    mapping(uint256 tokenId => uint256 supply) internal _totalSupply;

    /// @dev Uniform approval for all tokens.
    mapping(address from => mapping(address caller => bool isApproved))
        internal _isApprovedForAll;

    /// @dev Additional optional per token approvals. This is non-standard for
    ///      ERC1155, but it's necessary to replicate the ERC20 interface.
    mapping(uint256 tokenId => mapping(address from => mapping(address caller => uint256 approved)))
        internal _perTokenApprovals;

    /// @dev A mapping to track the permitForAll signature nonces.
    mapping(address user => uint256 nonce) internal _nonces;

    /// Constructor ///

    /// @notice Instantiates Hyperdrive's storage.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(IHyperdrive.PoolConfig memory _config) {
        // Initialize the base token address.
        _baseToken = _config.baseToken;

        // Initialize the minimum share reserves. The minimum share reserves
        // defines the amount of shares that will be reserved to ensure that
        // the share reserves are never empty. We will also burn LP shares equal
        // to the minimum share reserves upon initialization to ensure that the
        // total supply of active LP tokens is always greater than zero. We
        // don't allow a value less than 1e3 to avoid numerical issues that
        // occur with small amounts of shares.
        if (_config.minimumShareReserves < 1e3) {
            revert IHyperdrive.InvalidMinimumShareReserves();
        }
        _minimumShareReserves = _config.minimumShareReserves;

        _minimumTransactionAmount = _config.minimumTransactionAmount;
        _precisionThreshold = _config.precisionThreshold;

        // Initialize the time configurations. There must be at least one
        // checkpoint per term to avoid having a position duration of zero.
        if (_config.checkpointDuration == 0) {
            revert IHyperdrive.InvalidCheckpointDuration();
        }
        _checkpointDuration = _config.checkpointDuration;
        if (
            _config.positionDuration < _config.checkpointDuration ||
            _config.positionDuration % _config.checkpointDuration != 0
        ) {
            revert IHyperdrive.InvalidPositionDuration();
        }
        _positionDuration = _config.positionDuration;
        _timeStretch = _config.timeStretch;
        _initialSharePrice = _pricePerShare();
        _governance = _config.governance;
        _feeCollector = _config.feeCollector;

        // Initialize the fee parameters.
        if (
            _config.fees.curve > 1e18 ||
            _config.fees.flat > 1e18 ||
            _config.fees.governance > 1e18
        ) {
            revert IHyperdrive.InvalidFeeAmounts();
        }
        _curveFee = _config.fees.curve;
        _flatFee = _config.fees.flat;
        _governanceFee = _config.fees.governance;

        // Initialize the MultiToken immutables.
        _linkerFactory = _config.linkerFactory;
        _linkerCodeHash = _config.linkerCodeHash;
    }

    /// @dev Loads the share price from the yield source.
    /// @notice This function is defined within this contract since it is necessary for initialization of _initialSharePrice.
    /// @return sharePrice The current share price.
    function _pricePerShare()
        internal
        view
        virtual
        returns (uint256 sharePrice);
}
