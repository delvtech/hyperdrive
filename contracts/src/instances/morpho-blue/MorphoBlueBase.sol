// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IMorpho, MarketParams } from "morpho-blue/src/interfaces/IMorpho.sol";
import { MarketParamsLib } from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { SharesMathLib } from "morpho-blue/src/libraries/SharesMathLib.sol";
import { MorphoBalancesLib } from "morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IMorphoBlueHyperdrive } from "../../interfaces/IMorphoBlueHyperdrive.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";

/// @author DELV
/// @title MorphoBlueBase
/// @notice The base contract for the MorphoBlue Hyperdrive implementation.
/// @dev This Hyperdrive implementation is designed to work with standard
///      MorphoBlue vaults. Non-standard implementations may not work correctly
///      and should be carefully checked.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract MorphoBlueBase is HyperdriveBase {
    using SafeERC20 for ERC20;
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;
    using SharesMathLib for uint256;

    // FIXME: Make getters for each of these immutables.

    /// @dev The Morpho Blue contract.
    IMorpho internal immutable _vault;

    /// @dev The collateral token for this Morpho Blue market.
    address internal immutable _collateralToken;

    /// @dev The oracle for this Morpho Blue market.
    address internal immutable _oracle;

    /// @dev The IRM for this Morpho Blue market.
    address internal immutable _irm;

    /// @dev The LLTV for this Morpho Blue market.
    uint256 internal immutable _lltv;

    // FIXME: Check that the vault shares token zero.
    //
    /// @notice Instantiates the MorphoBlueHyperdrive base contract.
    /// @param _params The Morpho Blue params.
    constructor(IMorphoBlueHyperdrive.MorphoBlueParams memory _params) {
        // Initialize the Morpho vault immutable.
        _vault = _params.morpho;

        // Initialize the market parameters immutables. We don't need an
        // immutable for the loan token because we set the base token to the
        // loan token.
        _collateralToken = _params.collateralToken;
        _oracle = _params.oracle;
        _irm = _params.irm;
        _lltv = _params.lltv;

        // Approve the Morpho vault with 1 wei. This ensures that all of the
        // subsequent approvals will be writing to a dirty storage slot.
        ERC20(address(_baseToken)).forceApprove(address(_vault), 1);
    }

    /// Yield Source ///

    /// @dev Accepts a deposit from the user in base.
    /// @param _baseAmount The base amount to deposit.
    /// @param _extraData Additional data to pass to the Morpho vault. This
    ///        should be zero if it is unused.
    /// @return The shares that were minted in the deposit.
    /// @return The amount of ETH to refund. Since this yield source isn't
    ///         payable, this is always zero.
    function _depositWithBase(
        uint256 _baseAmount,
        bytes calldata _extraData
    ) internal override returns (uint256, uint256) {
        // Take custody of the deposit in base.
        ERC20(address(_baseToken)).safeTransferFrom(
            msg.sender,
            address(this),
            _baseAmount
        );

        // Deposit the base into the yield source.
        //
        // NOTE: We increase the required approval amount by 1 wei so that
        // the vault ends with an approval of 1 wei. This makes future
        // approvals cheaper by keeping the storage slot warm.
        ERC20(address(_baseToken)).forceApprove(
            address(_vault),
            _baseAmount + 1
        );
        (, uint256 sharesMinted) = _vault.supply(
            MarketParams({
                loanToken: address(_baseToken),
                collateralToken: _collateralToken,
                oracle: _oracle,
                irm: _irm,
                lltv: _lltv
            }),
            _baseAmount,
            0,
            address(this),
            _extraData
        );

        return (sharesMinted, 0);
    }

    /// @dev Deposits with shares are not supported for this integration.
    function _depositWithShares(
        uint256, // unused _shareAmount
        bytes calldata // unused _extraData
    ) internal pure override {
        revert IHyperdrive.UnsupportedToken();
    }

    /// @dev Process a withdrawal in base and send the proceeds to the
    ///      destination.
    /// @param _shareAmount The amount of vault shares to withdraw.
    /// @param _destination The destination of the withdrawal.
    /// @return amountWithdrawn The amount of base withdrawn.
    function _withdrawWithBase(
        uint256 _shareAmount,
        address _destination,
        bytes calldata // unused
    ) internal override returns (uint256 amountWithdrawn) {
        (amountWithdrawn, ) = _vault.withdraw(
            MarketParams({
                loanToken: address(_baseToken),
                collateralToken: _collateralToken,
                oracle: _oracle,
                irm: _irm,
                lltv: _lltv
            }),
            0,
            _shareAmount,
            address(this),
            _destination
        );

        return amountWithdrawn;
    }

    /// @dev Withdrawals with shares are not supported for this integration.
    function _withdrawWithShares(
        uint256, // unused _shareAmount
        address, // unused _destination
        bytes calldata // unused
    ) internal pure override {
        revert IHyperdrive.UnsupportedToken();
    }

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function _convertToBase(
        uint256 _shareAmount
    ) internal view override returns (uint256) {
        // Get the total supply assets and shares after interest accrues.
        (uint256 totalSupplyAssets, uint256 totalSupplyShares, , ) = _vault
            .expectedMarketBalances(
                MarketParams({
                    loanToken: address(_baseToken),
                    collateralToken: _collateralToken,
                    oracle: _oracle,
                    irm: _irm,
                    lltv: _lltv
                })
            );

        return _shareAmount.toAssetsDown(totalSupplyAssets, totalSupplyShares);
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal view override returns (uint256) {
        // Get the total supply assets and shares after interest accrues.
        (uint256 totalSupplyAssets, uint256 totalSupplyShares, , ) = _vault
            .expectedMarketBalances(
                MarketParams({
                    loanToken: address(_baseToken),
                    collateralToken: _collateralToken,
                    oracle: _oracle,
                    irm: _irm,
                    lltv: _lltv
                })
            );

        return _baseAmount.toSharesDown(totalSupplyAssets, totalSupplyShares);
    }

    /// @dev Gets the total amount of shares held by the pool in the yield
    ///      source.
    /// @return shareAmount The total amount of shares.
    function _totalShares()
        internal
        view
        override
        returns (uint256 shareAmount)
    {
        return
            _vault
                .position(
                    MarketParams({
                        loanToken: address(_baseToken),
                        collateralToken: _collateralToken,
                        oracle: _oracle,
                        irm: _irm,
                        lltv: _lltv
                    }).id(),
                    address(this)
                )
                .supplyShares;
    }

    /// @dev We override the message value check since this integration is
    ///      not payable.
    function _checkMessageValue() internal view override {
        if (msg.value != 0) {
            revert IHyperdrive.NotPayable();
        }
    }
}
