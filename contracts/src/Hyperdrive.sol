// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";
import { HyperdriveLong } from "./HyperdriveLong.sol";
import { HyperdriveShort } from "./HyperdriveShort.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { IHyperdriveWrite } from "./interfaces/IHyperdriveWrite.sol";
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
    IHyperdriveWrite,
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
    function checkpoint(uint256 _checkpointTime) public {
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
        // their side of the trade. Closing out shorts first helps with netting
        // by ensuring the LP funds that were netted with longs are back in the
        // shareReserves before we close out the longs.
        uint256 openSharePrice = _checkpoints[
            _checkpointTime - _positionDuration
        ].sharePrice;
        uint256 maturedShortsAmount = _totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _checkpointTime)
        ];
        bool positionsClosed;
        if (maturedShortsAmount > 0) {
            (
                uint256 shareProceeds,
                uint256 governanceFee
            ) = _calculateMaturedProceeds(
                    maturedShortsAmount,
                    _sharePrice,
                    openSharePrice,
                    false
                );
            _governanceFeesAccrued += governanceFee;
            _applyCloseShort(
                maturedShortsAmount,
                0,
                shareProceeds,
                int256(shareProceeds), // keep the effective share reserves constant
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
            (
                uint256 shareProceeds,
                uint256 governanceFee
            ) = _calculateMaturedProceeds(
                    maturedLongsAmount,
                    _sharePrice,
                    openSharePrice,
                    true
                );
            _governanceFeesAccrued += governanceFee;
            _applyCloseLong(
                maturedLongsAmount,
                0,
                shareProceeds,
                int256(shareProceeds), // keep the effective share reserves constant
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

    /// @dev Calculates the proceeds of the long holders of a given position at
    ///      maturity. The long holders will be the LPs if the position is a
    ///      short.
    /// @param _bondAmount The bond amount of the position.
    /// @param _sharePrice The current share price.
    /// @param _openSharePrice The share price at the beginning of the
    ///        position's checkpoint.
    /// @param _isLong A flag indicating whether or not the position is a long.
    /// @return shareProceeds The proceeds of the long holders in shares.
    /// @return governanceFee The fee paid to governance in shares.
    function _calculateMaturedProceeds(
        uint256 _bondAmount,
        uint256 _sharePrice,
        uint256 _openSharePrice,
        bool _isLong
    ) internal view returns (uint256 shareProceeds, uint256 governanceFee) {
        // Calculate the share proceeds, flat fee, and governance fee. Since the
        // position is closed at maturity, the share proceeds are equal to the
        // bond amount divided by the share price.
        shareProceeds = _bondAmount.divDown(_sharePrice);
        uint256 flatFee = shareProceeds.mulDown(_flatFee);
        governanceFee = flatFee.mulDown(_governanceFee);

        // If the position is a long, the share proceeds are removed from the
        // share reserves. The proceeds are decreased by the flat fee because
        // the trader pays the flat fee. Most of the flat fee is paid to the
        // reserves; however, a portion of the flat fee is paid to governance.
        // With this in mind, we also increase the share proceeds by the
        // governance fee.
        if (_isLong) {
            shareProceeds -= flatFee - governanceFee;
        }
        // If the position is a short, the share proceeds are added to the share
        // reserves. The proceeds are increased by the flat fee because the pool
        // receives the flat fee. Most of the flat fee is paid to the reserves;
        // however, a portion of the flat fee is paid to governance. With this
        // in mind, we also decrease the share proceeds by the governance fee.
        else {
            shareProceeds += flatFee - governanceFee;
        }

        // If negative interest accrued over the period, the proceeds and
        // governance fee are given a "haircut" proportional to the negative
        // interest that accrued.
        if (_sharePrice < _openSharePrice) {
            shareProceeds = shareProceeds.mulDivDown(
                _sharePrice,
                _openSharePrice
            );
            governanceFee = governanceFee.mulDivDown(
                _sharePrice,
                _openSharePrice
            );
        }
    }
}
