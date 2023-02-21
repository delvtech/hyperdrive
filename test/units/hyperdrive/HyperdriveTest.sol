// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { AssetId } from "contracts/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
import { ERC20Mintable } from "test/mocks/ERC20Mintable.sol";
import { MockHyperdrive } from "test/mocks/MockHyperdrive.sol";

contract HyperdriveTest is Test {
    using FixedPointMath for uint256;

    address alice = address(uint160(uint256(keccak256("alice"))));
    address bob = address(uint160(uint256(keccak256("bob"))));
    address celine = address(uint160(uint256(keccak256("celine"))));

    ERC20Mintable baseToken;
    MockHyperdrive hyperdrive;

    uint256 internal constant INITIAL_SHARE_PRICE = FixedPointMath.ONE_18;
    uint256 internal constant CHECKPOINT_DURATION = 1 days;
    uint256 internal constant CHECKPOINTS_PER_TERM = 365;
    uint256 internal constant POSITION_DURATION =
        CHECKPOINT_DURATION * CHECKPOINTS_PER_TERM;

    function setUp() public {
        vm.startPrank(alice);

        // Instantiate the base token.
        baseToken = new ERC20Mintable();

        // Instantiate Hyperdrive.
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            22.186877016851916266e18
        );
        hyperdrive = new MockHyperdrive(
            baseToken,
            INITIAL_SHARE_PRICE,
            CHECKPOINTS_PER_TERM,
            CHECKPOINT_DURATION,
            timeStretch,
            0,
            0
        );

        // Advance time so that Hyperdrive can look back more than a position
        // duration.
        vm.warp(POSITION_DURATION * 3);
    }

    /// Actions ///

    function initialize(
        address lp,
        uint256 apr,
        uint256 contribution
    ) internal {
        vm.stopPrank();
        vm.startPrank(lp);

        // Initialize the pool.
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        hyperdrive.initialize(contribution, apr, lp);
    }

    function addLiquidity(
        address lp,
        uint256 contribution
    ) internal returns (uint256 lpShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Add liquidity to the pool.
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        hyperdrive.addLiquidity(contribution, 0, lp);

        return hyperdrive.balanceOf(AssetId._LP_ASSET_ID, lp);
    }

    function removeLiquidity(
        address lp,
        uint256 shares
    ) internal returns (uint256 baseProceeds) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Remove liquidity from the pool.
        uint256 baseBalanceBefore = baseToken.balanceOf(lp);
        hyperdrive.removeLiquidity(shares, 0, lp);

        return baseToken.balanceOf(lp) - baseBalanceBefore;
    }

    function openLong(
        address trader,
        uint256 baseAmount
    ) internal returns (uint256 maturityTime, uint256 bondAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the long.
        maturityTime = latestCheckpoint() + POSITION_DURATION;
        uint256 bondBalanceBefore = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            trader
        );
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, trader);

        uint256 bondBalanceAfter = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            trader
        );
        return (maturityTime, bondBalanceAfter.sub(bondBalanceBefore));
    }

    function closeLong(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount
    ) internal returns (uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Close the long.
        uint256 baseBalanceBefore = baseToken.balanceOf(trader);
        hyperdrive.closeLong(maturityTime, bondAmount, 0, trader);

        uint256 baseBalanceAfter = baseToken.balanceOf(trader);
        return baseBalanceAfter.sub(baseBalanceBefore);
    }

    function openShort(
        address trader,
        uint256 bondAmount
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the short
        maturityTime = latestCheckpoint() + POSITION_DURATION;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        uint256 baseBalanceBefore = baseToken.balanceOf(trader);
        hyperdrive.openShort(bondAmount, bondAmount, trader);

        baseAmount = baseBalanceBefore - baseToken.balanceOf(trader);
        baseToken.burn(bondAmount - baseAmount);
        return (maturityTime, baseAmount);
    }

    function closeShort(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount
    ) internal returns (uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Close the short
        uint256 baseBalanceBefore = baseToken.balanceOf(trader);
        hyperdrive.closeShort(maturityTime, bondAmount, 0, trader);

        return baseToken.balanceOf(trader) - baseBalanceBefore;
    }

    /// Utils ///

    struct PoolInfo {
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 lpTotalSupply;
        uint256 sharePrice;
        uint256 longsOutstanding;
        uint256 longAverageMaturityTime;
        uint256 longBaseVolume;
        uint256 shortsOutstanding;
        uint256 shortAverageMaturityTime;
        uint256 shortBaseVolume;
    }

    function getPoolInfo() internal view returns (PoolInfo memory) {
        (
            uint256 shareReserves,
            uint256 bondReserves,
            uint256 lpTotalSupply,
            uint256 sharePrice,
            uint256 longsOutstanding,
            uint256 longAverageMaturityTime,
            uint256 longBaseVolume,
            uint256 shortsOutstanding,
            uint256 shortAverageMaturityTime,
            uint256 shortBaseVolume
        ) = hyperdrive.getPoolInfo();
        return
            PoolInfo({
                shareReserves: shareReserves,
                bondReserves: bondReserves,
                lpTotalSupply: lpTotalSupply,
                sharePrice: sharePrice,
                longsOutstanding: longsOutstanding,
                longAverageMaturityTime: longAverageMaturityTime,
                longBaseVolume: longBaseVolume,
                shortsOutstanding: shortsOutstanding,
                shortAverageMaturityTime: shortAverageMaturityTime,
                shortBaseVolume: shortBaseVolume
            });
    }

    function calculateAPRFromReserves(
        MockHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        return
            HyperdriveMath.calculateAPRFromReserves(
                _hyperdrive.shareReserves(),
                _hyperdrive.bondReserves(),
                _hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
                _hyperdrive.initialSharePrice(),
                _hyperdrive.positionDuration(),
                _hyperdrive.timeStretch()
            );
    }

    function calculateAPRFromRealizedPrice(
        uint256 baseAmount,
        uint256 bondAmount,
        uint256 timeRemaining
    ) internal pure returns (uint256) {
        // apr = (dy - dx) / (dx * t)
        return
            (bondAmount.sub(baseAmount)).divDown(
                baseAmount.mulDown(timeRemaining)
            );
    }

    function calculateTimeRemaining(
        uint256 _maturityTime
    ) internal view returns (uint256 timeRemaining) {
        timeRemaining = _maturityTime > block.timestamp
            ? _maturityTime - block.timestamp
            : 0;
        timeRemaining = (timeRemaining).divDown(POSITION_DURATION);
        return timeRemaining;
    }

    function latestCheckpoint() internal view returns (uint256) {
        return block.timestamp - (block.timestamp % CHECKPOINT_DURATION);
    }
}
