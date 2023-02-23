// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { Hyperdrive } from "contracts/Hyperdrive.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { ERC20Mintable } from "test/mocks/ERC20Mintable.sol";

contract MockHyperdrive is Hyperdrive {
    using FixedPointMath for uint256;

    uint256 internal _sharePrice;

    constructor(
        ERC20Mintable baseToken,
        uint256 _initialSharePrice,
        uint256 _checkpointsPerTerm,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        uint256 _curveFee,
        uint256 _flatFee
    )
        Hyperdrive(
            bytes32(0),
            address(new ForwarderFactory()),
            baseToken,
            _initialSharePrice,
            _checkpointsPerTerm,
            _checkpointDuration,
            _timeStretch,
            _curveFee,
            _flatFee
        )
    {
        _sharePrice = _initialSharePrice;
    }

    /// Mocks ///

    function setFees(uint256 _curveFee, uint256 _flatFee) public {
        curveFee = _curveFee;
        flatFee = _flatFee;
    }

    error InvalidSharePrice();

    function getSharePrice() external view returns (uint256) {
        return _sharePrice;
    }

    function setSharePrice(uint256 sharePrice) external {
        if (sharePrice < _sharePrice) {
            revert InvalidSharePrice();
        }

        // Update the share price and accrue interest.
        ERC20Mintable(address(baseToken)).mint(
            (sharePrice.sub(_sharePrice)).mulDown(
                baseToken.balanceOf(address(this))
            )
        );
        _sharePrice = sharePrice;
    }

    /// Overrides ///

    function deposit(
        uint256 amount,
        bool
    ) internal override returns (uint256, uint256) {
        bool success = baseToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) {
            revert Errors.TransferFailed();
        }
        return (amount.divDown(_sharePrice), _sharePrice);
    }

    function withdraw(
        uint256 shares,
        address destination,
        bool
    ) internal override returns (uint256, uint256) {
        uint256 amountWithdrawn = shares.mulDown(_sharePrice);
        bool success = baseToken.transfer(destination, amountWithdrawn);
        if (!success) {
            revert Errors.TransferFailed();
        }
        return (amountWithdrawn, _sharePrice);
    }

    function pricePerShare() internal view override returns (uint256) {
        return _sharePrice;
    }
}
