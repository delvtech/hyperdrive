// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC20 } from "../../interfaces/IERC20.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IRestakeManager } from "../../interfaces/IRestakeManager.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { FixedPointMath, ONE } from "../../libraries/FixedPointMath.sol";

/// @author DELV
/// @title esETH Base Contract
/// @notice The base contract for the ezETH Hyperdrive implementation.
/// @dev
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract EzETHBase is HyperdriveBase {
    using FixedPointMath for uint256;

    /// @dev The Renzo entrypoint contract.
    IRestakeManager internal immutable _restakeManager;

    /// @dev The ezETH token contract.
    IERC20 internal immutable _ezETH;

    /// @notice Instantiates the ezETH Hyperdrive base contract.
    /// @param __restakeManager The Renzo Restakemanager contract.
    constructor(IRestakeManager __restakeManager) {
        _restakeManager = __restakeManager;
        _ezETH = _restakeManager.ezETH;
    }

    /// Yield Source ///

    /// @dev Accepts a transfer from the user in base token.
    /// @param _baseAmount The base amount to deposit.
    /// @return sharesMinted The shares that were minted in the deposit.
    /// @return refund The amount of ETH to refund. This should be zero for
    ///         yield sources that don't accept ETH.
    function _depositWithBase(
        uint256 _baseAmount,
        bytes calldata
    ) internal override returns (uint256 sharesMinted, uint256 refund) {
        // Ensure that sufficient ether was provided.
        if (msg.value < _baseAmount) {
            revert IHyperdrive.TransferFailed();
        }

        // If the user sent more ether than the amount specified, refund the
        // excess ether.
        unchecked {
            refund = msg.value - _baseAmount;
        }

        uint256 balanceBefore = _ezETH.balanceOf(address(this));
        // Submit the provided ether to Renzo to be deposited.
        // a referrer id can be put in here
        _restakeManager.depositETH{ value: _baseAmount }();
        uint256 balanceAfter = _ezETH.balanceOf(address(this));
        sharesMinted = balanceAfter - balanceBefore;

        return (sharesMinted, refund);
    }

    /// @dev Process a deposit in vault shares.
    /// @param _shareAmount The vault shares amount to deposit.
    function _depositWithShares(
        uint256 _shareAmount,
        bytes calldata // unused
    ) internal override {
        // Transfer ezETH shares into the contract.
        _ezETH.transferFrom(msg.sender, address(this), _shareAmount);
    }

    /// @dev Process a withdrawal in base and send the proceeds to the
    ///      destination.
    function _withdrawWithBase(
        uint256, // unused
        address, // unused
        bytes calldata // unused
    ) internal pure override returns (uint256) {
        // ezETH withdrawals aren't necessarily instantaneous. Users that want
        // to withdraw can manage their withdrawal separately.
        revert IHyperdrive.UnsupportedToken();
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
        // Transfer the stETH shares to the destination.
        _ezETH.transfer(_destination, _shareAmount);
    }

    /// @dev Returns the current vault share price.
    /// @return price The current vault share price.
    function _pricePerVaultShare()
        internal
        view
        override
        returns (uint256 price)
    {
        (, , uint256 totalTVL) = _restakeManager.calculateTVLS();
        uint256 ezETHSupply = _ezETH.totalSupply();

        // Price in ETH / ezETH, does not include eigenlayer points.
        return totalTVL.mulDown(ezETHSupply);
    }

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return baseAmount The base amount.
    function _convertToBase(
        uint256 _shareAmount
    ) internal view override returns (uint256) {
        return _shareAmount.mulDown(_pricePerVaultShare());
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return shareAmount The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal view override returns (uint256) {
        return _baseAmount.divDown(_pricePerVaultShare());
    }

    /// @dev Gets the total amount of base held by the pool.
    /// @return baseAmount The total amount of base.
    function _totalBase() internal pure override returns (uint256) {
        // NOTE: Since ETH is the base token and can't be swept, we can safely
        // return zero.
        return 0;
    }

    /// @dev We override the message value check since this integration is
    ///      payable.
    function _checkMessageValue() internal pure override {}
}
