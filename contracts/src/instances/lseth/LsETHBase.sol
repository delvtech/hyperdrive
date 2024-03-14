// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IRiverV1 } from "../../interfaces/lseth/IRiverV1.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { FixedPointMath, ONE } from "../../libraries/FixedPointMath.sol";

/// @author DELV
/// @title StethHyperdrive
/// @notice The base contract for the stETH Hyperdrive implementation.
/// @dev Lido has it's own notion of shares to account for the accrual of
///      interest on the ether pooled in the Lido protocol. Instead of
///      maintaining a balance of shares, this integration can simply use Lido
///      shares directly.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract LsETHBase is HyperdriveBase {
    using FixedPointMath for uint256;

    /// @dev The Lido contract.
    IRiverV1 internal immutable _river;

    /// @notice Instantiates the stETH Hyperdrive base contract.
    /// @param __river The Lido contract.
    constructor(IRiverV1 __river) {
        _river = __river;
    }

    /// Yield Source ///

    /// @dev Accepts a deposit from the user in base.
    /// @param _baseAmount The base amount to deposit.
    /// @return sharesMinted The shares that were minted in the deposit.
    /// @return refund The amount of ETH to refund. This should be zero for
    ///         yield sources that don't accept ETH.
    function _depositWithBase(
        uint256 _baseAmount,
        bytes calldata // unused
    ) internal pure override returns (uint256, uint256) {
        revert IHyperdrive.UnsupportedToken();
    }

    /// @dev Process a deposit in vault shares.
    /// @param _shareAmount The vault shares amount to deposit.
    function _depositWithShares(
        uint256 _shareAmount,
        bytes calldata // unused
    ) internal override {
        // Transfer stETH shares into the contract.
        _river.transferFrom(msg.sender, address(this), _shareAmount);
    }

    /// @dev Process a withdrawal in base and send the proceeds to the
    ///      destination.
    function _withdrawWithBase(
        uint256, // unused
        address, // unused
        bytes calldata // unused
    ) internal pure override returns (uint256) {
        // stETH withdrawals aren't necessarily instantaneous. Users that want
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
        _river.transfer(_destination, _shareAmount);
    }

    /// @dev We override the message value check since this integration is
    ///      payable.
    function _checkMessageValue() internal pure override {}

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return baseAmount The base amount.
    function _convertToBase(
        uint256 _shareAmount
    ) internal view override returns (uint256) {
        return _river.underlyingBalanceFromShares(_shareAmount);
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return shareAmount The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal view override returns (uint256) {
        return _river.sharesFromUnderlyingBalance(_baseAmount);
    }

    /// @dev Gets the total amount of base held by the pool.
    /// @return baseAmount The total amount of base.
    function _totalBase() internal pure override returns (uint256) {
        // NOTE: Since ETH is the base token and can't be swept, we can safely
        // return zero.
        return 0;
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
        return _river.balanceOf(address(this));
    }
}
