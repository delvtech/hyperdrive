// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { Hyperdrive } from "contracts/src/external/Hyperdrive.sol";
import { HyperdriveTarget0 } from "contracts/src/external/HyperdriveTarget0.sol";
import { HyperdriveTarget1 } from "contracts/src/external/HyperdriveTarget1.sol";
import { HyperdriveBase } from "contracts/src/internal/HyperdriveBase.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { ETH } from "test/utils/Constants.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

interface IMockHyperdrive {
    function accrue(uint256 time, int256 apr) external;

    function calculateFeesGivenShares(
        uint256 _amountIn,
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 sharePrice
    )
        external
        view
        returns (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 governanceCurveFee,
            uint256 governanceFlatFee
        );

    function calculateFeesGivenBonds(
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 sharePrice
    )
        external
        view
        returns (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 totalGovernanceFee
        );

    function calculateOpenLong(
        uint256 _shareAmount,
        uint256 _sharePrice,
        uint256 _timeRemaining
    )
        external
        view
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 bondProceeds,
            uint256 totalGovernanceFee
        );

    function calculateTimeRemaining(
        uint256 _maturityTime
    ) external view returns (uint256);

    function calculateTimeRemainingScaled(
        uint256 _maturityTime
    ) external view returns (uint256);

    function latestCheckpoint() external view returns (uint256);

    function updateLiquidity(uint256 shareReservesDelta) external;

    function setReserves(uint256 shareReserves, uint256 bondReserves) external;

    function getGovernanceFeesAccrued() external view returns (uint256);
}

abstract contract MockHyperdriveBase is HyperdriveBase {
    using FixedPointMath for uint256;

    uint256 internal totalShares;

    function _deposit(
        uint256 amount,
        IHyperdrive.Options calldata
    ) internal override returns (uint256, uint256) {
        // Transfer the specified amount of funds from the trader. If the trader
        // overpaid, we return the excess amount.
        uint256 assets;
        bool success = true;
        if (address(_baseToken) == ETH) {
            assets = address(this).balance;
            if (msg.value < amount) {
                revert IHyperdrive.TransferFailed();
            }
            if (msg.value > amount) {
                (success, ) = payable(msg.sender).call{
                    value: msg.value - amount
                }("");
            }
        } else {
            assets = _baseToken.balanceOf(address(this));
            success = _baseToken.transferFrom(
                msg.sender,
                address(this),
                amount
            );
        }
        if (!success) {
            revert IHyperdrive.TransferFailed();
        }

        // Increase the total shares and return with the amount of shares minted
        // and the current share price.
        if (totalShares == 0) {
            totalShares = amount.divDown(_initialSharePrice);
            return (totalShares, _initialSharePrice);
        } else {
            uint256 newShares = totalShares.mulDivDown(amount, assets);
            totalShares += newShares;
            return (newShares, _pricePerShare());
        }
    }

    function _withdraw(
        uint256 shares,
        IHyperdrive.Options calldata options
    ) internal override returns (uint256 withdrawValue) {
        // If the shares to withdraw is greater than the total shares, we clamp
        // to the total shares.
        shares = shares > totalShares ? totalShares : shares;

        // Get the total amount of assets held in the pool.
        uint256 assets;
        if (address(_baseToken) == ETH) {
            assets = address(this).balance;
        } else {
            assets = _baseToken.balanceOf(address(this));
        }

        // Calculate the base proceeds.
        withdrawValue = totalShares != 0
            ? shares.mulDown(assets.divDown(totalShares))
            : 0;

        // Transfer the base proceeds to the destination and burn the shares.
        totalShares -= shares;
        bool success;
        if (address(_baseToken) == ETH) {
            (success, ) = payable(options.destination).call{
                value: withdrawValue
            }("");
        } else {
            success = _baseToken.transfer(options.destination, withdrawValue);
        }
        if (!success) {
            revert IHyperdrive.TransferFailed();
        }

        return withdrawValue;
    }

    function _pricePerShare()
        internal
        view
        override
        returns (uint256 sharePrice)
    {
        // Get the total amount of base held in Hyperdrive.
        uint256 assets;
        if (address(_baseToken) == ETH) {
            assets = address(this).balance;
        } else {
            assets = _baseToken.balanceOf(address(this));
        }

        // The share price is the total amount of base divided by the total
        // amount of shares.
        sharePrice = totalShares != 0 ? assets.divDown(totalShares) : 0;
    }

    // This overrides checkMessageValue to serve the dual purpose of making
    // ETH yield source instances to be payable and non-ETH yield
    // source instances non-payable.
    function _checkMessageValue() internal view override {
        if (address(_baseToken) != ETH && msg.value > 0) {
            revert IHyperdrive.NotPayable();
        }
    }
}

