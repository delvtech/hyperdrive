// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { MakerDsrHyperdrive, DsrManager } from "../src/instances/MakerDsrHyperdrive.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FixedPointMath } from "../src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "../src/ForwarderFactory.sol";
import { HyperdriveBase } from "contracts/src/HyperdriveBase.sol";

contract MockMakerDsrHyperdrive is MakerDsrHyperdrive {
    using FixedPointMath for uint256;

    constructor(
        DsrManager _dsrManager
    )
        MakerDsrHyperdrive(
            bytes32(0),
            address(0),
            365,
            1 days,
            FixedPointMath.ONE_18.divDown(22.186877016851916266e18),
            HyperdriveBase.Fees(0, 0, 0),
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
    ) external returns (uint256, uint256) {
        return _withdraw(shares, destination, asUnderlying);
    }

    function pricePerShare() external view returns (uint256) {
        return _pricePerShare();
    }
}
