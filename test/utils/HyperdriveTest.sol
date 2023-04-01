// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { BaseTest } from "./BaseTest.sol";
import { ForwarderFactory } from "contracts/src/ForwarderFactory.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveBase } from "contracts/src/HyperdriveBase.sol";
import { MockHyperdrive } from "../mocks/MockHyperdrive.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveUtils } from "./HyperdriveUtils.sol";

contract HyperdriveTest is BaseTest {
    using FixedPointMath for uint256;

    ERC20Mintable baseToken;
    IHyperdrive hyperdrive;

    uint256 internal constant INITIAL_CONTRIBUTION = 1e15;
    uint256 internal constant INITIAL_SHARE_PRICE = FixedPointMath.ONE_18;
    uint256 internal constant CHECKPOINT_DURATION = 1 days;
    uint256 internal constant CHECKPOINTS_PER_TERM = 365;
    uint256 internal constant POSITION_DURATION =
        CHECKPOINT_DURATION * CHECKPOINTS_PER_TERM;

    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(alice);

        // Instantiate the base token.
        baseToken = new ERC20Mintable();

        // Instantiate Hyperdrive.
        deploy(
            alice,
            0.05e18,
            INITIAL_SHARE_PRICE,
            IHyperdrive.Fees({ curve: 0, flat: 0, governance: 0 }),
            governance
        );

        // Advance time so that Hyperdrive can look back more than a position
        // duration.
        vm.warp(POSITION_DURATION * 3);
    }

    function deploy(
        address deployer,
        uint256 apr,
        uint256 initialSharePrice,
        IHyperdrive.Fees memory fees,
        address governance
    ) internal {
        vm.stopPrank();
        vm.startPrank(deployer);

        // Mint base tokens for the initial contribution, and approve the
        // contract that will be deployed.
        baseToken.mint(INITIAL_CONTRIBUTION);
        bytes32 salt = keccak256(abi.encodePacked(deployer, block.number));
        bytes32 codeHash = keccak256(
            abi.encodePacked(
                type(MockHyperdrive).creationCode,
                abi.encode(
                    baseToken,
                    initialSharePrice,
                    CHECKPOINTS_PER_TERM,
                    CHECKPOINT_DURATION,
                    HyperdriveUtils.calculateTimeStretch(apr),
                    fees,
                    governance
                )
            )
        );
        address expectedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), deployer, salt, codeHash)
                    )
                )
            )
        );
        baseToken.approve(expectedAddress, INITIAL_CONTRIBUTION);

        // Deploy the contract.
        hyperdrive = IHyperdrive(
            address(
                new MockHyperdrive{ salt: salt }(
                    baseToken,
                    initialSharePrice,
                    CHECKPOINTS_PER_TERM,
                    CHECKPOINT_DURATION,
                    HyperdriveUtils.calculateTimeStretch(apr),
                    fees,
                    governance
                )
            )
        );
    }

    /// Actions ///

    function initialize(
        address lp,
        uint256 apr,
        uint256 contribution
    ) internal returns (uint256 lpShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Initialize the pool.
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        hyperdrive.initialize(contribution, apr, lp, true);

        return hyperdrive.balanceOf(AssetId._LP_ASSET_ID, lp);
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
        hyperdrive.addLiquidity(contribution, 0, type(uint256).max, lp, true);

        return hyperdrive.balanceOf(AssetId._LP_ASSET_ID, lp);
    }

    function removeLiquidity(
        address lp,
        uint256 shares
    ) internal returns (uint256 baseProceeds, uint256 withdrawalShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Remove liquidity from the pool.
        uint256 baseBalanceBefore = baseToken.balanceOf(lp);
        uint256 withdrawalShareBalanceBefore = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0),
            lp
        );
        hyperdrive.removeLiquidity(shares, 0, lp, true);

        return (
            baseToken.balanceOf(lp) - baseBalanceBefore,
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0),
                lp
            ) - withdrawalShareBalanceBefore
        );
    }

    function redeemWithdrawalShares(
        address lp,
        uint256 shares
    ) internal returns (uint256 baseProceeds) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Redeem the withdrawal shares.
        uint256 baseBalanceBefore = baseToken.balanceOf(lp);
        hyperdrive.redeemWithdrawalShares(shares, 0, lp, true);

        return baseToken.balanceOf(lp) - baseBalanceBefore;
    }

    function openLong(
        address trader,
        uint256 baseAmount
    ) internal returns (uint256 maturityTime, uint256 bondAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the long.
        maturityTime = HyperdriveUtils.maturityTimeFromLatestCheckpoint(
            hyperdrive
        );
        uint256 bondBalanceBefore = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            trader
        );
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, trader, true);

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
        hyperdrive.closeLong(maturityTime, bondAmount, 0, trader, true);

        uint256 baseBalanceAfter = baseToken.balanceOf(trader);
        return baseBalanceAfter.sub(baseBalanceBefore);
    }

    function openShort(
        address trader,
        uint256 bondAmount
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        return openShort(trader, bondAmount, bondAmount);
    }

    function openShort(
        address trader,
        uint256 bondAmount,
        uint256 maxDeposit
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the short
        maturityTime = HyperdriveUtils.maturityTimeFromLatestCheckpoint(
            hyperdrive
        );
        baseToken.mint(maxDeposit);
        baseToken.approve(address(hyperdrive), maxDeposit);
        uint256 baseBalanceBefore = baseToken.balanceOf(trader);
        hyperdrive.openShort(bondAmount, maxDeposit, trader, true);

        baseAmount = baseBalanceBefore - baseToken.balanceOf(trader);
        baseToken.burn(maxDeposit - baseAmount);
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
        hyperdrive.closeShort(maturityTime, bondAmount, 0, trader, true);

        return baseToken.balanceOf(trader) - baseBalanceBefore;
    }

    /// Utils ///
    function advanceTime(uint256 time, int256 apr) internal {
        MockHyperdrive(address(hyperdrive)).accrue(time, apr);
        vm.warp(block.timestamp + time);
    }
}
