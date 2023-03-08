// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { ForwarderFactory } from "../src/ForwarderFactory.sol";
import { Hyperdrive } from "../src/Hyperdrive.sol";
import { FixedPointMath } from "../src/libraries/FixedPointMath.sol";
import { Errors } from "../src/libraries/Errors.sol";
import { ERC20Mintable } from "./ERC20Mintable.sol";

contract MockHyperdrive is Hyperdrive {
    using FixedPointMath for uint256;

    uint256 internal _sharePrice;

    constructor(
        ERC20Mintable baseToken,
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

    function getGovFeesAccrued() external view returns (uint256) {
        return govFeesAccrued;
    }

    // Accrues compounded interest for a given number of seconds and readjusts
    // share price to reflect such compounding
    function accrue(uint256 time, uint256 apr) external {
        (uint256 accrued, uint256 interest) = calculateCompoundInterest(
            baseToken.balanceOf(address(this)),
            apr,
            time
        );

        if (interest > 0) {
            ERC20Mintable(address(baseToken)).mint(interest);
        }

        _sharePrice = accrued.divDown(
            marketState.shareReserves > 0 ? marketState.shareReserves : accrued
        );
    }

    function setSharePrice(uint256 sharePrice) external {
        if (sharePrice > _sharePrice) {
            // Update the share price and accrue interest.
            ERC20Mintable(address(baseToken)).mint(
                (sharePrice.sub(_sharePrice)).mulDown(
                    baseToken.balanceOf(address(this))
                )
            );
        } else {
            baseToken.transfer(
                address(1),
                (_sharePrice.sub(sharePrice)).mulDown(
                    baseToken.balanceOf(address(this))
                )
            );
        }
        _sharePrice = sharePrice;
    }

    function calculateFeesOutGivenSharesIn(
        uint256 _amountIn,
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 sharePrice
    )
        public
        view
        returns (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 govCurveFee,
            uint256 govFlatFee
        )
    {
        (
            totalCurveFee,
            totalFlatFee,
            govCurveFee,
            govFlatFee
        ) = _calculateFeesOutGivenSharesIn(
            _amountIn,
            _amountOut,
            _normalizedTimeRemaining,
            _spotPrice,
            sharePrice
        );
        return (totalCurveFee, totalFlatFee, govCurveFee, govFlatFee);
    }

    function calculateFeesOutGivenBondsIn(
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 sharePrice
    ) public view returns (uint256 totalFee, uint256 totalGovFee) {
        (totalFee, totalGovFee) = _calculateFeesOutGivenBondsIn(
            _amountIn,
            _normalizedTimeRemaining,
            _spotPrice,
            sharePrice
        );
        return (totalFee, totalGovFee);
    }

    function calculateFeesInGivenBondsOut(
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 sharePrice
    )
        public
        view
        returns (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 govCurveFee,
            uint256 govFlatFee
        )
    {
        (
            totalCurveFee,
            totalFlatFee,
            govCurveFee,
            govFlatFee
        ) = _calculateFeesInGivenBondsOut(
            _amountOut,
            _normalizedTimeRemaining,
            _spotPrice,
            sharePrice
        );
        return (totalCurveFee, totalFlatFee, govCurveFee, govFlatFee);
    }

    // Derives principal + compounded rate of interest over a period
    // principal * e ^ (rate * time)
    function calculateCompoundInterest(
        uint256 _principal,
        uint256 _apr,
        uint256 _time
    ) public pure returns (uint256 accrued, uint256 interest) {
        uint256 normalizedTime = _time.divDown(365 days);
        accrued = _principal.mulDown(
            uint256(FixedPointMath.exp(int256(_apr.mulDown(normalizedTime))))
        );
        interest = accrued - _principal;
    }

    /// Overrides ///

    function _deposit(
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

    function _withdraw(
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

    function _pricePerShare() internal view override returns (uint256) {
        return _sharePrice;
    }
}
