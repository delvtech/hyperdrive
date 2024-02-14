// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveShort } from "contracts/src/internal/HyperdriveShort.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveStorage } from "contracts/src/internal/HyperdriveStorage.sol";
import { MockHyperdrive } from "contracts/test/MockHyperdrive.sol";

abstract contract MockHyperdriveShort is HyperdriveShort {
    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      opening a short. This calculation includes trading fees.
    /// @param _bondAmount The amount of bonds being sold to open the short.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _openVaultSharePrice The vault share price at the beginning of
    ///        the checkpoint.
    /// @return baseDeposit The deposit, in base, required to open the short.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return totalGovernanceFee The governance fee in shares.
    function calculateOpenShort(
        uint256 _bondAmount,
        uint256 _vaultSharePrice,
        uint256 _openVaultSharePrice
    )
        public
        view
        returns (
            uint256 baseDeposit,
            uint256 shareReservesDelta,
            uint256 totalGovernanceFee
        )
    {
        return
            _calculateOpenShort(
                _bondAmount,
                _vaultSharePrice,
                _openVaultSharePrice
            );
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      closing a short. This calculation includes trading fees.
    /// @param _bondAmount The amount of bonds being purchased to close the
    ///        short.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _maturityTime The maturity time of the short position.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return shareProceeds The proceeds in shares of closing the short.
    /// @return shareReservesDelta The shares added to the reserves.
    /// @return shareAdjustmentDelta The change in the share adjustment.
    /// @return totalGovernanceFee The governance fee in shares.
    function calculateCloseShort(
        uint256 _bondAmount,
        uint256 _vaultSharePrice,
        uint256 _maturityTime
    )
        public
        view
        returns (
            uint256 bondReservesDelta,
            uint256 shareProceeds,
            uint256 shareReservesDelta,
            int256 shareAdjustmentDelta,
            uint256 totalGovernanceFee
        )
    {
        return
            _calculateCloseShort(_bondAmount, _vaultSharePrice, _maturityTime);
    }
}
