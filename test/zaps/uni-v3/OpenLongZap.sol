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

contract OpenLongZapTest is UniV3ZapTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using UniV3Path for bytes;

    /// @notice Ensure that zapping into `openLong` will fail when the
    ///         recipient isn't the zap contract.
    function test_openLongZap_failure_invalidRecipient() external {
        // Ensure that the zap fails when the recipient isn't Hyperdrive.
        vm.expectRevert(IUniV3Zap.InvalidRecipient.selector);
        zap.openLongZap(
            SDAI_HYPERDRIVE,
            0, // minimum output
            0, // minimum vault share price
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: ""
            }),
            false, // is rebasing
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(USDC, LOWEST_FEE_TIER, DAI),
                recipient: bob,
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e6,
                amountOutMinimum: 999e18
            })
        );
    }

    /// @notice Ensure that zapping into `openLong` with base will fail when
    ///         the output isn't the base token.
    function test_openLongZap_failure_invalidOutputToken_asBase() external {
        // Ensure that the zap fails when `asBase` is true and the output token
        // isn't the base token.
        vm.expectRevert(IUniV3Zap.InvalidOutputToken.selector);
        zap.openLongZap(
            SDAI_HYPERDRIVE,
            0, // minimum output
            0, // minimum vault share price
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: ""
            }),
            false, // is rebasing
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(
                    USDC,
                    LOW_FEE_TIER,
                    WETH,
                    LOW_FEE_TIER,
                    SDAI
                ),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e6,
                amountOutMinimum: 850e18
            })
        );
    }

    /// @notice Ensure that zapping into `openLong` with vault shares will
    ///         fail when the output isn't the vault shares token.
    function test_openLongZap_failure_invalidOutputToken_asShares() external {
        // Ensure that the zap fails when `asBase` is false and the output token
        // isn't the vault shares token.
        vm.expectRevert(IUniV3Zap.InvalidOutputToken.selector);
        zap.openLongZap(
            SDAI_HYPERDRIVE,
            0, // minimum output
            0, // minimum vault share price
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: ""
            }),
            false, // is rebasing
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(USDC, LOWEST_FEE_TIER, DAI),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e6,
                amountOutMinimum: 999e18
            })
        );
    }

    /// @notice Ensure that zapping into `openLong` with base refunds the
    ///         sender when they send ETH that can't be used for the zap.
    function test_openLongZap_success_asBase_refund() external {
        // Get Alice's ether balance before the zap.
        uint256 aliceBalanceBefore = alice.balance;

        // Zaps into `addLiquidity` with `asBase` as `true` from USDC to DAI.
        zap.openLongZap{ value: 100e18 }(
            SDAI_HYPERDRIVE,
            0, // minimum output
            0, // minimum vault share price
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: ""
            }),
            false, // is rebasing
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(USDC, LOWEST_FEE_TIER, DAI),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e6,
                amountOutMinimum: 999e18
            })
        );

        // Ensure that Alice's balance didn't change. This indicates that her
        // ETH transfer was fully refunded.
        assertEq(alice.balance, aliceBalanceBefore);
    }

    /// @notice Ensure that zapping into `openLong` with vault shares
    ///         refunds the sender when they send ETH that can't be used for the
    ///         zap.
    function test_openLongZap_success_asShares_refund() external {
        // Get Alice's ether balance before the zap.
        uint256 aliceBalanceBefore = alice.balance;

        // Zaps into `addLiquidity` with `asBase` as `false` from USDC to sDAI.
        zap.openLongZap{ value: 100e18 }(
            SDAI_HYPERDRIVE,
            0, // minimum output
            0, // minimum vault share price
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: ""
            }),
            false, // is rebasing
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(
                    USDC,
                    LOW_FEE_TIER,
                    WETH,
                    LOW_FEE_TIER,
                    SDAI
                ),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e6,
                amountOutMinimum: 850e18
            })
        );

        // Ensure that Alice's balance didn't change. This indicates that her
        // ETH transfer was fully refunded.
        assertEq(alice.balance, aliceBalanceBefore);
    }

    /// @notice Ensure that Alice can pay for a zap from WETH to DAI with WETH.
    ///         We send extra ETH in the zap to ensure that Alice gets refunded
    ///         for the excess.
    function test_openLongZap_success_asBase_withWETH() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // ETH (via WETH) to DAI is successful.
        _verifyOpenLongZap(
            SDAI_HYPERDRIVE,
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(WETH, LOW_FEE_TIER, DAI),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 0.3882e18,
                amountOutMinimum: 999e18
            }),
            0.1e18, // this should be refunded
            false, // is rebasing
            true // as base
        );
    }

    /// @notice Ensure that Alice can pay for a zap from WETH to sDAI with WETH.
    ///         We send extra ETH in the zap to ensure that Alice gets refunded
    ///         for the excess.
    function test_openLongZap_success_asShares_withWETH() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // ETH (via WETH) to sDAI is successful.
        _verifyOpenLongZap(
            SDAI_HYPERDRIVE,
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(WETH, LOW_FEE_TIER, SDAI),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 0.3882e18,
                amountOutMinimum: 886e18
            }),
            0.1e18, // this should be refunded
            false, // is rebasing
            false // as base
        );
    }

    /// @notice Ensure that Alice can pay for a zap from WETH to DAI with ETH.
    ///         We send extra ETH in the zap to ensure that Alice gets refunded
    ///         for the excess.
    function test_openLongZap_success_asBase_withETH() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // ETH (via WETH) to DAI is successful.
        _verifyOpenLongZap(
            SDAI_HYPERDRIVE,
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(WETH, LOW_FEE_TIER, DAI),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 0.3882e18,
                amountOutMinimum: 999e18
            }),
            10e18, // most of this should be refunded
            false, // is rebasing
            true // as base
        );
    }

    /// @notice Ensure that Alice can pay for a zap from WETH to sDAI with ETH.
    ///         We send extra ETH in the zap to ensure that Alice gets refunded
    ///         for the excess.
    function test_openLongZap_success_asShares_withETH() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // ETH (via WETH) to sDAI is successful.
        _verifyOpenLongZap(
            SDAI_HYPERDRIVE,
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(WETH, LOW_FEE_TIER, SDAI),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 0.3882e18,
                amountOutMinimum: 886e18
            }),
            10e18, // most of this should be refunded
            false, // is rebasing
            false // as base
        );
    }

    /// @notice Ensure that zapping into `openLong` with base succeeds with
    ///         a rebasing yield source.
    function test_openLongZap_success_rebasing_asBase() external {
        // Ensure that adding liquidity with base using a zap from USDC to WETH
        // (and ultimately into ETH) is successful.
        _verifyOpenLongZap(
            STETH_HYPERDRIVE,
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(USDC, MEDIUM_FEE_TIER, WETH),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e6,
                amountOutMinimum: 0.38e18
            }),
            10e18, // this should be completely refunded
            true, // is rebasing
            true // as base
        );
    }

    /// @notice Ensure that zapping into `openLong` with vault shares
    ///         succeeds with a rebasing yield source.
    function test_openLongZap_success_rebasing_asShares() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // USDC to stETH is successful.
        _verifyOpenLongZap(
            STETH_HYPERDRIVE,
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(
                    USDC,
                    MEDIUM_FEE_TIER,
                    WETH,
                    HIGH_FEE_TIER,
                    STETH
                ),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e6,
                amountOutMinimum: 0.38e18
            }),
            0,
            true, // is rebasing
            false // as base
        );
    }

    /// @notice Ensure that zapping into `openLong` with base succeeds with
    ///         a non-rebasing yield source.
    function test_openLongZap_success_nonRebasing_asBase() external {
        // Ensure that adding liquidity with base using a zap from USDC to DAI
        // is successful.
        _verifyOpenLongZap(
            SDAI_HYPERDRIVE,
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(USDC, LOWEST_FEE_TIER, DAI),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e6,
                amountOutMinimum: 999e18
            }),
            0,
            false, // is rebasing
            true // as base
        );
    }

    /// @notice Ensure that zapping into `openLong` with vault shares
    ///         succeeds with a non-rebasing yield source.
    function test_openLongZap_success_nonRebasing_asShares() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // USDC to sDAI is successful.
        _verifyOpenLongZap(
            SDAI_HYPERDRIVE,
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(
                    USDC,
                    LOW_FEE_TIER,
                    WETH,
                    LOW_FEE_TIER,
                    SDAI
                ),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e6,
                amountOutMinimum: 885e18
            }),
            10e18, // this should be completely refunded
            false, // is rebasing
            false // as base
        );
    }

    /// @dev Verify that `openLongZap` performs correctly under the
    ///      specified conditions.
    /// @param _hyperdrive The Hyperdrive instance.
    /// @param _swapParams The Uniswap multi-hop swap parameters.
    /// @param _value The ETH value to send in the transaction.
    /// @param _isRebasing A flag indicating whether or not the yield source is
    ///        rebasing.
    /// @param _asBase A flag indicating whether or not the deposit should be in
    ///        base.
    function _verifyOpenLongZap(
        IHyperdrive _hyperdrive,
        ISwapRouter.ExactInputParams memory _swapParams,
        uint256 _value,
        bool _isRebasing,
        bool _asBase
    ) internal {
        // Gets some data about the trader and the pool before the zap.
        bool isETHInput = _swapParams.path.tokenIn() == WETH &&
            _value > _swapParams.amountIn;
        uint256 aliceBalanceBefore;
        if (isETHInput) {
            aliceBalanceBefore = alice.balance;
        } else {
            aliceBalanceBefore = IERC20(_swapParams.path.tokenIn()).balanceOf(
                alice
            );
        }
        uint256 hyperdriveVaultSharesBalanceBefore = IERC20(
            _hyperdrive.vaultSharesToken()
        ).balanceOf(address(_hyperdrive));
        uint256 longsOutstandingBefore = _hyperdrive
            .getPoolInfo()
            .longsOutstanding;
        uint256 longBalanceBefore = _hyperdrive.balanceOf(
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Long,
                hyperdrive.latestCheckpoint() + POSITION_DURATION
            ),
            alice
        );
        uint256 spotPriceBefore = _hyperdrive.calculateSpotPrice();

        // Zap into `openLong`.
        uint256 value = _value; // avoid stack-too-deep
        ISwapRouter.ExactInputParams memory swapParams = _swapParams; // avoid stack-too-deep
        IHyperdrive hyperdrive = _hyperdrive; // avoid stack-too-deep
        bool isRebasing = _isRebasing; // avoid stack-too-deep
        bool asBase = _asBase; // avoid stack-too-deep
        (uint256 maturityTime, uint256 longAmount) = zap.openLongZap{
            value: value
        }(
            hyperdrive,
            0, // minimum output
            0, // minimum vault share price
            IHyperdrive.Options({
                destination: alice,
                asBase: asBase,
                extraData: ""
            }),
            isRebasing, // is rebasing
            swapParams
        );

        // Ensure that the maturity time is the latest checkpoint.
        assertEq(
            maturityTime,
            hyperdrive.latestCheckpoint() +
                hyperdrive.getPoolConfig().positionDuration
        );

        // Ensure that Alice was charged the correct amount of the input token.
        if (isETHInput) {
            assertEq(alice.balance, aliceBalanceBefore - swapParams.amountIn);
        } else {
            assertEq(
                IERC20(swapParams.path.tokenIn()).balanceOf(alice),
                aliceBalanceBefore - swapParams.amountIn
            );
        }

        // Ensure that Hyperdrive received more than the minimum output of the
        // swap.
        uint256 hyperdriveVaultSharesBalanceAfter = IERC20(
            hyperdrive.vaultSharesToken()
        ).balanceOf(address(hyperdrive));
        if (isRebasing) {
            // NOTE: Since the vault shares rebase, the units are in base.
            assertGt(
                hyperdriveVaultSharesBalanceAfter,
                hyperdriveVaultSharesBalanceBefore + swapParams.amountOutMinimum
            );
        } else if (asBase) {
            // NOTE: Since the vault shares don't rebase, the units are in shares.
            assertGt(
                hyperdriveVaultSharesBalanceAfter,
                hyperdriveVaultSharesBalanceBefore +
                    _convertToShares(hyperdrive, swapParams.amountOutMinimum)
            );
        } else {
            // NOTE: Since the vault shares don't rebase, the units are in shares.
            assertGt(
                hyperdriveVaultSharesBalanceAfter,
                hyperdriveVaultSharesBalanceBefore + swapParams.amountOutMinimum
            );
        }

        // Ensure that Alice received an appropriate amount of LP shares and
        // that the LP total supply increased.
        if (!asBase && !isRebasing) {
            // Ensure that the realized price is higher than the spot price
            // before.
            assertGt(
                _convertToBase(hyperdrive, swapParams.amountOutMinimum).divDown(
                    longAmount
                ),
                spotPriceBefore
            );
        }
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                alice
            ),
            longBalanceBefore + longAmount
        );
        assertEq(
            hyperdrive.getPoolInfo().longsOutstanding,
            longsOutstandingBefore + longAmount
        );
    }
}
