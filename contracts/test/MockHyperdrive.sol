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
    function accrue(uint256 time, int256 apr) external {
        (uint256 accrued, int256 interest) = calculateCompoundInterest(
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

        _sharePrice = accrued.divDown(
            marketState.shareReserves > 0 ? marketState.shareReserves : accrued
        );
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

    /// @dev Derives principal + compounded rate of interest over a period
    ///      principal * e ^ (rate * time)
    /// @param _principal The initial amount interest will be accrued on
    /// @param _apr Annual percentage rate
    /// @param _time Number of seconds compounding will occur for
    function calculateCompoundInterest(
        uint256 _principal,
        int256 _apr,
        uint256 _time
    ) public pure returns (uint256 accrued, int256 interest) {
        // Adjust time to a fraction of a year
        uint256 normalizedTime = _time.divDown(365 days);
        uint256 rt = uint256(_apr < 0 ? -_apr : _apr).mulDown(normalizedTime);

        if (_apr > 0) {
            accrued = _principal.mulDown(
                uint256(FixedPointMath.exp(int256(rt)))
            );
            interest = int256(accrued - _principal);
            return (accrued, interest);
        } else if (_apr < 0) {
            // NOTE: Might not be the correct calculation for negatively
            // continuously compounded interest
            accrued = _principal.divDown(
                uint256(FixedPointMath.exp(int256(rt)))
            );
            interest = int256(accrued) - int256(_principal);
            return (accrued, interest);
        }
        return (_principal, 0);
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
