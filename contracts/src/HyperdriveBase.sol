// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveStorage } from "./HyperdriveStorage.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { IHyperdriveWrite } from "./interfaces/IHyperdriveWrite.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import { SafeCast } from "./libraries/SafeCast.sol";
import { MultiToken } from "./token/MultiToken.sol";

/// @author DELV
/// @title HyperdriveBase
/// @notice The base contract of the Hyperdrive inheritance hierarchy.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveBase is
    IHyperdriveWrite,
    MultiToken,
    HyperdriveStorage
{
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

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

    /// @notice Initializes a Hyperdrive pool.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _dataProvider The address of the data provider.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory
    )
        MultiToken(_dataProvider, _linkerCodeHash, _linkerFactory)
        HyperdriveStorage(_config)
    {
        // Initialize the oracle.
        for (uint256 i = 0; i < _config.oracleSize; ) {
            _buffer.push(OracleData(uint32(block.timestamp), 0));
            unchecked {
                ++i;
            }
        }
    }

    /// Yield Source ///

    /// @notice A YieldSource dependent check that prevents ether from being
    ///         transferred to Hyperdrive instances that don't accept ether.
    function _checkMessageValue() internal view virtual {
        if (msg.value != 0) {
            revert IHyperdrive.NotPayable();
        }
    }

    /// @notice Transfers base from the user and commits it to the yield source.
    /// @param _amount The amount of base to deposit.
    /// @param _options The options that configure how the withdrawal is
    ///        settled. In particular, the currency used in the deposit is
    ///        specified here. Aside from those options, yield sources can
    ///        choose to implement additional options.
    /// @return sharesMinted The shares created by this deposit.
    /// @return sharePrice The share price.
    function _deposit(
        uint256 _amount,
        IHyperdrive.Options memory _options
    ) internal virtual returns (uint256 sharesMinted, uint256 sharePrice);

    /// @notice Withdraws shares from the yield source and sends the base
    ///         released to the destination.
    /// @param _shares The shares to withdraw from the yield source.
    /// @param _options The options that configure how the withdrawal is
    ///        settled. In particular, the destination and currency used in the
    ///        withdrawal are specified here. Aside from those options, yield
    ///        sources can choose to implement additional options.
    /// @return amountWithdrawn The amount of base released by the withdrawal.
    function _withdraw(
        uint256 _shares,
        IHyperdrive.Options memory _options
    ) internal virtual returns (uint256 amountWithdrawn);

    /// @notice Loads the share price from the yield source.
    /// @return sharePrice The current share price.
    function _pricePerShare()
        internal
        view
        virtual
        returns (uint256 sharePrice);

    /// Pause ///

    event PauserUpdated(address indexed newPauser);

    /// @notice Allows governance to change the pauser status of an address.
    /// @param who The address to change.
    /// @param status The new pauser status.
    function setPauser(address who, bool status) external {
        if (msg.sender != _governance) revert IHyperdrive.Unauthorized();
        _pausers[who] = status;
        emit PauserUpdated(who);
    }

    event GovernanceUpdated(address indexed newGovernance);

    /// @notice Allows governance to change governance.
    /// @param _who The new governance address.
    function setGovernance(address _who) external {
        if (msg.sender != _governance) revert IHyperdrive.Unauthorized();
        _governance = _who;

        emit GovernanceUpdated(_who);
    }

    /// @notice Allows an authorized address to pause this contract.
    /// @param _status True to pause all deposits and false to unpause them.
    function pause(bool _status) external {
        if (!_pausers[msg.sender]) revert IHyperdrive.Unauthorized();
        _marketState.isPaused = _status;
    }

    /// @notice Blocks a function execution if the contract is paused.
    modifier isNotPaused() {
        if (_marketState.isPaused) revert IHyperdrive.Paused();
        _;
    }

    /// Checkpoint ///

    /// @dev Creates a new checkpoint if necessary.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @param _sharePrice The current share price.
    /// @return openSharePrice The open share price of the latest checkpoint.
    function _applyCheckpoint(
        uint256 _checkpointTime,
        uint256 _sharePrice
    ) internal virtual returns (uint256 openSharePrice);

    /// @notice This function collects the governance fees accrued by the pool.
    /// @param _options The options that configure how the fees are settled.
    /// @return proceeds The amount of base collected.
    function collectGovernanceFee(
        IHyperdrive.Options memory _options
    ) external nonReentrant returns (uint256 proceeds) {
        // The destination option isn't used in this function, and we require
        // that it is set to the zero address to prevent accidental use.
        if (_options.destination != address(0)) {
            revert IHyperdrive.InvalidOptions();
        }
        _options.destination = _feeCollector;

        // Must have been granted a role
        if (
            !_pausers[msg.sender] &&
            msg.sender != _feeCollector &&
            msg.sender != _governance
        ) revert IHyperdrive.Unauthorized();
        uint256 governanceFeesAccrued = _governanceFeesAccrued;
        delete _governanceFeesAccrued;
        proceeds = _withdraw(governanceFeesAccrued, _options);
    }

    /// Helpers ///

    /// @dev Calculates the checkpoint exposure when a position is closed
    /// @param _bondAmount The amount of bonds that the user is closing.
    /// @param _shareReservesDelta The amount of shares that the reserves will change by.
    /// @param _bondReservesDelta The amount of bonds that the reserves will change by.
    /// @param _shareUserDelta The amount of shares that the user will receive (long) or pay (short).
    /// @param _maturityTime The maturity time of the position being closed.
    /// @param _sharePrice The current share price.
    /// @param _isLong True if the position being closed is long.
    function _updateCheckpointLongExposureOnClose(
        uint256 _bondAmount,
        uint256 _shareReservesDelta,
        uint256 _bondReservesDelta,
        uint256 _shareUserDelta,
        uint256 _maturityTime,
        uint256 _sharePrice,
        bool _isLong
    ) internal {
        uint256 checkpointTime = _maturityTime - _positionDuration;
        uint256 checkpointLongs = _totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _maturityTime)
        ];
        uint256 checkpointShorts = _totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _maturityTime)
        ];

        // We can zero out long exposure when there are no more open positions
        if (checkpointLongs == 0 && checkpointShorts == 0) {
            _checkpoints[checkpointTime].longExposure = 0;
        } else {
            // The long exposure delta is flat + curve amount + the bonds the user is closing:
            // (dz_user*c - dz*c) + (dy - dz*c) + dy_user
            // = dz_user*c + dy - 2*dz*c + dy_user
            int128 delta = int128(
                (_shareUserDelta.mulDown(_sharePrice) +
                    _bondReservesDelta -
                    2 *
                    _shareReservesDelta.mulDown(_sharePrice) +
                    _bondAmount).toUint128()
            );

            // If the position being closed is long, then the long exposure decreases
            // by the delta. If it's short, then the long exposure increases by the delta.
            if (_isLong) {
                _checkpoints[checkpointTime].longExposure -= delta;
            } else {
                _checkpoints[checkpointTime].longExposure += delta;
            }
        }
    }

    /// @dev Updates the global long exposure.
    /// @param _before The long exposure before the update.
    /// @param _after The long exposure after the update.
    function _updateLongExposure(int256 _before, int256 _after) internal {
        // LongExposure is decreasing (OpenShort/CloseLong)
        if (_before > _after && _before >= 0) {
            int256 delta = int256(_before - _after.max(0));
            // Since the longExposure can't be negative, we need to make sure we don't underflow
            _marketState.longExposure -= uint128(
                delta.min(int128(_marketState.longExposure)).toInt128()
            );
        }
        // LongExposure is increasing (OpenLong/CloseShort)
        else if (_after > _before) {
            if (_before >= 0) {
                _marketState.longExposure += uint128(
                    _after.toInt128() - _before.toInt128()
                );
            } else {
                _marketState.longExposure += uint128(_after.max(0).toInt128());
            }
        }
    }

    /// @dev Calculates the number of share reserves that are not reserved by open positions
    /// @param _sharePrice The current share price.
    function _calculateIdleShareReserves(
        uint256 _sharePrice
    ) internal view returns (uint256 idleShares) {
        uint256 longExposure = uint256(_marketState.longExposure).divDown(
            _sharePrice
        );
        if (_marketState.shareReserves > longExposure + _minimumShareReserves) {
            idleShares =
                _marketState.shareReserves -
                longExposure -
                _minimumShareReserves;
        }
        return idleShares;
    }

    /// @dev Check solvency by verifying that the share reserves are greater than the exposure plus the minimum share reserves.
    /// @param _sharePrice The current share price.
    /// @return True if the share reserves are greater than the exposure plus the minimum share reserves.
    function _isSolvent(uint256 _sharePrice) internal view returns (bool) {
        return
            (int256(
                (uint256(_marketState.shareReserves).mulDown(_sharePrice))
            ) - int128(_marketState.longExposure)).max(0) >=
            int256(_minimumShareReserves.mulDown(_sharePrice));
    }

    /// @dev Calculates the fees that go to the LPs and governance.
    /// @param _amountIn Amount in shares.
    /// @param _spotPrice The price without slippage of bonds in terms of base (base/bonds).
    /// @param _sharePrice The current price of shares in terms of base (base/shares).
    /// @return totalCurveFee The total curve fee. The fee is in terms of bonds.
    /// @return governanceCurveFee The curve fee that goes to governance. The fee is in terms of bonds.
    function _calculateFeesOutGivenSharesIn(
        uint256 _amountIn,
        uint256 _spotPrice,
        uint256 _sharePrice
    )
        internal
        view
        returns (uint256 totalCurveFee, uint256 governanceCurveFee)
    {
        // Fixed Rate (r) = (value at maturity - purchase price)/(purchase price)
        //                = (1-p)/p
        //                = ((1 / p) - 1)
        //                = the return on investment at maturity of a bond purchased at price p
        //
        // Another way to think about it:
        // p (spot price) tells us how many base a bond is worth -> p = base/bonds
        // 1/p tells us how many bonds a base is worth -> 1/p = bonds/base
        // 1/p - 1 tells us how many additional bonds we get for each base -> (1/p - 1) = additional bonds/base
        // the curve fee is taken from the additional bonds the user gets for each base
        // total curve fee = ((1 / p) - 1) * phi_curve * c * dz
        //                 = r * phi_curve * base/shares * shares
        //                 = bonds/base * phi_curve * base
        //                 = bonds * phi_curve
        totalCurveFee = (FixedPointMath.ONE_18.divDown(_spotPrice) -
            FixedPointMath.ONE_18)
            .mulDown(_curveFee)
            .mulDown(_sharePrice)
            .mulDown(_amountIn);

        // We leave the governance fee in terms of bonds:
        // governanceCurveFee = total_curve_fee * p * phi_gov
        //                    = bonds * phi_gov
        governanceCurveFee = totalCurveFee.mulDown(_governanceFee);
    }

    /// @dev Calculates the fees that go to the LPs and governance.
    /// @param _amountIn Amount in terms of bonds.
    /// @param _normalizedTimeRemaining The normalized amount of time until maturity.
    /// @param _spotPrice The price without slippage of bonds in terms of base (base/bonds).
    /// @param _sharePrice The current price of shares in terms of base (base/shares).
    /// @return totalCurveFee The curve fee. The fee is in terms of shares.
    /// @return totalFlatFee The flat fee. The fee is in terms of shares.
    /// @return totalGovernanceFee The total fee that goes to governance. The fee is in terms of shares.
    function _calculateFeesOutGivenBondsIn(
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _sharePrice
    )
        internal
        view
        returns (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 totalGovernanceFee
        )
    {
        // p (spot price) tells us how many base a bond is worth -> p = base/bonds
        // 1 - p tells us how many additional base a bond is worth at maturity -> (1 - p) = additional base/bonds

        // The curve fee is taken from the additional base the user gets for each bond at maturity
        // total curve fee = ((1 - p) * phi_curve * d_y * t)/c
        //                 = (base/bonds * phi_curve * bonds * t) / (base/shares)
        //                 = (base/bonds * phi_curve * bonds * t) * (shares/base)
        //                 = (base * phi_curve * t) * (shares/base)
        //                 = phi_curve * t * shares
        uint256 _pricePart = FixedPointMath.ONE_18 - _spotPrice;
        totalCurveFee = _pricePart
            .mulDown(_curveFee)
            .mulDown(_amountIn)
            .mulDivDown(_normalizedTimeRemaining, _sharePrice);

        // Calculate the curve portion of the governance fee
        // governanceCurveFee = total_curve_fee * phi_gov
        //                    = shares * phi_gov
        totalGovernanceFee = totalCurveFee.mulDown(_governanceFee);

        // The flat portion of the fee is taken from the matured bonds.
        // Since a matured bond is worth 1 base, it is appropriate to consider
        // d_y in units of base.
        // flat fee = (d_y * (1 - t) * phi_flat) / c
        //          = (base * (1 - t) * phi_flat) / (base/shares)
        //          = (base * (1 - t) * phi_flat) * (shares/base)
        //          = shares * (1 - t) * phi_flat
        uint256 flat = _amountIn.mulDivDown(
            FixedPointMath.ONE_18 - _normalizedTimeRemaining,
            _sharePrice
        );
        totalFlatFee = flat.mulDown(_flatFee);

        // Calculate the flat portion of the governance fee
        // governanceFlatFee = total_flat_fee * phi_gov
        //                   = shares * phi_gov
        //
        // The totalGovernanceFee is the sum of the curve and flat governance fees
        // totalGovernanceFee = governanceCurveFee + governanceFlatFee
        totalGovernanceFee += totalFlatFee.mulDown(_governanceFee);
    }

    /// @dev Calculates the fees that go to the LPs and governance.
    /// @param _amountOut Amount in terms of bonds.
    /// @param _normalizedTimeRemaining The normalized amount of time until maturity.
    /// @param _spotPrice The price without slippage of bonds in terms of base (base/bonds).
    /// @param _sharePrice The current price of shares in terms of base (base/shares).
    /// @return totalCurveFee The total curve fee. Fee is in terms of shares.
    /// @return totalFlatFee The total flat fee.  Fee is in terms of shares.
    /// @return governanceCurveFee The curve fee that goes to governance.  Fee is in terms of shares.
    /// @return governanceFlatFee The flat fee that goes to governance.  Fee is in terms of shares.
    function _calculateFeesInGivenBondsOut(
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _sharePrice
    )
        internal
        view
        returns (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 governanceCurveFee,
            uint256 governanceFlatFee
        )
    {
        // p (spot price) tells us how many base a bond is worth -> p = base/bonds
        // 1 - p tells us how many additional base a bond is worth at maturity -> (1 - p) = additional base/bonds

        // The curve fee is taken from the additional base the user gets for each bond at maturity
        // total curve fee = ((1 - p) * phi_curve * d_y * t)/c
        //                 = (base/bonds * phi_curve * bonds * t) / (base/shares)
        //                 = (base/bonds * phi_curve * bonds * t) * (shares/base)
        //                 = (base * phi_curve * t) * (shares/base)
        //                 = phi_curve * t * shares
        totalCurveFee = FixedPointMath.ONE_18 - _spotPrice;
        totalCurveFee = totalCurveFee
            .mulDown(_curveFee)
            .mulDown(_amountOut)
            .mulDivDown(_normalizedTimeRemaining, _sharePrice);

        // Calculate the curve portion of the governance fee
        // governanceCurveFee = total_curve_fee * phi_gov
        //                    = shares * phi_gov
        governanceCurveFee = totalCurveFee.mulDown(_governanceFee);

        // The flat portion of the fee is taken from the matured bonds.
        // Since a matured bond is worth 1 base, it is appropriate to consider
        // d_y in units of base.
        // flat fee = (d_y * (1 - t) * phi_flat) / c
        //          = (base * (1 - t) * phi_flat) / (base/shares)
        //          = (base * (1 - t) * phi_flat) * (shares/base)
        //          = shares * (1 - t) * phi_flat
        uint256 flat = _amountOut.mulDivDown(
            FixedPointMath.ONE_18 - _normalizedTimeRemaining,
            _sharePrice
        );
        totalFlatFee = flat.mulDown(_flatFee);

        // Calculate the flat portion of the governance fee
        // governanceFlatFee = total_flat_fee * phi_gov
        //                   = shares * phi_gov
        governanceFlatFee = totalFlatFee.mulDown(_governanceFee);
    }
}
