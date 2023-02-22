// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/libraries/AssetId.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "./HyperdriveTest.sol";
import "forge-std/console.sol";

contract removeLiquidityTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_remove_liquidity() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);
        uint256 lpToken = hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice);

        // Give user a long
        openLong(bob, contribution/5);

        // Have the LP remove funds
        removeLiquidity(alice, lpToken);

        // Close the long
        uint256 maturityTime = latestCheckpoint() + POSITION_DURATION;
        uint256 bobBalance = hyperdrive.balanceOf(AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime), bob);
        console.log(bobBalance);
        closeLong(bob, maturityTime, bobBalance);

        // 
    }
}
