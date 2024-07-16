// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { DoubleEndedQueue } from "openzeppelin/utils/structs/DoubleEndedQueue.sol";
import { EverlongAdmin } from "contracts/src/everlong/EverlongAdmin.sol";
import { EverlongERC4626 } from "contracts/src/everlong/EverlongERC4626.sol";
import { EverlongPositions } from "contracts/src/everlong/EverlongPositions.sol";

import { FixedPointMath, ONE } from "../libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";

contract Everlong is EverlongAdmin, EverlongERC4626, EverlongPositions {
    using DoubleEndedQueue for *;
    using FixedPointMath for uint256;
    // max 10% slippage
    uint256 constant MAX_SLIPPAGE = 1e17;

    constructor(
        address underlying_,
        string memory name_,
        string memory symbol_
    )
        EverlongAdmin()
        EverlongERC4626(underlying_, name_, symbol_)
        EverlongPositions()
    {}

    function _openLongs(uint256 _toSpend) internal {
        IHyperdrive.PoolInfo memory poolInfo = IHyperdrive(asset())
            .getPoolInfo();
        IHyperdrive.PoolConfig memory poolConfig = IHyperdrive(asset())
            .getPoolConfig();
        (uint256 effectiveShareReserves, bool success) = HyperdriveMath
            .calculateEffectiveShareReservesSafe(
                poolInfo.shareReserves,
                poolInfo.shareAdjustment
            );
        if (!success) {
            revert("ahhh");
        }
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            effectiveShareReserves,
            poolInfo.bondReserves,
            poolConfig.initialVaultSharePrice,
            poolConfig.timeStretch
        );
        (uint256 maturityTime, uint256 bondProceeds) = IHyperdrive(asset())
            .openLong(
                _toSpend,
                _toSpend /
                    spotPrice -
                    ((_toSpend * MAX_SLIPPAGE) / (spotPrice * 1e18)),
                0,
                IHyperdrive.Options(address(this), false, "")
            );
        Position memory latestPosition = abi.decode(
            abi.encodePacked(_positions.back()),
            (Position)
        );
        if (latestPosition.maturityTime == maturityTime) {
            _positions.popBack();
            _positions.pushBack(
                bytes32(bytes32(bytes16(latestPosition.maturityTime)) >> 16) |
                    bytes16(latestPosition.bondAmount + uint128(bondProceeds))
            );
        } else {
            _positions.pushBack(
                bytes32(bytes32(bytes16(uint128(maturityTime))) >> 16) |
                    bytes16(uint128(bondProceeds))
            );
        }
    }
}
