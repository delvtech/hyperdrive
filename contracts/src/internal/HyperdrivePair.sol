// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveEvents } from "../interfaces/IHyperdriveEvents.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../libraries/HyperdriveMath.sol";
import { LPMath } from "../libraries/LPMath.sol";
import { SafeCast } from "../libraries/SafeCast.sol";
import { HyperdriveBase } from "./HyperdriveLP.sol";
import { HyperdriveMultiToken } from "./HyperdriveMultiToken.sol";

/// @author DELV
/// @title HyperdriveLong
/// @notice Implements the long accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdrivePair is
    IHyperdriveEvents,
    HyperdriveBase,
    HyperdriveMultiToken
{
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @dev Mints a pair of long and short positions that directly match each
    ///      other. The amount of long and short positions that are created is
    ///      equal to the base value of the deposit. These positions are sent to
    ///      the provided destinations.
    /// @param _amount The amount of capital provided to open the long. The
    ///        units of this quantity are either base or vault shares, depending
    ///        on the value of `_options.asBase`.
    /// @param _options The pair options that configure how the trade is settled.
    /// @return maturityTime The maturity time of the new long and short positions.
    /// @return bondAmount The bond amount of the new long and short positoins.
    function _mint(
        uint256 _amount,
        uint256 _minVaultSharePrice,
        IHyperdrive.PairOptions calldata _options
    )
        internal
        nonReentrant
        isNotPaused
        returns (uint256 maturityTime, uint256 bondAmount)
    {
        // Check that the message value is valid.
        _checkMessageValue();

        // Check that the provided options are valid.
        _checkPairOptions(_options);

        // Deposit the user's input amount.
        (uint256 sharesDeposited, uint256 vaultSharePrice) = _deposit(
            _amount,
            _options.asBase,
            _options.extraData
        );

        // Enforce the minimum vault share price.
        if (vaultSharePrice < _minVaultSharePrice) {
            revert IHyperdrive.MinimumSharePrice();
        }

        // Perform a checkpoint.
        uint256 latestCheckpoint = _latestCheckpoint();
        uint256 openVaultSharePrice = _applyCheckpoint(
            latestCheckpoint,
            vaultSharePrice,
            LPMath.SHARE_PROCEEDS_MAX_ITERATIONS,
            true
        );

        // Calculate the bond amount and governance fee from the shares
        // deposited.
        uint256 governanceFee;
        (bondAmount, governanceFee) = _calculateMint(
            sharesDeposited,
            vaultSharePrice,
            openVaultSharePrice
        );

        // Apply the state changes caused by creating the pair.
        maturityTime = latestCheckpoint + _positionDuration;
        _applyMint(maturityTime, bondAmount, governanceFee);

        // Mint bonds equal in value to the base deposited.
        uint256 longAssetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );
        uint256 shortAssetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Short,
            maturityTime
        );
        _mint(longAssetId, _options.longDestination, bondAmount);
        _mint(shortAssetId, _options.shortDestination, bondAmount);

        // Emit an Mint event.
        uint256 bondAmount_ = bondAmount; // avoid stack-too-deep
        uint256 amount = _amount; // avoid stack-too-deep
        IHyperdrive.PairOptions calldata options = _options; // avoid stack-too-deep
        emit Mint(
            options.longDestination,
            options.shortDestination,
            maturityTime,
            longAssetId,
            shortAssetId,
            amount,
            vaultSharePrice,
            options.asBase,
            bondAmount_,
            options.extraData
        );

        return (maturityTime, bondAmount);
    }

    // // FIXME: Add Natspec.
    // function _burn(
    //     uint256 _maturityTime,
    //     uint256 _bondAmount,
    //     IHyperdrive.Options calldata _options
    // )
    //     internal
    //     returns (uint256 maturityTime, uint256 longAmount, uint256 shortAmount)
    // {
    //     // FIXME: This function should take in a long and a short and send the
    //     //        underlying capital to the owner.

    //     // Check that the provided options are valid.
    //     _checkOptions(_options);

    //     // Ensure that the bond amount is greater than or equal to the minimum
    //     // transaction amount.
    //     if (_bondAmount < _minimumTransactionAmount) {
    //         revert IHyperdrive.MinimumTransactionAmount();
    //     }

    //     // If the short hasn't matured, we checkpoint the latest checkpoint.
    //     // Otherwise, we perform a checkpoint at the time the short matured.
    //     // This ensures the short and all of the other positions in the
    //     // checkpoint are closed.
    //     uint256 vaultSharePrice = _pricePerVaultShare();
    //     if (block.timestamp < _maturityTime) {
    //         _applyCheckpoint(
    //             _latestCheckpoint(),
    //             vaultSharePrice,
    //             LPMath.SHARE_PROCEEDS_MAX_ITERATIONS,
    //             true
    //         );
    //     } else {
    //         _applyCheckpoint(
    //             _maturityTime,
    //             vaultSharePrice,
    //             LPMath.SHARE_PROCEEDS_MAX_ITERATIONS,
    //             true
    //         );
    //     }

    //     // Burn the longs and shorts that are being closed.
    //     _burn(
    //         AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _maturityTime),
    //         msg.sender,
    //         _bondAmount
    //     );
    //     _burn(
    //         AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _maturityTime),
    //         msg.sender,
    //         _bondAmount
    //     );

    //     // FIXME: We need to do the following things to update the states:
    //     //
    //     // 1. [ ] Update the longs and shorts outstanding.
    //     // 2. [ ] Get the amount of base owed to the longs and shorts.
    //     // 3. [ ] Assess the governance fees.
    //     // 4. [ ] Withdraw the proceeds to the destination.
    // }

    /// @dev Applies state changes to create a pair of matched long and short
    ///      positions. This operation leaves the pool's solvency and idle
    ///      capital unchanged because the positions fully net out. Specifically:
    ///
    ///      - Share reserves, share adjustments, and bond reserves remain
    ///        constant since the provided capital backs the positions directly.
    ///      - Solvency remains constant because the net effect of matching long
    ///        and short positions is neutral.
    ///      - Idle capital is unaffected since no excess funds are added or
    ///        removed during this process.
    ///
    ///      Therefore:
    ///
    ///      - Solvency checks are unnecessary.
    ///      - Idle capital does not need to be redistributed to LPs.
    /// @param _maturityTime The maturity time of the pair of long and short
    ///        positions
    /// @param _bondAmount The amount of bonds created.
    /// @param _governanceFee The governance fee calculated from the bond amount.
    function _applyMint(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _governanceFee
    ) internal {
        // Update the amount of governance fees accrued. Since the long and
        // short both pay the governance fee, the governance fees accrued
        // increases by twice the governance fee.
        _governanceFeesAccrued += 2 * _governanceFee;

        // Update the average maturity time of longs and short positions and the
        // amount of long and short positions outstanding. Everything else
        // remains constant.
        _marketState.longAverageMaturityTime = uint256(
            _marketState.longAverageMaturityTime
        )
            .updateWeightedAverage(
                _marketState.longsOutstanding,
                _maturityTime * ONE, // scale up to fixed point scale
                _bondAmount,
                true
            )
            .toUint128();
        _marketState.shortAverageMaturityTime = uint256(
            _marketState.shortAverageMaturityTime
        )
            .updateWeightedAverage(
                _marketState.shortsOutstanding,
                _maturityTime * ONE, // scale up to fixed point scale
                _bondAmount,
                true
            )
            .toUint128();
        _marketState.longsOutstanding += _bondAmount.toUint128();
        _marketState.shortsOutstanding += _bondAmount.toUint128();
    }

    /// @dev Calculates the amount of bonds that can be minted and the governance
    ///      fee from the amount of vault shares that were deposited.
    /// @param _sharesDeposited The amount of vault shares that were deposited.
    /// @param _vaultSharePrice The vault share price.
    /// @param _openVaultSharePrice The vault share price at the beginning of
    ///        the checkpoint.
    function _calculateMint(
        uint256 _sharesDeposited,
        uint256 _vaultSharePrice,
        uint256 _openVaultSharePrice
    ) internal view returns (uint256, uint256) {
        // In order for a certain amount of bonds to be minted, there needs to
        // be enough base to pay the prepaid interest that has accrued since the
        // start of the checkpoint, to pay out the face value of the bond at
        // maturity, for the short to pay the flat fee at maturity, and for the
        // long and short to both pay the governance fee during the mint. We can
        // work back from this understanding to get the amount of bonds from the
        // amount of shares deposited.
        //
        // sharesDeposited * vaultSharePrice = (
        //    bondAmount + bondAmount * (c - c0) / c0 + bondAmount * flatFee +
        //    2 * bondAmount * flatFee * governanceFee
        // )
        //
        // This implies that
        //
        // bondAmount = shareDeposited * vaultSharePrice / (
        //     1 + (c - c0) / c0 + flatFee + 2 * flatFee * governanceFee
        // )
        //
        // NOTE: We round down to underestimate the bond amount.
        uint256 bondAmount = _sharesDeposited.mulDivDown(
            _vaultSharePrice,
            // NOTE: Round up to overestimate the denominator. This
            // underestimates the bond amount.
            (ONE +
                (_vaultSharePrice - _openVaultSharePrice).divUp(
                    _openVaultSharePrice
                ) +
                _flatFee +
                2 *
                _flatFee.mulUp(_governanceLPFee))
        );
        // FIXME: What should the rounding be here?
        uint256 governanceFee = bondAmount.mulDown(_flatFee).mulDown(
            _governanceLPFee
        );

        return (bondAmount, governanceFee);
    }
}
