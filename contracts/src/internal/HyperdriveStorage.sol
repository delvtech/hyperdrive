// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ReentrancyGuard } from "openzeppelin/utils/ReentrancyGuard.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../interfaces/IHyperdriveAdminController.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";

/// @author DELV
/// @title HyperdriveStorage
/// @notice Hyperdrive's storage contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveStorage is ReentrancyGuard {
    using FixedPointMath for uint256;

    /// Metadata ///

    /// @dev The instance's name.
    string internal _name;

    /// Tokens ///

    /// @dev The base asset.
    IERC20 internal immutable _baseToken;

    /// @dev The vault shares asset.
    IERC20 internal immutable _vaultSharesToken;

    /// Time ///

    /// @dev The amount of seconds between vault share price checkpoints.
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
    uint256 internal immutable _governanceLPFee;

    /// @dev The portion of the zombie interest that goes to governance.
    uint256 internal immutable _governanceZombieFee;

    /// Market State ///

    /// @dev The vault share price at the time the pool was created.
    uint256 internal immutable _initialVaultSharePrice;

    /// @dev The minimum amount of share reserves that must be maintained at all
    ///      times. This is used to enforce practical limits on the share
    ///      reserves to avoid numerical issues that can occur if the share
    ///      reserves become very small or equal to zero.
    uint256 internal immutable _minimumShareReserves;

    /// @dev The minimum amount of tokens that a position can be opened or
    ///      closed with.
    uint256 internal immutable _minimumTransactionAmount;

    /// @dev The maximum delta between the last checkpoint's weighted spot APR
    ///      and the current spot APR for an LP to add liquidity. This protects
    ///      LPs from sandwich attacks.
    uint256 internal immutable _circuitBreakerDelta;

    /// @dev The state of the market. This includes the reserves, buffers, and
    ///      other data used to price trades and maintain solvency.
    IHyperdrive.MarketState internal _marketState;

    /// @dev The state corresponding to the withdraw pool.
    IHyperdrive.WithdrawPool internal _withdrawPool;

    /// @dev Hyperdrive positions are bucketed into checkpoints, which allows us
    ///      to avoid poking in any period that has LP or trading activity. The
    ///      checkpoints contain the starting vault share price from the
    ///      checkpoint as well as aggregate volume values.
    mapping(uint256 checkpointNumber => IHyperdrive.Checkpoint checkpoint)
        internal _checkpoints;

    /// Admin ///

    // TODO: This isn't included in `IHyperdrive.PoolConfig` for backwards
    //       compatability, but we should add it in a future breaking version.
    //
    /// @dev The address that contains the admin configuration for this instance.
    /// @dev A HyperdriveFactory instance can serve as the admin controller.
    IHyperdriveAdminController internal immutable _adminController;

    /// @dev Governance fees that haven't been collected yet denominated in shares.
    uint256 internal _governanceFeesAccrued;

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

    // TODO: It would be good to update `PoolConfig` when we make other breaking
    //       changes.
    //
    /// @notice Instantiates Hyperdrive's storage.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController
    ) {
        // Initialize the base and vault shares token addresses.
        _baseToken = _config.baseToken;
        _vaultSharesToken = _config.vaultSharesToken;

        // Initialize the initial vault share price.
        _initialVaultSharePrice = _config.initialVaultSharePrice;

        // Initialize the minimum share reserves. The minimum share reserves
        // defines the amount of shares that will be reserved to ensure that
        // the share reserves are never empty. We will also burn LP shares equal
        // to the minimum share reserves upon initialization to ensure that the
        // total supply of active LP tokens is always greater than zero.
        _minimumShareReserves = _config.minimumShareReserves;

        // Initialize the minimum transaction amount. The minimum transaction
        // amount defines the minimum input that the system will allow, which
        // prevents weird rounding issues that can occur with very small
        // amounts.
        _minimumTransactionAmount = _config.minimumTransactionAmount;

        // Initialize the maximum add liquidity APR delta. The maximum add
        // liquidity APR delta defines the maximum delta between the current
        // spot APR and the weighted spot APR from the last checkpoint for an
        // LP to add liquidity. This mitigates the possibility of LP sandwich
        // attacks by making them economically infeasible to pull off.
        _circuitBreakerDelta = _config.circuitBreakerDelta;

        // Initialize the time configurations. There must be at least one
        // checkpoint per term to avoid having a position duration of zero.
        _checkpointDuration = _config.checkpointDuration;
        _positionDuration = _config.positionDuration;
        _timeStretch = _config.timeStretch;

        // Initialize the fee parameters.
        _curveFee = _config.fees.curve;
        _flatFee = _config.fees.flat;
        _governanceLPFee = _config.fees.governanceLP;
        _governanceZombieFee = _config.fees.governanceZombie;

        // Initialize the MultiToken immutables.
        _linkerFactory = _config.linkerFactory;
        _linkerCodeHash = _config.linkerCodeHash;

        // Initialize the admin controller.
        _adminController = __adminController;
    }
}
