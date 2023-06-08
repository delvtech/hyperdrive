// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC20PresetMinterPauser } from "openzeppelin-contracts/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { Hyperdrive } from "../src/Hyperdrive.sol";
import { HyperdriveDataProvider } from "../src/HyperdriveDataProvider.sol";
import { MultiTokenDataProvider } from "../src/MultiTokenDataProvider.sol";
import { FixedPointMath } from "../src/libraries/FixedPointMath.sol";
import { Errors } from "../src/libraries/Errors.sol";
import { ERC20Mintable } from "./ERC20Mintable.sol";
import { IHyperdrive } from "../src/interfaces/IHyperdrive.sol";
import { IERC20 } from "../src/interfaces/IERC20.sol";

contract MockHyperdriveTestnet is Hyperdrive {
    using FixedPointMath for uint256;

    uint256 internal rate;
    uint256 internal lastUpdated;
    uint256 internal totalShares;

    constructor(
        address _dataProvider,
        ERC20Mintable _baseToken,
        uint256 _initialRate,
        uint256 _initialSharePrice,
        uint256 _positionDuration,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        IHyperdrive.Fees memory _fees,
        address _governance
    )
        Hyperdrive(
            IHyperdrive.PoolConfig({
                baseToken: IERC20(address(_baseToken)),
                initialSharePrice: _initialSharePrice,
                positionDuration: _positionDuration,
                checkpointDuration: _checkpointDuration,
                timeStretch: _timeStretch,
                governance: _governance,
                feeCollector: _feeCollector,
                fees: _fees,
                oracleSize: 2,
                updateGap: 0
            }),
            _dataProvider,
            bytes32(0),
            address(0)
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
        if (!_asUnderlying) revert UnsupportedOption();

        // Accrue interest.
        accrueInterest();

        // Take custody of the base.
        bool success = _baseToken.transferFrom(
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
        if (!_asUnderlying) revert UnsupportedOption();

        // Accrue interest.
        accrueInterest();

        // Transfer the base to the destination.
        sharePrice = _pricePerShare();
        amountWithdrawn = _shares.mulDown(sharePrice);
        bool success = _baseToken.transfer(_destination, amountWithdrawn);
        if (!success) {
            revert Errors.TransferFailed();
        }

        return (amountWithdrawn, sharePrice);
    }

    function _pricePerShare() internal view override returns (uint256) {
        uint256 underlying = _baseToken.balanceOf(address(this)) +
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
            _baseToken.balanceOf(address(this)).mulDown(
                rate.mulDown(timeElapsed)
            );
    }

    function accrueInterest() internal {
        ERC20Mintable(address(_baseToken)).mint(getAccruedInterest());
        lastUpdated = block.timestamp;
    }
}

contract MockHyperdriveDataProviderTestnet is
    MultiTokenDataProvider,
    HyperdriveDataProvider
{
    using FixedPointMath for uint256;

    uint256 internal rate;
    uint256 internal lastUpdated;
    uint256 internal totalShares;

    constructor(
        ERC20Mintable _baseToken,
        uint256 _initialRate,
        uint256 _initialSharePrice,
        uint256 _positionDuration,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        IHyperdrive.Fees memory _fees,
        address _governance
    )
        HyperdriveDataProvider(
            IHyperdrive.PoolConfig({
                baseToken: IERC20(address(_baseToken)),
                initialSharePrice: _initialSharePrice,
                positionDuration: _positionDuration,
                checkpointDuration: _checkpointDuration,
                timeStretch: _timeStretch,
                governance: _governance,
                feeCollector: _feeCollector,
                fees: _fees,
                oracleSize: 2,
                updateGap: 0
            })
        )
        MultiTokenDataProvider(_linkerCodeHash, _factory)
    {}

    /// Overrides ///

    function _pricePerShare() internal view override returns (uint256) {
        uint256 underlying = _baseToken.balanceOf(address(this)) +
            getAccruedInterest();
        return underlying.divDown(totalShares);
    }

    /// Helpers ///

    function getAccruedInterest() internal view returns (uint256) {
        // base_balance = base_balance * (1 + r * t)
        uint256 timeElapsed = (block.timestamp - lastUpdated).divDown(365 days);
        return
            _baseToken.balanceOf(address(this)).mulDown(
                rate.mulDown(timeElapsed)
            );
    }
}
