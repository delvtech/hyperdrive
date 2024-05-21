// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { Id, IMorpho, Market, MarketParams, Position } from "../../interfaces/IMorpho.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { MorphoSharesMath } from "../../libraries/MorphoSharesMath.sol";
import { MorphoParamsLib } from "../../libraries/MorphoParamsLib.sol";

import "forge-std/console2.sol";

/// @author DELV
/// @title MorphoBase
/// @notice The base contract for the Morpho Hyperdrive implementation.
/// @dev This Hyperdrive implementation is designed to work with standard
///      Morpho vaults. Non-standard implementations may not work correctly
///      and should be carefully checked.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract MorphoBase is HyperdriveBase {
    using SafeERC20 for ERC20;
    using MorphoSharesMath for uint256;
    using MorphoParamsLib for MarketParams;

    IMorpho internal immutable _morpho;
    MarketParams internal _marketParams;

    /// @notice Instantiates the ezETH Hyperdrive base contract.
    /// @param __morpho The Morpho contract.
    /// @param __marketParams The Morpho market information.
    constructor(IMorpho __morpho, MarketParams memory __marketParams) {
        _morpho = __morpho;
        _marketParams = __marketParams;
    }

    /// Yield Source ///

    /// @dev Accepts a deposit from the user in base.
    /// @param _baseAmount The base amount to deposit.
    /// @return The shares that were minted in the deposit.
    /// @return The amount of ETH to refund. Since this yield source isn't
    ///         payable, this is always zero.
    function _depositWithBase(
        uint256 _baseAmount,
        bytes calldata // unused
    ) internal override returns (uint256, uint256) {
        // Take custody of the deposit in base.
        ERC20(address(_marketParams.loanToken)).safeTransferFrom(
            msg.sender,
            address(this),
            _baseAmount
        );

        ERC20(_marketParams.loanToken).forceApprove(
            address(_morpho),
            _baseAmount + 1
        );

        (, uint256 sharesSupplied) = _morpho.supply(
            _marketParams,
            _baseAmount,
            0,
            address(this),
            hex""
        );

        return (sharesSupplied, 0);
    }

    /// @dev Process a deposit in vault shares.
    /// @param _shareAmount The vault shares amount to deposit.
    function _depositWithShares(
        uint256 _shareAmount,
        bytes calldata // unused _extraData
    ) internal override {
        revert IHyperdrive.UnsupportedToken();

        // // Take custody of the deposit in base.
        // ERC20(address(_marketParams.loanToken)).safeTransferFrom(
        //     msg.sender,
        //     address(this),
        //     _baseAmount
        // );

        // ERC20(marketParams.loanToken).forceApprove(
        //     address(_morpho),
        //     _baseAmount + 1
        // );

        // (, uint256 sharesSupplied) = _morpho.supply(
        //     _marketParams,
        //     0,
        //     _shareAmount,
        //     msg.sender,
        //     hex""
        // );

        // return (sharesSupplied, 0);
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
    ) internal override returns (uint256) {
        (uint256 amountWithdrawn, ) = _morpho.withdraw(
            _marketParams,
            0,
            _shareAmount, // TODO _shareAmount is in 36 decimals
            address(this), // onBalf of hyperdrive
            msg.sender // credit to user
        );

        return amountWithdrawn;
    }

    /// @dev Process a withdrawal in vault shares and send the proceeds to the
    ///      destination.
    /// @param _shareAmount The amount of vault shares to withdraw.
    /// @param _destination The destination of the withdrawal.
    function _withdrawWithShares(
        uint256 _shareAmount,
        address _destination,
        bytes calldata // unused
    ) internal override {
        revert IHyperdrive.UnsupportedToken();
    }

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function _convertToBase(
        uint256 _shareAmount
    ) internal view override returns (uint256) {
        Id marketId = _marketParams.id();
        Market memory market = _morpho.market(marketId);

        return
            _shareAmount.toAssetsDown(
                market.totalSupplyAssets,
                market.totalSupplyShares
            );
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal view override returns (uint256) {
        Id marketId = _marketParams.id();
        Market memory market = _morpho.market(marketId);

        // rounding down for withdraws
        return
            _baseAmount.toSharesDown(
                market.totalSupplyAssets,
                market.totalSupplyShares
            );
    }

    /// @dev Gets the total amount of shares held by the pool in the yield
    ///      source.
    /// @return shareAmount The total amount of shares.
    function _totalShares() internal view override returns (uint256) {
        Id marketId = _marketParams.id();
        Market memory market = _morpho.market(marketId);

        Position memory position = _morpho.position(marketId, address(this));
        return position.supplyShares;
    }

    /// @dev We override the message value check since this integration is
    ///      not payable.
    function _checkMessageValue() internal view override {
        if (msg.value != 0) {
            revert IHyperdrive.NotPayable();
        }
    }
}