contract MockHyperdrive is Hyperdrive, MockHyperdriveBase {
    using FixedPointMath for uint256;

    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _target0,
        address _target1
    ) Hyperdrive(_config, _target0, _target1, bytes32(0), address(0)) {}

    /// Mocks ///

    function setMarketState(
        IHyperdrive.MarketState memory _marketState_
    ) external {
        _marketState = _marketState_;
    }

    function setTotalShares(uint256 _totalShares) external {
        totalShares = _totalShares;
    }

    // Accrues compounded interest for a given number of seconds and readjusts
    // share price to reflect such compounding
    function accrue(uint256 time, int256 apr) external {
        (, int256 interest) = HyperdriveUtils.calculateCompoundInterest(
            _baseToken.balanceOf(address(this)),
            apr,
            time
        );

        if (interest > 0) {
            ERC20Mintable(address(_baseToken)).mint(
                address(this),
                uint256(interest)
            );
        } else if (interest < 0) {
            ERC20Mintable(address(_baseToken)).burn(
                address(this),
                uint256(-interest)
            );
        }
    }

    function calculateFeesGivenShares(
        uint256 _amountIn,
        uint256 _spotPrice,
        uint256 sharePrice
    )
        external
        view
        returns (uint256 totalCurveFee, uint256 governanceCurveFee)
    {
        (totalCurveFee, governanceCurveFee) = _calculateFeesGivenShares(
            _amountIn,
            _spotPrice,
            sharePrice
        );
        return (totalCurveFee, governanceCurveFee);
    }

    function calculateFeesGivenBonds(
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 sharePrice
    )
        external
        view
        returns (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 governanceCurveFee,
            uint256 governanceFlatFee,
            uint256 totalGovernanceFee
        )
    {
        (
            totalCurveFee,
            totalFlatFee,
            governanceCurveFee,
            governanceFlatFee,
            totalGovernanceFee
        ) = _calculateFeesGivenBonds(
            _amountOut,
            _normalizedTimeRemaining,
            _spotPrice,
            sharePrice
        );
        return (
            totalCurveFee,
            totalFlatFee,
            governanceCurveFee,
            governanceFlatFee,
            totalGovernanceFee
        );
    }

    // Calls Hyperdrive._calculateOpenLong
    function calculateOpenLong(
        uint256 _shareAmount,
        uint256 _sharePrice
    )
        external
        view
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 bondProceeds,
            uint256 totalGovernanceFee
        )
    {
        return _calculateOpenLong(_shareAmount, _sharePrice);
    }

    function calculateTimeRemaining(
        uint256 _maturityTime
    ) external view returns (uint256 timeRemaining) {
        return _calculateTimeRemaining(_maturityTime);
    }

    function calculateTimeRemainingScaled(
        uint256 _maturityTime
    ) external view returns (uint256 timeRemaining) {
        return _calculateTimeRemainingScaled(_maturityTime);
    }

    function latestCheckpoint() external view returns (uint256 checkpointTime) {
        return _latestCheckpoint();
    }

    function updateLiquidity(int256 _shareReservesDelta) external {
        _updateLiquidity(_shareReservesDelta);
    }

    function calculateIdleShareReserves(
        uint256 _sharePrice
    ) external view returns (uint256) {
        return _calculateIdleShareReserves(_sharePrice);
    }

    function getTotalShares() external view returns (uint256) {
        return totalShares;
    }

    function setReserves(uint128 shareReserves, uint128 bondReserves) external {
        _marketState.shareReserves = shareReserves;
        _marketState.bondReserves = bondReserves;
    }

    function setLongExposure(uint128 longExposure) external {
        _marketState.longExposure = longExposure;
    }
}

contract MockHyperdriveTarget0 is HyperdriveTarget0, MockHyperdriveBase {
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveTarget0(_config, bytes32(0), address(0)) {}

    /// Mocks ///

    function getGovernanceFeesAccrued() external view returns (uint256) {
        _revert(abi.encode(_governanceFeesAccrued));
    }
}

contract MockHyperdriveTarget1 is HyperdriveTarget1, MockHyperdriveBase {
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveTarget1(_config, bytes32(0), address(0)) {}
}
