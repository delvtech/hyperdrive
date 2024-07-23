// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IChainlinkAggregatorV3 } from "../../interfaces/IChainlinkAggregatorV3.sol";
import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";

// FIXME: This is the highest risk integration that we've added so far. I want
//        this to be flexible enough for us to use it, but it will have more
//        footguns than other integrations and will be more dangerous if it's
//        used incorrectly.
//
// FIXME: What is the best way to handle uptime on L2s?
//
/// @author DELV
/// @title ChainlinkBase
/// @notice The base contract for the Chainlink Hyperdrive implementation.
/// FIXME: Update this disclaimer.
/// @dev This Hyperdrive implementation is designed to work with standard
///      Chainlink vaults. Non-standard implementations may not work correctly
///      and should be carefully checked.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract ChainlinkBase is HyperdriveBase {
    using SafeERC20 for ERC20;

    // FIXME: Do we need new immutables to handle L2 downtime?

    // FIXME: Add a getter for this.
    //
    // FIXME: Add Natspec.
    IChainlinkAggregatorV3 internal immutable aggregator;

    /// @notice Instantiates the ChainlinkHyperdrive base contract.
    /// @param _aggregator The Chainlink aggregator. This is the contract that
    ///        will return the answer.
    constructor(IChainlinkAggregatorV3 _aggregator) {
        aggregator = _aggregator;
    }

    /// Yield Source ///

    /// @dev Accepts a deposit from the user in base. This function fails since
    ///      base isn't a supported asset for this integration.
    /// @return The shares that were minted in the deposit.
    /// @return The amount of ETH to refund. Since this yield source isn't
    ///         payable, this is always zero.
    function _depositWithBase(
        uint256, // unused _baseAmount
        bytes calldata // unused _extraData
    ) internal pure override returns (uint256, uint256) {
        revert IHyperdrive.UnsupportedToken();
    }

    /// @dev Process a deposit in vault shares.
    /// @param _shareAmount The vault shares amount to deposit.
    function _depositWithShares(
        uint256 _shareAmount,
        bytes calldata // unused _extraData
    ) internal override {
        // Take custody of the deposit in vault shares.
        ERC20(address(_vaultSharesToken)).safeTransferFrom(
            msg.sender,
            address(this),
            _shareAmount
        );
    }

    /// @dev Process a withdrawal in base and send the proceeds to the
    ///      destination. This function fails since base isn't a supported asset
    ///      for this integration.
    /// @return amountWithdrawn The amount of base withdrawn.
    function _withdrawWithBase(
        uint256, // unused _shareAmount
        address, // unused _destination
        bytes calldata // unused _extraData
    ) internal pure override returns (uint256) {
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
        // Transfer vault shares to the destination.
        ERC20(address(_vaultSharesToken)).safeTransfer(
            _destination,
            _shareAmount
        );
    }

    // FIXME: We should use the standard conversions pattern.
    //
    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function _convertToBase(
        uint256 _shareAmount
    ) internal view override returns (uint256) {
        // ****************************************************************
        // FIXME: Implement this for new instances.
        return
            IERC4626(address(_vaultSharesToken)).convertToAssets(_shareAmount);
        // ****************************************************************
    }

    // FIXME: We should use the standard conversions pattern.
    //
    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal view override returns (uint256) {
        // ****************************************************************
        // FIXME: Implement this for new instances.
        return
            IERC4626(address(_vaultSharesToken)).convertToShares(_baseAmount);
        // ****************************************************************
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
        return _vaultSharesToken.balanceOf(address(this));
    }

    /// @dev We override the message value check since this integration is
    ///      not payable.
    function _checkMessageValue() internal view override {
        if (msg.value != 0) {
            revert IHyperdrive.NotPayable();
        }
    }
}
