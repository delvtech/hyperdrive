// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC20PresetMinterPauser } from "openzeppelin-contracts/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { Hyperdrive } from "contracts/src/Hyperdrive.sol";
import { HyperdriveDataProvider } from "contracts/src/HyperdriveDataProvider.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { MultiTokenDataProvider } from "contracts/src/token/MultiTokenDataProvider.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";

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

    /// Overrides ///

    function _deposit(
        uint256 amount,
        bool
    ) internal override returns (uint256, uint256) {
        uint256 assets = _baseToken.balanceOf(address(this));
        bool success = _baseToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) {
            revert IHyperdrive.TransferFailed();
        }
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
        uint256 assets = _baseToken.balanceOf(address(this));
        shares = shares > totalShares ? totalShares : shares;
        withdrawValue = totalShares != 0
            ? shares.mulDown(assets.divDown(totalShares))
            : 0;
        bool success = _baseToken.transfer(destination, withdrawValue);
        if (!success) {
            revert IHyperdrive.TransferFailed();
        }
        totalShares -= shares;
        return withdrawValue;
    }

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
