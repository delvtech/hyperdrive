// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";
import { HyperdriveLong } from "./HyperdriveLong.sol";
import { HyperdriveShort } from "./HyperdriveShort.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import { SafeCast } from "./libraries/SafeCast.sol";

/// @author DELV
/// @title Hyperdrive
/// @notice A fixed-rate AMM that mints bonds on demand for longs and shorts.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract Hyperdrive is
    HyperdriveBase,
    HyperdriveLong,
    HyperdriveShort
{
    using FixedPointMath for uint256;
    using SafeCast for uint256;

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
    ) HyperdriveBase(_config, _dataProvider, _linkerCodeHash, _linkerFactory) {} // solhint-disable-line no-empty-blocks

    /// @notice Allows anyone to mint a new checkpoint.
    /// @param _checkpointTime The time of the checkpoint to create.
    function checkpoint(uint256 _checkpointTime) public override {
        // If the checkpoint has already been set, return early.
        if (_checkpoints[_checkpointTime].sharePrice != 0) {
            return;
        }

        // If the checkpoint time isn't divisible by the checkpoint duration
        // or is in the future, it's an invalid checkpoint and we should
        // revert.
        uint256 latestCheckpoint = _latestCheckpoint();
        if (
            _checkpointTime % _checkpointDuration != 0 ||
            latestCheckpoint < _checkpointTime
        ) {
            revert IHyperdrive.InvalidCheckpointTime();
        }

        // If the checkpoint time is the latest checkpoint, we use the current
        // share price. Otherwise, we use a linear search to find the closest
        // share price and use that to perform the checkpoint.
        if (_checkpointTime == latestCheckpoint) {
            _applyCheckpoint(latestCheckpoint, _pricePerShare());
        } else {
            for (
                uint256 time = _checkpointTime;
                ;
                time += _checkpointDuration
            ) {
                uint256 closestSharePrice = _checkpoints[time].sharePrice;
                if (time == latestCheckpoint) {
                    closestSharePrice = _pricePerShare();
                }
                if (closestSharePrice != 0) {
                    _applyCheckpoint(_checkpointTime, closestSharePrice);
                    break;
                }
            }
        }
    }

    /// @dev Creates a new checkpoint if necessary.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @param _sharePrice The current share price.
    /// @return The opening share price of the latest checkpoint.
    function _applyCheckpoint(
        uint256 _checkpointTime,
        uint256 _sharePrice
    ) internal override returns (uint256) {
        // Return early if the checkpoint has already been updated.
        IHyperdrive.Checkpoint storage checkpoint_ = _checkpoints[
            _checkpointTime
        ];
        if (checkpoint_.sharePrice != 0 || _checkpointTime > block.timestamp) {
            return checkpoint_.sharePrice;
        }

        // Create the share price checkpoint.
        checkpoint_.sharePrice = _sharePrice.toUint128();

        // Close out all of the short positions that matured at the beginning of
        // this checkpoint. This ensures that shorts don't continue to collect
        // free variable interest and that LP's can withdraw the proceeds of
        // their side of the trade.
        uint256 openSharePrice = _checkpoints[
            _checkpointTime - _positionDuration
        ].sharePrice;
        uint256 maturedShortsAmount = _totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _checkpointTime)
        ];
        bool positionsClosed;
        if (maturedShortsAmount > 0) {
            // FIXME: DRY up this accounting.
            //
            // When a short matures, the LPs receives base equal to the bond
            // amount minus the flat fee. Most of the flat fee is paid to the
            // reserves; however, a portion of the flat fee is paid to
            // governance. If negative interest accrued over the period, the
            // LPs take a proportional "haircut" to their proceeds. With this in
            // mind, the share reserves should increase by the amount of newly
            // matured longs divided by the share price, plus the flat fee, and
            // minus the governance fee (since this doesn't go to the reserves).
            // If negative interest accrues, we discount the share proceeds by
            // the negative interest that accrued.
            uint256 shareProceeds = maturedShortsAmount.divDown(_sharePrice);
            uint256 flatFee = shareProceeds.mulDown(_flatFee);
            uint256 govFee = flatFee.mulDown(_governanceFee);
            shareProceeds += flatFee - govFee;
            if (_sharePrice < openSharePrice) {
                // FIXME: We may be scaling in the wrong place. Should fees be
                // scaled like this? We should do the same thing here that we
                // do elsewhere.
                shareProceeds = shareProceeds.mulDivDown(
                    _sharePrice,
                    openSharePrice
                );
            }

            // Update the governance fees accrued in terms of shares.
            _governanceFeesAccrued += govFee;

            // Closing out shorts first helps with netting by ensuring the LP
            // funds that were netted with longs are back in the shareReserves
            // before we close out the longs.
            _applyCloseShort(
                maturedShortsAmount,
                0,
                shareProceeds,
                0,
                _checkpointTime
            );
            positionsClosed = true;
        }

        // Close out all of the long positions that matured at the beginning of
        // this checkpoint.
        uint256 maturedLongsAmount = _totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _checkpointTime)
        ];
        if (maturedLongsAmount > 0) {
            // FIXME: DRY up this accounting.
            //
            // When a long matures, the long holder receives base equal to the
            // bond amount minus the flat fee. Most of the flat fee is paid to
            // the reserves; however, a portion of the flat fee is paid to
            // governance. If negative interest accrued over the period, the
            // long holder takes a proportional "haircut" to their proceeds.
            // With this in mind, the share reserves should decrease by the
            // amount of newly matured longs divided by the share price, minus
            // the flat fee, and plus the governance fee (since this doesn't go
            // to the reserves). If negative interest accrues, we discount the
            // share proceeds by the negative interest that accrued.
            uint256 shareProceeds = maturedLongsAmount.divDown(_sharePrice);
            uint256 flatFee = shareProceeds.mulDown(_flatFee);
            uint256 govFee = flatFee.mulDown(_governanceFee);
            shareProceeds -= flatFee - govFee;
            if (_sharePrice < openSharePrice) {
                // FIXME: We may be scaling in the wrong place. Should fees be
                // scaled like this? We should do the same thing here that we
                // do elsewhere.
                shareProceeds = shareProceeds.mulDivDown(
                    _sharePrice,
                    openSharePrice
                );
            }

            // Update the governance fees accrued in terms of shares.
            _governanceFeesAccrued += govFee;

            // Close out the longs.
            _applyCloseLong(
                maturedLongsAmount,
                0,
                shareProceeds,
                0,
                _checkpointTime
            );
            positionsClosed = true;
        }

        // Update the checkpoint and global longExposure
        if (positionsClosed) {
            uint256 maturityTime = _checkpointTime - _positionDuration;
            int128 checkpointExposureBefore = int128(
                _checkpoints[maturityTime].longExposure
            );
            _checkpoints[maturityTime].longExposure = 0;
            _updateLongExposure(
                checkpointExposureBefore,
                _checkpoints[maturityTime].longExposure
            );

            // Distribute the excess idle to the withdrawal pool.
            _distributeExcessIdle(_sharePrice);
        }

        return _sharePrice;
    }
}
