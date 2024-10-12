// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { ISwapRouter } from "../../../contracts/src/interfaces/ISwapRouter.sol";
import { IUniV3Zap } from "../../../contracts/src/interfaces/IUniV3Zap.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { ETH } from "../../../contracts/src/libraries/Constants.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { UniV3Path } from "../../../contracts/src/libraries/UniV3Path.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { UniV3ZapTest } from "./UniV3Zap.t.sol";

contract AddLiquidityZapTest is UniV3ZapTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using UniV3Path for bytes;

    /// @notice Ensure that zapping into `addLiquidity` will fail when the
    ///         recipient isn't the zap contract.
    function test_addLiquidityZap_failure_invalidRecipient() external {
        vm.expectRevert(IUniV3Zap.InvalidRecipient.selector);
        zap.addLiquidityZap(
            SDAI_HYPERDRIVE,
            0, // minimum LP share price
            0, // minimum APR
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: ""
            }),
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(USDC, LOWEST_FEE_TIER, DAI),
                    recipient: bob,
                    deadline: block.timestamp + 1 minutes,
                    amountIn: 1_000e6,
                    amountOutMinimum: 999e18
                }),
                sourceAsset: USDC,
                sourceAmount: 1_000e6,
                shouldWrap: false,
                isRebasing: false
            })
        );
    }

    /// @notice Ensure that zapping into `addLiquidity` will fail when the
    ///         input and output tokens are the same.
    function test_addLiquidityZap_failure_invalidSwap() external {
        vm.expectRevert(IUniV3Zap.InvalidSwap.selector);
        zap.addLiquidityZap(
            SDAI_HYPERDRIVE,
            0, // minimum LP share price
            0, // minimum APR
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: ""
            }),
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(DAI, LOWEST_FEE_TIER, DAI),
                    recipient: address(zap),
                    deadline: block.timestamp + 1 minutes,
                    amountIn: 1_000e18,
                    amountOutMinimum: 999e18
                }),
                sourceAsset: DAI,
                sourceAmount: 1_000e18,
                shouldWrap: false,
                isRebasing: false
            })
        );
    }

    /// @notice Ensure that zapping into `addLiquidity` with base will fail when
    ///         the output isn't the base token.
    function test_addLiquidityZap_failure_invalidOutputToken_asBase() external {
        vm.expectRevert(IUniV3Zap.InvalidOutputToken.selector);
        zap.addLiquidityZap(
            SDAI_HYPERDRIVE,
            0, // minimum LP share price
            0, // minimum APR
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: ""
            }),
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
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
                }),
                sourceAsset: USDC,
                sourceAmount: 1_000e6,
                shouldWrap: false,
                isRebasing: false
            })
        );
    }

    /// @notice Ensure that zapping into `addLiquidity` with vault shares will
    ///         fail when the output isn't the vault shares token.
    function test_addLiquidityZap_failure_invalidOutputToken_asShares()
        external
    {
        vm.expectRevert(IUniV3Zap.InvalidOutputToken.selector);
        zap.addLiquidityZap(
            SDAI_HYPERDRIVE,
            0, // minimum LP share price
            0, // minimum APR
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: ""
            }),
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(USDC, LOWEST_FEE_TIER, DAI),
                    recipient: address(zap),
                    deadline: block.timestamp + 1 minutes,
                    amountIn: 1_000e6,
                    amountOutMinimum: 999e18
                }),
                sourceAsset: USDC,
                sourceAmount: 1_000e6,
                shouldWrap: false,
                isRebasing: false
            })
        );
    }

    /// @notice Ensure that zapping into `addLiquidity` with base refunds the
    ///         sender when they send ETH that can't be used for the zap.
    function test_addLiquidityZap_success_asBase_refund() external {
        // Get Alice's ether balance before the zap.
        uint256 aliceBalanceBefore = alice.balance;

        // Zaps into `addLiquidity` with `asBase` as `true` from USDC to DAI.
        zap.addLiquidityZap{ value: 100e18 }(
            SDAI_HYPERDRIVE,
            0, // minimum LP share price
            0, // minimum APR
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: ""
            }),
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(USDC, LOWEST_FEE_TIER, DAI),
                    recipient: address(zap),
                    deadline: block.timestamp + 1 minutes,
                    amountIn: 1_000e6,
                    amountOutMinimum: 999e18
                }),
                sourceAsset: USDC,
                sourceAmount: 1_000e6,
                shouldWrap: false,
                isRebasing: false
            })
        );

        // Ensure that Alice's balance didn't change. This indicates that her
        // ETH transfer was fully refunded.
        assertEq(alice.balance, aliceBalanceBefore);
    }

    /// @notice Ensure that zapping into `addLiquidity` with vault shares
    ///         refunds the sender when they send ETH that can't be used for the
    ///         zap.
    function test_addLiquidityZap_success_asShares_refund() external {
        // Get Alice's ether balance before the zap.
        uint256 aliceBalanceBefore = alice.balance;

        // Zaps into `addLiquidity` with `asBase` as `false` from USDC to sDAI.
        zap.addLiquidityZap{ value: 100e18 }(
            SDAI_HYPERDRIVE,
            0, // minimum LP share price
            0, // minimum APR
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: ""
            }),
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
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
                }),
                sourceAsset: USDC,
                sourceAmount: 1_000e6,
                shouldWrap: false,
                isRebasing: false
            })
        );

        // Ensure that Alice's balance didn't change. This indicates that her
        // ETH transfer was fully refunded.
        assertEq(alice.balance, aliceBalanceBefore);
    }

    /// @notice Ensure that Alice can pay for a zap from WETH to DAI with WETH.
    ///         We send extra ETH in the zap to ensure that Alice gets refunded
    ///         for the excess.
    function test_addLiquidityZap_success_asBase_withWETH() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // ETH (via WETH) to DAI is successful.
        _verifyAddLiquidityZap(
            SDAI_HYPERDRIVE,
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(WETH, LOW_FEE_TIER, DAI),
                    recipient: address(zap),
                    deadline: block.timestamp + 1 minutes,
                    amountIn: 0.3882e18,
                    amountOutMinimum: 999e18
                }),
                sourceAsset: WETH,
                sourceAmount: 0.3882e18,
                shouldWrap: false,
                isRebasing: false
            }),
            0.1e18, // this should be refunded
            true // as base
        );
    }

    /// @notice Ensure that Alice can pay for a zap from WETH to sDAI with WETH.
    ///         We send extra ETH in the zap to ensure that Alice gets refunded
    ///         for the excess.
    function test_addLiquidityZap_success_asShares_withWETH() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // ETH (via WETH) to sDAI is successful.
        _verifyAddLiquidityZap(
            SDAI_HYPERDRIVE,
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(WETH, LOW_FEE_TIER, SDAI),
                    recipient: address(zap),
                    deadline: block.timestamp + 1 minutes,
                    amountIn: 0.3882e18,
                    amountOutMinimum: 886e18
                }),
                sourceAsset: WETH,
                sourceAmount: 0.3882e18,
                shouldWrap: false,
                isRebasing: false
            }),
            0.1e18, // this should be refunded
            false // as base
        );
    }

    /// @notice Ensure that Alice can pay for a zap from WETH to DAI with ETH.
    ///         We send extra ETH in the zap to ensure that Alice gets refunded
    ///         for the excess.
    function test_addLiquidityZap_success_asBase_withETH() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // ETH (via WETH) to DAI is successful.
        _verifyAddLiquidityZap(
            SDAI_HYPERDRIVE,
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(WETH, LOW_FEE_TIER, DAI),
                    recipient: address(zap),
                    deadline: block.timestamp + 1 minutes,
                    amountIn: 0.3882e18,
                    amountOutMinimum: 999e18
                }),
                sourceAsset: ETH,
                sourceAmount: 0.3882e18,
                shouldWrap: true,
                isRebasing: false
            }),
            10e18, // most of this should be refunded
            true // as base
        );
    }

    /// @notice Ensure that Alice can pay for a zap from WETH to sDAI with ETH.
    ///         We send extra ETH in the zap to ensure that Alice gets refunded
    ///         for the excess.
    function test_addLiquidityZap_success_asShares_withETH() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // ETH (via WETH) to sDAI is successful.
        _verifyAddLiquidityZap(
            SDAI_HYPERDRIVE,
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(WETH, LOW_FEE_TIER, SDAI),
                    recipient: address(zap),
                    deadline: block.timestamp + 1 minutes,
                    amountIn: 0.3882e18,
                    amountOutMinimum: 886e18
                }),
                sourceAsset: ETH,
                sourceAmount: 0.3882e18,
                shouldWrap: true,
                isRebasing: false
            }),
            10e18, // most of this should be refunded
            false // as base
        );
    }

    /// @notice Ensure that zapping into `addLiquidity` with base succeeds with
    ///         a rebasing yield source.
    function test_addLiquidityZap_success_rebasing_asBase() external {
        // Ensure that adding liquidity with base using a zap from USDC to WETH
        // (and ultimately into ETH) is successful.
        _verifyAddLiquidityZap(
            STETH_HYPERDRIVE,
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(USDC, MEDIUM_FEE_TIER, WETH),
                    recipient: address(zap),
                    deadline: block.timestamp + 1 minutes,
                    amountIn: 1_000e6,
                    amountOutMinimum: 0.38e18
                }),
                sourceAsset: USDC,
                sourceAmount: 1_000e6,
                shouldWrap: false,
                isRebasing: true
            }),
            10e18, // this should be completely refunded
            true // as base
        );
    }

    /// @notice Ensure that zapping into `addLiquidity` with vault shares
    ///         succeeds with a rebasing yield source.
    function test_addLiquidityZap_success_rebasing_asShares() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // USDC to stETH is successful.
        _verifyAddLiquidityZap(
            STETH_HYPERDRIVE,
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
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
                sourceAsset: USDC,
                sourceAmount: 1_000e6,
                shouldWrap: false,
                isRebasing: true
            }),
            0,
            false // as base
        );
    }

    /// @notice Ensure that zapping into `addLiquidity` with base succeeds with
    ///         a non-rebasing yield source.
    function test_addLiquidityZap_success_nonRebasing_asBase() external {
        // Ensure that adding liquidity with base using a zap from USDC to DAI
        // is successful.
        _verifyAddLiquidityZap(
            SDAI_HYPERDRIVE,
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(USDC, LOWEST_FEE_TIER, DAI),
                    recipient: address(zap),
                    deadline: block.timestamp + 1 minutes,
                    amountIn: 1_000e6,
                    amountOutMinimum: 999e18
                }),
                sourceAsset: USDC,
                sourceAmount: 1_000e6,
                shouldWrap: false,
                isRebasing: false
            }),
            0,
            true // as base
        );
    }

    /// @notice Ensure that zapping into `addLiquidity` with vault shares
    ///         succeeds with a non-rebasing yield source.
    function test_addLiquidityZap_success_nonRebasing_asShares() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // USDC to sDAI is successful.
        _verifyAddLiquidityZap(
            SDAI_HYPERDRIVE,
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
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
                }),
                sourceAsset: USDC,
                sourceAmount: 1_000e6,
                shouldWrap: false,
                isRebasing: false
            }),
            10e18, // this should be completely refunded
            false // as base
        );
    }

    /// @notice Ensure that zapping into `addLiquidity` with base succeeds when
    ///         the input needs to be wrapped.
    function test_addLiquidityZap_success_shouldWrap_asBase() external {
        _verifyAddLiquidityZap(
            SDAI_HYPERDRIVE,
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(
                        WSTETH,
                        LOWEST_FEE_TIER,
                        WETH,
                        LOW_FEE_TIER,
                        DAI
                    ),
                    recipient: address(zap),
                    deadline: block.timestamp + 1 minutes,
                    amountIn: 0.2534e18,
                    amountOutMinimum: 771e18
                }),
                sourceAsset: STETH,
                sourceAmount: 0.3e18,
                shouldWrap: true,
                isRebasing: false
            }),
            10e18, // this should be completely refunded
            true // as base
        );
    }

    /// @notice Ensure that zapping into `addLiquidity` with vault shares
    ///         succeeds when the input needs to be wrapped.
    function test_addLiquidityZap_success_shouldWrap_asShares() external {
        _verifyAddLiquidityZap(
            SDAI_HYPERDRIVE,
            IUniV3Zap.ZapInOptions({
                swapParams: ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(
                        WSTETH,
                        LOWEST_FEE_TIER,
                        WETH,
                        LOW_FEE_TIER,
                        SDAI
                    ),
                    recipient: address(zap),
                    deadline: block.timestamp + 1 minutes,
                    amountIn: 0.2534e18,
                    amountOutMinimum: 691e18
                }),
                sourceAsset: STETH,
                sourceAmount: 0.3e18,
                shouldWrap: true,
                isRebasing: false
            }),
            10e18, // this should be completely refunded
            false // as shares
        );
    }

    /// @dev Verify that `addLiquidityZap` performs correctly under the
    ///      specified conditions.
    /// @param _hyperdrive The Hyperdrive instance.
    /// @param _zapInOptions The options for the zap.
    /// @param _value The ETH value to send in the transaction.
    /// @param _asBase A flag indicating whether or not the deposit should be in
    ///        base.
    function _verifyAddLiquidityZap(
        IHyperdrive _hyperdrive,
        IUniV3Zap.ZapInOptions memory _zapInOptions,
        uint256 _value,
        bool _asBase
    ) internal {
        // Gets some data about the trader and the pool before the zap.
        bool isETHInput = _zapInOptions.swapParams.path.tokenIn() == WETH &&
            _value > _zapInOptions.swapParams.amountIn;
        uint256 aliceBalanceBefore;
        if (isETHInput) {
            aliceBalanceBefore = alice.balance;
        } else {
            aliceBalanceBefore = IERC20(_zapInOptions.sourceAsset).balanceOf(
                alice
            );
        }
        uint256 hyperdriveVaultSharesBalanceBefore = IERC20(
            _hyperdrive.vaultSharesToken()
        ).balanceOf(address(_hyperdrive));
        uint256 lpTotalSupplyBefore = _hyperdrive.getPoolInfo().lpTotalSupply;
        uint256 lpSharesBefore = _hyperdrive.balanceOf(
            AssetId._LP_ASSET_ID,
            alice
        );

        // Zap into `addLiquidity`.
        IHyperdrive hyperdrive_ = _hyperdrive; // avoid stack-too-deep
        IUniV3Zap.ZapInOptions memory zapInOptions = _zapInOptions; // avoid stack-too-deep
        bool asBase = _asBase; // avoid stack-too-deep
        uint256 lpShares = zap.addLiquidityZap{ value: _value }(
            _hyperdrive,
            0, // minimum LP share price
            0, // minimum APR
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: alice,
                asBase: asBase,
                extraData: ""
            }),
            zapInOptions
        );

        // Ensure that Alice was charged the correct amount of the input token.
        if (isETHInput) {
            assertEq(
                alice.balance,
                aliceBalanceBefore - zapInOptions.sourceAmount
            );
        } else {
            assertEq(
                IERC20(_zapInOptions.sourceAsset).balanceOf(alice),
                aliceBalanceBefore - zapInOptions.sourceAmount
            );
        }

        // Ensure that Hyperdrive received more than the minimum output of the
        // swap.
        uint256 hyperdriveVaultSharesBalanceAfter = IERC20(
            hyperdrive_.vaultSharesToken()
        ).balanceOf(address(hyperdrive_));
        if (zapInOptions.isRebasing) {
            // NOTE: Since the vault shares rebase, the units are in base.
            assertGt(
                hyperdriveVaultSharesBalanceAfter,
                hyperdriveVaultSharesBalanceBefore +
                    zapInOptions.swapParams.amountOutMinimum
            );
        } else if (_asBase) {
            // NOTE: Since the vault shares don't rebase, the units are in shares.
            assertGt(
                hyperdriveVaultSharesBalanceAfter,
                hyperdriveVaultSharesBalanceBefore +
                    _convertToShares(
                        hyperdrive_,
                        zapInOptions.swapParams.amountOutMinimum
                    )
            );
        } else {
            // NOTE: Since the vault shares don't rebase, the units are in shares.
            assertGt(
                hyperdriveVaultSharesBalanceAfter,
                hyperdriveVaultSharesBalanceBefore +
                    zapInOptions.swapParams.amountOutMinimum
            );
        }

        // Ensure that Alice received an appropriate amount of LP shares and
        // that the LP total supply increased.
        if (zapInOptions.isRebasing) {
            if (asBase) {
                assertGt(
                    lpShares,
                    zapInOptions.swapParams.amountOutMinimum.divDown(
                        hyperdrive_.getPoolInfo().lpSharePrice
                    )
                );
            } else {
                assertGt(
                    lpShares,
                    zapInOptions.swapParams.amountOutMinimum.divDown(
                        hyperdrive_.getPoolInfo().lpSharePrice
                    )
                );
            }
        } else {
            if (asBase) {
                assertGt(
                    lpShares,
                    zapInOptions.swapParams.amountOutMinimum.divDown(
                        hyperdrive_.getPoolInfo().lpSharePrice
                    )
                );
            } else {
                assertGt(
                    lpShares,
                    _convertToBase(
                        hyperdrive_,
                        zapInOptions.swapParams.amountOutMinimum
                    ).divDown(hyperdrive_.getPoolInfo().lpSharePrice)
                );
            }
        }
        assertEq(
            hyperdrive_.balanceOf(AssetId._LP_ASSET_ID, alice),
            lpSharesBefore + lpShares
        );
        assertEq(
            hyperdrive_.getPoolInfo().lpTotalSupply,
            lpTotalSupplyBefore + lpShares
        );
    }
}
