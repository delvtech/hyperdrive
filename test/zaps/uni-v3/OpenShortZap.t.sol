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

contract OpenShortZapTest is UniV3ZapTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using UniV3Path for bytes;

    /// @notice Ensure that zapping into `openShort` will fail when the
    ///         recipient isn't the zap contract.
    function test_openShortZap_failure_invalidRecipient() external {
        vm.expectRevert(IUniV3Zap.InvalidRecipient.selector);
        zap.openShortZap(
            SDAI_HYPERDRIVE,
            3_000e18, // bond amount
            type(uint256).max, // maximum deposit
            0, // minimum vault share price
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

    /// @notice Ensure that zapping into `openShort` will fail when the
    ///         input and output tokens are the same.
    function test_openShortZap_failure_invalidSwap() external {
        vm.expectRevert(IUniV3Zap.InvalidSwap.selector);
        zap.openShortZap(
            SDAI_HYPERDRIVE,
            3_000e18, // bond amount
            type(uint256).max, // maximum deposit
            0, // minimum vault share price
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

    /// @notice Ensure that zapping into `openShort` with base will fail when
    ///         the output isn't the base token.
    function test_openShortZap_failure_invalidOutputToken_asBase() external {
        vm.expectRevert(IUniV3Zap.InvalidOutputToken.selector);
        zap.openShortZap(
            SDAI_HYPERDRIVE,
            3_000e18, // bond amount
            type(uint256).max, // maximum deposit
            0, // minimum vault share price
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

    /// @notice Ensure that zapping into `openShort` with vault shares will
    ///         fail when the output isn't the vault shares token.
    function test_openShortZap_failure_invalidOutputToken_asShares() external {
        vm.expectRevert(IUniV3Zap.InvalidOutputToken.selector);
        zap.openShortZap(
            SDAI_HYPERDRIVE,
            3_000e18, // bond amount
            type(uint256).max, // maximum deposit
            0, // minimum vault share price
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

    /// @notice Ensure that zapping into `openShort` with base refunds the
    ///         sender when they send ETH that can't be used for the zap.
    function test_openShortZap_success_asBase_refund() external {
        // Get Alice's ether balance before the zap.
        uint256 aliceBalanceBefore = alice.balance;

        // Zaps into `addLiquidity` with `asBase` as `true` from USDC to DAI.
        zap.openShortZap{ value: 100e18 }(
            SDAI_HYPERDRIVE,
            3_000e18, // bond amount
            type(uint256).max, // maximum deposit
            0, // minimum vault share price
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

    /// @notice Ensure that zapping into `openShort` with vault shares
    ///         refunds the sender when they send ETH that can't be used for the
    ///         zap.
    function test_openShortZap_success_asShares_refund() external {
        // Get Alice's ether balance before the zap.
        uint256 aliceBalanceBefore = alice.balance;

        // Zaps into `addLiquidity` with `asBase` as `false` from USDC to sDAI.
        zap.openShortZap{ value: 100e18 }(
            SDAI_HYPERDRIVE,
            3_000e18, // bond amount
            type(uint256).max, // maximum deposit
            0, // minimum vault share price
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
    function test_openShortZap_success_asBase_withWETH() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // ETH (via WETH) to DAI is successful.
        _verifyOpenShortZap(
            SDAI_HYPERDRIVE,
            3_000e18, // bond amount
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
    function test_openShortZap_success_asShares_withWETH() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // ETH (via WETH) to sDAI is successful.
        _verifyOpenShortZap(
            SDAI_HYPERDRIVE,
            3_000e18, // bond amount
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
    function test_openShortZap_success_asBase_withETH() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // ETH (via WETH) to DAI is successful.
        _verifyOpenShortZap(
            SDAI_HYPERDRIVE,
            3_000e18, // bond amount
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
    function test_openShortZap_success_asShares_withETH() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // ETH (via WETH) to sDAI is successful.
        _verifyOpenShortZap(
            SDAI_HYPERDRIVE,
            3_000e18, // bond amount
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

    /// @notice Ensure that zapping into `openShort` with base succeeds with
    ///         a rebasing yield source.
    function test_openShortZap_success_rebasing_asBase() external {
        // Ensure that adding liquidity with base using a zap from USDC to WETH
        // (and ultimately into ETH) is successful.
        _verifyOpenShortZap(
            STETH_HYPERDRIVE,
            1e18, // bond amount
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

    /// @notice Ensure that zapping into `openShort` with vault shares
    ///         succeeds with a rebasing yield source.
    function test_openShortZap_success_rebasing_asShares() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // USDC to stETH is successful.
        _verifyOpenShortZap(
            STETH_HYPERDRIVE,
            1e18, // bond amount
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

    /// @notice Ensure that zapping into `openShort` with base succeeds with
    ///         a non-rebasing yield source.
    function test_openShortZap_success_nonRebasing_asBase() external {
        // Ensure that adding liquidity with base using a zap from USDC to DAI
        // is successful.
        _verifyOpenShortZap(
            SDAI_HYPERDRIVE,
            3_000e18, // bond amount
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

    /// @notice Ensure that zapping into `openShort` with vault shares
    ///         succeeds with a non-rebasing yield source.
    function test_openShortZap_success_nonRebasing_asShares() external {
        // Ensure that adding liquidity with vault shares using a zap from
        // USDC to sDAI is successful.
        _verifyOpenShortZap(
            SDAI_HYPERDRIVE,
            3_000e18, // bond amount
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

    /// @notice Ensure that zapping into `openShort` with base succeeds when
    ///         the input needs to be wrapped.
    function test_openShortZap_success_shouldWrap_asBase() external {
        _verifyOpenShortZap(
            SDAI_HYPERDRIVE,
            3_000e18, // bond amount
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

    /// @notice Ensure that zapping into `openShort` with vault shares
    ///         succeeds when the input needs to be wrapped.
    function test_openShortZap_success_shouldWrap_asShares() external {
        _verifyOpenShortZap(
            SDAI_HYPERDRIVE,
            3_000e18, // bond amount
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

    struct VerifyOpenShortParams {
        /// @dev A flag indicating whether or not the swap input is in ETH.
        bool isETHInput;
        /// @dev A flag indicating whether or not the swap output is in ETH.
        bool isETHOutput;
        /// @dev Alice's balance of the swap input before the zap.
        uint256 aliceInputBalanceBefore;
        /// @dev Alice's balance of the swap output before the zap.
        uint256 aliceOutputBalanceBefore;
        /// @dev Alice's balance of shorts in this checkpoint before the zap.
        uint256 aliceShortBalanceBefore;
        /// @dev Hyperdrive's vault shares balance before the zap.
        uint256 hyperdriveVaultSharesBalanceBefore;
        /// @dev The amount of shorts outstanding before the zap.
        uint256 shortsOutstandingBefore;
        /// @dev The spot price before the zap.
        uint256 spotPriceBefore;
    }

    /// @dev Verify that `openShortZap` performs correctly under the
    ///      specified conditions.
    /// @param _hyperdrive The Hyperdrive instance.
    /// @param _bondAmount The amount of bonds to short.
    /// @param _zapInOptions The options for the zap.
    /// @param _value The ETH value to send in the transaction.
    /// @param _asBase A flag indicating whether or not the deposit should be in
    ///        base.
    function _verifyOpenShortZap(
        IHyperdrive _hyperdrive,
        uint256 _bondAmount,
        IUniV3Zap.ZapInOptions memory _zapInOptions,
        uint256 _value,
        bool _asBase
    ) internal {
        // Gets some data about the trader and the pool before the zap.
        VerifyOpenShortParams memory params;
        params.isETHInput =
            _zapInOptions.swapParams.path.tokenIn() == WETH &&
            _value > _zapInOptions.swapParams.amountIn;
        if (params.isETHInput) {
            params.aliceInputBalanceBefore = alice.balance;
        } else {
            params.aliceInputBalanceBefore = IERC20(_zapInOptions.sourceAsset)
                .balanceOf(alice);
        }
        params.isETHOutput = _asBase && _hyperdrive.baseToken() == ETH;
        if (params.isETHOutput) {
            params.aliceOutputBalanceBefore = alice.balance;
        } else {
            params.aliceOutputBalanceBefore = IERC20(
                _zapInOptions.swapParams.path.tokenOut()
            ).balanceOf(alice);
        }
        params.aliceShortBalanceBefore = _hyperdrive.balanceOf(
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Short,
                hyperdrive.latestCheckpoint() + POSITION_DURATION
            ),
            alice
        );
        params.hyperdriveVaultSharesBalanceBefore = IERC20(
            _hyperdrive.vaultSharesToken()
        ).balanceOf(address(_hyperdrive));
        params.shortsOutstandingBefore = _hyperdrive
            .getPoolInfo()
            .shortsOutstanding;
        params.spotPriceBefore = _hyperdrive.calculateSpotPrice();

        // Zap into `openShort`.
        (uint256 maturityTime, uint256 deposit) = zap.openShortZap{
            value: _value
        }(
            _hyperdrive,
            _bondAmount,
            type(uint256).max, // maximum deposit
            0, // minimum vault share price
            IHyperdrive.Options({
                destination: alice,
                asBase: _asBase,
                extraData: ""
            }),
            _zapInOptions
        );

        // Ensure that the maturity time is the latest checkpoint.
        assertEq(
            maturityTime,
            _hyperdrive.latestCheckpoint() +
                _hyperdrive.getPoolConfig().positionDuration
        );

        // Ensure that Alice was charged the correct amount of the input token.
        if (params.isETHInput) {
            assertEq(
                alice.balance,
                params.aliceInputBalanceBefore - _zapInOptions.sourceAmount
            );
        } else {
            assertEq(
                IERC20(_zapInOptions.sourceAsset).balanceOf(alice),
                params.aliceInputBalanceBefore - _zapInOptions.sourceAmount
            );
        }

        // Ensure that Alice was refunded any of the output token that wasn't
        // used.
        if (params.isETHOutput) {
            assertGt(
                alice.balance,
                params.aliceOutputBalanceBefore +
                    (_zapInOptions.swapParams.amountOutMinimum - deposit)
            );
        } else {
            assertGt(
                IERC20(_zapInOptions.swapParams.path.tokenOut()).balanceOf(
                    alice
                ),
                params.aliceOutputBalanceBefore +
                    (_zapInOptions.swapParams.amountOutMinimum - deposit)
            );
        }

        // Ensure that Hyperdrive received the deposit.
        uint256 hyperdriveVaultSharesBalanceAfter = IERC20(
            _hyperdrive.vaultSharesToken()
        ).balanceOf(address(_hyperdrive));
        if (_zapInOptions.isRebasing) {
            if (_asBase) {
                // NOTE: Since the vault shares rebase, the units are in base.
                assertEq(
                    hyperdriveVaultSharesBalanceAfter,
                    params.hyperdriveVaultSharesBalanceBefore + deposit
                );
            } else {
                assertApproxEqAbs(
                    hyperdriveVaultSharesBalanceAfter,
                    params.hyperdriveVaultSharesBalanceBefore +
                        _convertToBase(_hyperdrive, deposit),
                    1
                );
            }
        } else {
            if (_asBase) {
                // NOTE: Since the vault shares don't rebase, the units are in shares.
                assertApproxEqAbs(
                    hyperdriveVaultSharesBalanceAfter,
                    params.hyperdriveVaultSharesBalanceBefore +
                        _convertToShares(_hyperdrive, deposit),
                    1
                );
            } else {
                // NOTE: Since the vault shares don't rebase, the units are in shares.
                assertEq(
                    hyperdriveVaultSharesBalanceAfter,
                    params.hyperdriveVaultSharesBalanceBefore + deposit
                );
            }
        }

        // Ensure that Alice received an appropriate amount of LP shares and
        // that the LP total supply increased.
        if (_zapInOptions.isRebasing) {
            if (_asBase) {
                assertLt(deposit.divDown(_bondAmount), params.spotPriceBefore);
            } else {
                assertLt(deposit.divDown(_bondAmount), params.spotPriceBefore);
            }
        } else {
            if (_asBase) {
                assertLt(deposit.divDown(_bondAmount), params.spotPriceBefore);
            } else {
                assertLt(
                    _convertToBase(_hyperdrive, deposit).divDown(_bondAmount),
                    params.spotPriceBefore
                );
            }
        }
        assertEq(
            _hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                alice
            ),
            params.aliceShortBalanceBefore + _bondAmount
        );
        assertEq(
            _hyperdrive.getPoolInfo().shortsOutstanding,
            params.shortsOutstandingBefore + _bondAmount
        );
    }
}
