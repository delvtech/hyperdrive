// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { ForwarderFactory } from "../src/ForwarderFactory.sol";
import { Hyperdrive } from "../src/Hyperdrive.sol";
import { FixedPointMath } from "../src/libraries/FixedPointMath.sol";
import { Errors } from "../src/libraries/Errors.sol";
import { ERC20Mintable } from "./ERC20Mintable.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

contract MockHyperdrive is Hyperdrive {
    using FixedPointMath for uint256;

    uint256 internal totalShares;

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
    {}

    /// Mocks ///

    function setFees(uint256 _curveFee, uint256 _flatFee) public {
        curveFee = _curveFee;
        flatFee = _flatFee;
    }

    function getGovFeesAccrued() external view returns (uint256) {
        return govFeesAccrued;
    }

    // Accrues compounded interest for a given number of seconds and readjusts
    // share price to reflect such compounding
    function accrue(uint256 time, int256 apr) external {
        (, int256 interest) = HyperdriveUtils.calculateCompoundInterest(
            baseToken.balanceOf(address(this)),
            apr,
            time
        );

        if (interest > 0) {
            ERC20Mintable(address(baseToken)).mint(
                address(this),
                uint256(interest)
            );
        } else if (interest < 0) {
            ERC20Mintable(address(baseToken)).burn(
                address(this),
                uint256(-interest)
            );
        }
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
    )
        public
        view
        returns (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 totalGovFee
        )
    {
        (
            totalCurveFee,
            totalFlatFee,
            totalGovFee
        ) = _calculateFeesOutGivenBondsIn(
            _amountIn,
            _normalizedTimeRemaining,
            _spotPrice,
            sharePrice
        );
        return (totalCurveFee, totalFlatFee, totalGovFee);
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

    /// Overrides ///

    function _deposit(
        uint256 amount,
        bool
    ) internal override returns (uint256, uint256) {
        uint256 assets = baseToken.balanceOf(address(this));
        bool success = baseToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) {
            revert Errors.TransferFailed();
        }
        if (totalShares == 0) {
            totalShares = amount;
            return (amount, FixedPointMath.ONE_18);
        } else {
            uint256 newShares = totalShares.mulDivDown(amount, assets);
            totalShares += newShares;
            return (newShares, amount.divDown(newShares));
        }
    }

    function _withdraw(
        uint256 shares,
        address destination,
        bool
    ) internal override returns (uint256 withdrawValue, uint256 sharePrice) {
        uint256 assets = baseToken.balanceOf(address(this));
        shares = shares > totalShares ? totalShares : shares;
        withdrawValue = assets.mulDivDown(shares, totalShares);
        bool success = baseToken.transfer(destination, withdrawValue);
        if (!success) {
            revert Errors.TransferFailed();
        }
        totalShares -= shares;
        sharePrice = withdrawValue != 0 ? shares.divDown(withdrawValue) : 0;
        return (withdrawValue, sharePrice);
    }

    function _pricePerShare()
        internal
        view
        override
        returns (uint256 sharePrice)
    {
        uint256 assets = baseToken.balanceOf(address(this));
        sharePrice = totalShares != 0 ? assets.divDown(totalShares) : 0;
        return sharePrice;
    }
}
