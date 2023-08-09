// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC20PresetMinterPauser } from "openzeppelin-contracts/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { Hyperdrive } from "contracts/src/Hyperdrive.sol";
import { HyperdriveDataProvider } from "contracts/src/HyperdriveDataProvider.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { MultiTokenDataProvider } from "contracts/src/token/MultiTokenDataProvider.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { ETH } from "test/utils/Constants.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

interface IMockHyperdrive {
    function accrue(uint256 time, int256 apr) external;

    function calculateFeesOutGivenSharesIn(
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

    function calculateFeesOutGivenBondsIn(
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

    function calculateFeesInGivenBondsOut(
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

    function setReserves(uint256 shareReserves, uint256 bondReserves) external;

    function getGovernanceFeesAccrued() external view returns (uint256);
}

contract MockHyperdrive is Hyperdrive {
    using FixedPointMath for uint256;

    uint256 internal totalShares;

    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider
    ) Hyperdrive(_config, _dataProvider, bytes32(0), address(0)) {}

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

    function getOracleState() external view returns (uint256, uint256) {
        return (uint256(_oracle.head), uint256(_oracle.lastTimestamp));
    }

    function loadOracle(
        uint256 index
    ) external view returns (uint256, uint256) {
        return (
            uint256(_buffer[index].data),
            uint256(_buffer[index].timestamp)
        );
    }

    function recordOracle(uint256 data) external {
        recordPrice(data);
    }

    function calculateFeesOutGivenSharesIn(
        uint256 _amountIn,
        uint256 _spotPrice,
        uint256 sharePrice
    )
        external
        view
        returns (uint256 totalCurveFee, uint256 governanceCurveFee)
    {
        (totalCurveFee, governanceCurveFee) = _calculateFeesOutGivenSharesIn(
            _amountIn,
            _spotPrice,
            sharePrice
        );
        return (totalCurveFee, governanceCurveFee);
    }

    function calculateFeesOutGivenBondsIn(
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
        )
    {
        (
            totalCurveFee,
            totalFlatFee,
            totalGovernanceFee
        ) = _calculateFeesOutGivenBondsIn(
            _amountIn,
            _normalizedTimeRemaining,
            _spotPrice,
            sharePrice
        );
        return (totalCurveFee, totalFlatFee, totalGovernanceFee);
    }

    function calculateFeesInGivenBondsOut(
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
        )
    {
        (
            totalCurveFee,
            totalFlatFee,
            governanceCurveFee,
            governanceFlatFee
        ) = _calculateFeesInGivenBondsOut(
            _amountOut,
            _normalizedTimeRemaining,
            _spotPrice,
            sharePrice
        );
        return (
            totalCurveFee,
            totalFlatFee,
            governanceCurveFee,
            governanceFlatFee
        );
    }

    // Calls Hyperdrive._calculateOpenLong
    function calculateOpenLong(
        uint256 _shareAmount,
        uint256 _sharePrice
    )
        external
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

    function setReserves(uint256 shareReserves, uint256 bondReserves) external {
        _marketState.shareReserves = uint128(shareReserves);
        _marketState.bondReserves = uint128(bondReserves);
    }

    function getCurrentExposure() external view returns (int256) {
        return _getCurrentExposure();
    }

    /// Overrides ///

    // This overrides checkMessageValue to serve the dual purpose of making
    // ETH yield source instances to be payable and non-ETH yield
    // source instances non-payable.
    function _checkMessageValue() internal view override {
        if (address(_baseToken) != ETH && msg.value > 0) {
            revert IHyperdrive.NotPayable();
        }
    }

    function _deposit(
        uint256 amount,
        bool
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
            return (amount, _initialSharePrice);
        } else {
            uint256 newShares = totalShares.mulDivDown(amount, assets);
            totalShares += newShares;
            return (newShares, _pricePerShare());
        }
    }

    function _withdraw(
        uint256 shares,
        address destination,
        bool
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
            (success, ) = payable(destination).call{ value: withdrawValue }("");
        } else {
            success = _baseToken.transfer(destination, withdrawValue);
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
}

contract MockHyperdriveDataProvider is
    MultiTokenDataProvider,
    HyperdriveDataProvider
{
    using FixedPointMath for uint256;

    uint256 internal totalShares;

    constructor(
        IHyperdrive.PoolConfig memory _config
    )
        HyperdriveDataProvider(_config)
        MultiTokenDataProvider(bytes32(0), address(0))
    {}

    /// Mocks ///

    function getGovernanceFeesAccrued() external view returns (uint256) {
        _revert(abi.encode(_governanceFeesAccrued));
    }

    /// Overrides ///

    function _pricePerShare()
        internal
        view
        override
        returns (uint256 sharePrice)
    {
        uint256 assets = _baseToken.balanceOf(address(this));
        sharePrice = totalShares != 0 ? assets.divDown(totalShares) : 0;
        return sharePrice;
    }
}
