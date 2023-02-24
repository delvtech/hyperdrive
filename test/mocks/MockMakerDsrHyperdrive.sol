// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { MakerDsrHyperdrive, DsrManager, Chai } from "contracts/instances/MakerDsrHyperdrive.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";

contract MockMakerDsrHyperdrive is MakerDsrHyperdrive {
    using FixedPointMath for uint256;

    constructor(
        IERC20 _chaiToken,
        DsrManager _dsrManager
    )
        MakerDsrHyperdrive(
            bytes32(0),
            address(new ForwarderFactory()),
            365,
            1 days,
            FixedPointMath.ONE_18.divDown(22.186877016851916266e18),
            0,
            0,
            _chaiToken,
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
