// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { DsrHyperdrive, DsrManager } from "../src/instances/DsrHyperdrive.sol";
import { DsrHyperdriveDataProvider } from "../src/instances/DsrHyperdriveDataProvider.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { FixedPointMath } from "../src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "../src/ForwarderFactory.sol";
import { IHyperdrive } from "../src/interfaces/IHyperdrive.sol";

interface IMockDsrHyperdrive is IHyperdrive {
    function totalShares() external view returns (uint256);

    function deposit(
        uint256 amount,
        bool asUnderlying
    ) external returns (uint256, uint256);

    function withdraw(
        uint256 shares,
        address destination,
        bool asUnderlying
    ) external returns (uint256, uint256);

    function pricePerShare() external view returns (uint256);
}

contract MockDsrHyperdrive is DsrHyperdrive {
    using FixedPointMath for uint256;

    constructor(
        address _dataProvider,
        DsrManager _dsrManager
    )
        DsrHyperdrive(
            IHyperdrive.PoolConfig({
                baseToken: IERC20(address(_dsrManager.dai())),
                initialSharePrice: FixedPointMath.ONE_18,
                positionDuration: 365 days,
                checkpointDuration: 1 days,
                timeStretch: FixedPointMath.ONE_18.divDown(
                    22.186877016851916266e18
                ),
                governance: address(0),
                feeCollector: address(0),
                fees: IHyperdrive.Fees({ curve: 0, flat: 0, governance: 0 }),
                oracleSize: 2,
                updateGap: 0
            }),
            _dataProvider,
            bytes32(0),
            address(0),
            _dsrManager
        )
    {}

    function deposit(
        uint256 amount,
        bool asUnderlying
    ) external returns (uint256, uint256) {
        return _deposit(amount, asUnderlying);
    }

    function withdraw(
        uint256 shares,
        address destination,
        bool asUnderlying
    ) external returns (uint256) {
        return _withdraw(shares, destination, asUnderlying);
    }

    function pricePerShare() external view returns (uint256) {
        return _pricePerShare();
    }
}

contract MockDsrHyperdriveDataProvider is DsrHyperdriveDataProvider {
    using FixedPointMath for uint256;

    constructor(
        DsrManager _dsrManager
    )
        DsrHyperdriveDataProvider(
            IHyperdrive.PoolConfig({
                baseToken: IERC20(address(_dsrManager.dai())),
                initialSharePrice: FixedPointMath.ONE_18,
                positionDuration: 365 days,
                checkpointDuration: 1 days,
                timeStretch: FixedPointMath.ONE_18.divDown(
                    22.186877016851916266e18
                ),
                governance: address(0),
                feeCollector: address(0),
                fees: IHyperdrive.Fees({ curve: 0, flat: 0, governance: 0 }),
                oracleSize: 2,
                updateGap: 0
            }),
            bytes32(0),
            address(0),
            _dsrManager
        )
    {}
}
