// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { ForwarderFactory } from "../src/ForwarderFactory.sol";
import { Hyperdrive } from "../src/Hyperdrive.sol";
import { FixedPointMath } from "../src/libraries/FixedPointMath.sol";
import { Errors } from "../src/libraries/Errors.sol";
import { ERC20Mintable } from "./ERC20Mintable.sol";

contract MockHyperdriveTestnet is Hyperdrive {
    using FixedPointMath for uint256;

    uint256 internal rate;
    uint256 internal lastUpdated;
    uint256 internal totalShares;

    constructor(
        ERC20Mintable baseToken,
        uint256 _initialRate,
        uint256 _initialSharePrice,
        uint256 _checkpointsPerTerm,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        Fees memory _fees,
        address _governance
    )
        Hyperdrive(
            bytes32(0),
            address(new ForwarderFactory()),
            baseToken,
            _initialSharePrice,
            _checkpointsPerTerm,
            _checkpointDuration,
            _timeStretch,
            _fees,
            _governance
        )
    {
        rate = _initialRate;
        lastUpdated = block.timestamp;
    }

    /// Overrides ///

    error UnsupportedOption();

    function _deposit(
        uint256 _amount,
        bool _asUnderlying
    ) internal override returns (uint256 sharesMinted, uint256 sharePrice) {
        // This yield source doesn't accept the underlying since it's just base.
        if (_asUnderlying) revert UnsupportedOption();

        // Accrue interest.
        accrueInterest();

        // Take custody of the base.
        bool success = baseToken.transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        if (!success) {
            revert Errors.TransferFailed();
        }

        // Update the total shares calculation.
        if (totalShares == 0) {
            totalShares = _amount;
            return (_amount, FixedPointMath.ONE_18);
        } else {
            sharePrice = _pricePerShare();
            sharesMinted = _amount.divDown(sharePrice);
            totalShares += sharesMinted;
            return (sharesMinted, sharePrice);
        }
    }

    function _withdraw(
        uint256 _shares,
        address _destination,
        bool _asUnderlying
    ) internal override returns (uint256 amountWithdrawn, uint256 sharePrice) {
        // This yield source doesn't accept the underlying since it's just base.
        if (_asUnderlying) revert UnsupportedOption();

        // Accrue interest.
        accrueInterest();

        // Transfer the base to the destination.
        sharePrice = _pricePerShare();
        amountWithdrawn = _shares.mulDown(sharePrice);
        bool success = baseToken.transfer(_destination, amountWithdrawn);
        if (!success) {
            revert Errors.TransferFailed();
        }

        return (amountWithdrawn, sharePrice);
    }

    function _pricePerShare() internal view override returns (uint256) {
        uint256 underlying = baseToken.balanceOf(address(this)) +
            getAccruedInterest();
        return underlying.divDown(totalShares);
    }

    /// Configuration ///

    function setRate(uint256 _rate) external {
        // Accrue interest.
        accrueInterest();

        // Update the rate.
        rate = _rate;
    }

    /// Helpers ///

    function getAccruedInterest() internal view returns (uint256) {
        // base_balance = base_balance * (1 + r * t)
        uint256 timeElapsed = (block.timestamp - lastUpdated).divDown(365 days);
        return
            baseToken.balanceOf(address(this)).mulDown(
                rate.mulDown(timeElapsed)
            );
    }

    function accrueInterest() internal {
        ERC20Mintable(address(baseToken)).mint(getAccruedInterest());
        lastUpdated = block.timestamp;
    }
}
