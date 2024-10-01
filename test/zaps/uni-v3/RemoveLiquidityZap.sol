// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { ISwapRouter } from "../../../contracts/src/interfaces/ISwapRouter.sol";
import { IUniV3Zap } from "../../../contracts/src/interfaces/IUniV3Zap.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { UniV3Path } from "../../../contracts/src/libraries/UniV3Path.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { UniV3ZapTest } from "./UniV3Zap.t.sol";

contract RemoveLiquidityZapTest is UniV3ZapTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using UniV3Path for bytes;

    /// @dev FIXME
    uint256 internal lpSharesSDAI;

    /// @dev FIXME
    uint256 internal lpSharesStETH;

    /// @notice FIXME
    function setUp() public override {
        // Sets up the underlying test infrastructure.
        super.setUp();

        // Add liquidity in both Hyperdrive markets.
        IERC20(DAI).approve(address(SDAI_HYPERDRIVE), type(uint256).max);
        lpSharesSDAI = SDAI_HYPERDRIVE.addLiquidity(
            1_000e18,
            0,
            0,
            type(uint256).max,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );
        IERC20(STETH).approve(address(STETH_HYPERDRIVE), type(uint256).max);
        lpSharesStETH = STETH_HYPERDRIVE.addLiquidity(
            1e18,
            0,
            0,
            type(uint256).max,
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: new bytes(0)
            })
        );
    }

    /// @notice Ensure that zapping out of `removeLiquidity` will fail when the
    ///         recipient of `removeLong` isn't the zap contract.
    function test_removeLiquidityZap_failure_invalidRecipient() external {
        // Ensure that the zap fails when the recipient isn't Hyperdrive.
        vm.expectRevert(IUniV3Zap.InvalidRecipient.selector);
        zap.removeLiquidityZap(
            SDAI_HYPERDRIVE,
            0, // minimum output per share
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: ""
            }),
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(DAI, LOWEST_FEE_TIER, USDC),
                recipient: bob,
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e18,
                amountOutMinimum: 999e6
            })
        );
    }

    /// @notice Ensure that zapping out of `removeLiquidity` with base will fail
    ///         when the input isn't the base token.
    function test_removeLiquidityZap_failure_invalidInputToken_asBase()
        external
    {
        // Ensure that the zap fails when the recipient isn't Hyperdrive.
        vm.expectRevert(IUniV3Zap.InvalidInputToken.selector);
        zap.removeLiquidityZap(
            SDAI_HYPERDRIVE,
            0, // minimum output per share
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: address(zap),
                asBase: true,
                extraData: ""
            }),
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(USDC, LOWEST_FEE_TIER, DAI),
                recipient: alice,
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e6,
                amountOutMinimum: 999e18
            })
        );
    }

    /// @notice Ensure that zapping out of `removeLiquidity` with vault shares
    ///         will fail when the input isn't the vault shares token.
    function test_removeLiquidityZap_failure_invalidInputToken_asShares()
        external
    {
        // Ensure that the zap fails when the recipient isn't Hyperdrive.
        vm.expectRevert(IUniV3Zap.InvalidInputToken.selector);
        zap.removeLiquidityZap(
            SDAI_HYPERDRIVE,
            0, // minimum output per share
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: address(zap),
                asBase: false,
                extraData: ""
            }),
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(DAI, LOWEST_FEE_TIER, USDC),
                recipient: alice,
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e18,
                amountOutMinimum: 999e6
            })
        );
    }

    // FIXME: To really fix this, we'll need a yield source with WETH.
    function test_removeLiquidityZap_success_asBase_withWETH() external {
        // FIXME
    }

    /// @notice Ensure that zapping out of `removeLiquidity` with base will
    ///         succeed when the yield source is rebasing and when the input is
    ///         the base token.
    /// @dev This also tests using ETH as the output assets and verifies that
    ///      we can properly convert to WETH.
    function test_removeLiquidityZap_success_rebasing_asBase() external {
        _verifyRemoveLiquidityZap(
            STETH_HYPERDRIVE,
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(WETH, LOW_FEE_TIER, DAI),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                // NOTE: The amount in is smaller than the proceeds will be.
                // This will automatically be adjusted up.
                amountIn: 0.3882e18,
                amountOutMinimum: 999e18
            }),
            0.1e18, // this should be refunded
            true, // is rebasing
            true // as base
        );
    }

    /// @notice Ensure that zapping out of `removeLiquidity` with vault shares
    ///         will succeed when the yield source is rebasing and when the
    ///         input is the vault shares token.
    function test_removeLiquidityZap_success_rebasing_asShares() external {
        _verifyRemoveLiquidityZap(
            STETH_HYPERDRIVE,
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(STETH, LOW_FEE_TIER, DAI),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                // NOTE: The amount in is smaller than the proceeds will be.
                // This will automatically be adjusted up.
                amountIn: 0.3882e18,
                amountOutMinimum: 999e18
            }),
            0.1e18, // this should be refunded
            true, // is rebasing
            false // as base
        );
    }

    /// @notice Ensure that zapping out of `removeLiquidity` with base will
    ///         succeed when the yield source is non-rebasing and when the input is
    ///         the base token.
    function test_removeLiquidityZap_success_nonRebasing_asBase() external {
        // FIXME
    }

    /// @notice Ensure that zapping out of `removeLiquidity` with vault shares
    ///         will succeed when the yield source is non-rebasing and when the
    ///         input is the vault shares token.
    function test_removeLiquidityZap_success_nonRebasing_asShares() external {
        // FIXME
    }

    // FIXME: What should this be testing?
    //
    /// @dev Verify that `removeLiquidityZap` performs correctly under the
    ///      specified conditions.
    /// @param _hyperdrive The Hyperdrive instance.
    /// @param _swapParams The Uniswap multi-hop swap parameters.
    /// @param _isRebasing A flag indicating whether or not the yield source is
    ///        rebasing.
    /// @param _asBase A flag indicating whether or not the deposit should be in
    ///        base.
    function _verifyRemoveLiquidityZap(
        IHyperdrive _hyperdrive,
        ISwapRouter.ExactInputParams memory _swapParams,
        bool _isRebasing,
        bool _asBase
    ) internal {
        // FIXME
        //
        // // Gets some data about the trader and the pool before the zap.
        // bool isETHInput = _swapParams.path.tokenIn() == WETH &&
        //     _value > _swapParams.amountIn;
        // uint256 aliceBalanceBefore;
        // if (isETHInput) {
        //     aliceBalanceBefore = alice.balance;
        // } else {
        //     aliceBalanceBefore = IERC20(_swapParams.path.tokenIn()).balanceOf(
        //         alice
        //     );
        // }
        // uint256 hyperdriveVaultSharesBalanceBefore = IERC20(
        //     _hyperdrive.vaultSharesToken()
        // ).balanceOf(address(_hyperdrive));
        // uint256 longsOutstandingBefore = _hyperdrive
        //     .getPoolInfo()
        //     .longsOutstanding;
        // uint256 longBalanceBefore = _hyperdrive.balanceOf(
        //     AssetId.encodeAssetId(
        //         AssetId.AssetIdPrefix.Long,
        //         hyperdrive.latestCheckpoint() + POSITION_DURATION
        //     ),
        //     alice
        // );
        // uint256 spotPriceBefore = _hyperdrive.calculateSpotPrice();
        // // Zap into `openLong`.
        // uint256 value = _value; // avoid stack-too-deep
        // ISwapRouter.ExactInputParams memory swapParams = _swapParams; // avoid stack-too-deep
        // IHyperdrive hyperdrive = _hyperdrive; // avoid stack-too-deep
        // bool isRebasing = _isRebasing; // avoid stack-too-deep
        // bool asBase = _asBase; // avoid stack-too-deep
        // (uint256 maturityTime, uint256 longAmount) = zap.openLongZap{
        //     value: value
        // }(
        //     hyperdrive,
        //     0, // minimum output
        //     0, // minimum vault share price
        //     IHyperdrive.Options({
        //         destination: alice,
        //         asBase: asBase,
        //         extraData: ""
        //     }),
        //     isRebasing, // is rebasing
        //     swapParams
        // );
        // // Ensure that the maturity time is the latest checkpoint.
        // assertEq(
        //     maturityTime,
        //     hyperdrive.latestCheckpoint() +
        //         hyperdrive.getPoolConfig().positionDuration
        // );
        // // Ensure that Alice was charged the correct amount of the input token.
        // if (isETHInput) {
        //     assertEq(alice.balance, aliceBalanceBefore - swapParams.amountIn);
        // } else {
        //     assertEq(
        //         IERC20(swapParams.path.tokenIn()).balanceOf(alice),
        //         aliceBalanceBefore - swapParams.amountIn
        //     );
        // }
        // // Ensure that Hyperdrive received more than the minimum output of the
        // // swap.
        // uint256 hyperdriveVaultSharesBalanceAfter = IERC20(
        //     hyperdrive.vaultSharesToken()
        // ).balanceOf(address(hyperdrive));
        // if (isRebasing) {
        //     // NOTE: Since the vault shares rebase, the units are in base.
        //     assertGt(
        //         hyperdriveVaultSharesBalanceAfter,
        //         hyperdriveVaultSharesBalanceBefore + swapParams.amountOutMinimum
        //     );
        // } else if (asBase) {
        //     // NOTE: Since the vault shares don't rebase, the units are in shares.
        //     assertGt(
        //         hyperdriveVaultSharesBalanceAfter,
        //         hyperdriveVaultSharesBalanceBefore +
        //             _convertToShares(hyperdrive, swapParams.amountOutMinimum)
        //     );
        // } else {
        //     // NOTE: Since the vault shares don't rebase, the units are in shares.
        //     assertGt(
        //         hyperdriveVaultSharesBalanceAfter,
        //         hyperdriveVaultSharesBalanceBefore + swapParams.amountOutMinimum
        //     );
        // }
        // // Ensure that Alice received an appropriate amount of LP shares and
        // // that the LP total supply increased.
        // if (!asBase && !isRebasing) {
        //     // Ensure that the realized price is higher than the spot price
        //     // before.
        //     assertGt(
        //         _convertToBase(hyperdrive, swapParams.amountOutMinimum).divDown(
        //             longAmount
        //         ),
        //         spotPriceBefore
        //     );
        // }
        // assertEq(
        //     hyperdrive.balanceOf(
        //         AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
        //         alice
        //     ),
        //     longBalanceBefore + longAmount
        // );
        // assertEq(
        //     hyperdrive.getPoolInfo().longsOutstanding,
        //     longsOutstandingBefore + longAmount
        // );
    }
}
