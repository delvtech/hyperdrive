// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { AssetId } from "contracts/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "test/mocks/ERC20Mintable.sol";
import { MockHyperdrive } from "test/mocks/MockHyperdrive.sol";

contract HyperdriveTest is Test {
    using FixedPointMath for uint256;

    address alice = address(uint160(uint256(keccak256("alice"))));
    address bob = address(uint160(uint256(keccak256("bob"))));

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
            timeStretch
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

    function addLiquidity(address lp, uint256 contribution) internal {
        vm.stopPrank();
        vm.startPrank(lp);

        // Add liquidity to the pool.
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        hyperdrive.addLiquidity(contribution, 0, lp);
    }

    function removeLiquidity(address lp, uint256 shares) internal {
        vm.stopPrank();
        vm.startPrank(lp);

        // Remove liquidity from the pool.
        hyperdrive.setApprovalForAll(address(hyperdrive), true);
        hyperdrive.removeLiquidity(shares, 0, lp);
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
        hyperdrive.setApprovalForAll(address(hyperdrive), true);
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
        uint256 baseBalanceBefore = baseToken.balanceOf(trader);
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        hyperdrive.openShort(bondAmount, 0, trader);

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
        hyperdrive.setApprovalForAll(address(hyperdrive), true);
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

    function calculateAPRFromRealizedPrice(
        uint256 baseAmount,
        uint256 bondAmount,
        uint256 timeRemaining,
        uint256 positionDuration
    ) internal pure returns (uint256) {
        // apr = (dy - dx) / (dx * t)
        uint256 t = timeRemaining.divDown(positionDuration);
        return (bondAmount.sub(baseAmount)).divDown(baseAmount.mulDown(t));
    }

    function latestCheckpoint() internal view returns (uint256) {
        return block.timestamp - (block.timestamp % CHECKPOINT_DURATION);
    }
}
