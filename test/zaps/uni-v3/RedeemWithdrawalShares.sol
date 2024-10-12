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

contract RedeemWithdrawalSharesZapTest is UniV3ZapTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using UniV3Path for bytes;

    /// @dev The withdrawal shares in the sDAI pool.
    uint256 internal withdrawalSharesSDAI;

    /// @dev The withdrawal shares in the rETH pool.
    uint256 internal withdrawalSharesRETH;

    /// @dev The withdrawal shares in the stETH pool.
    uint256 internal withdrawalSharesStETH;

    /// @dev The withdrawal shares in the WETH pool.
    uint256 internal withdrawalSharesWETHVault;

    /// Set Up ///

    /// @notice Prepare each of the Hyperdrive markets with withdrawal shares.
    function setUp() public override {
        // Sets up the underlying test infrastructure.
        super.setUp();

        // Prepare the sDAI, rETH, stETH, and WETH vault Hyperdrive markets.
        withdrawalSharesSDAI = _prepareHyperdrive(
            SDAI_HYPERDRIVE,
            500e18,
            true
        );
        withdrawalSharesRETH = _prepareHyperdrive(RETH_HYPERDRIVE, 1e18, false);
        withdrawalSharesStETH = _prepareHyperdrive(
            STETH_HYPERDRIVE,
            1e18,
            false
        );
        withdrawalSharesWETHVault = _prepareHyperdrive(
            WETH_VAULT_HYPERDRIVE,
            1e18,
            true
        );
    }

    /// @dev Prepares the Hyperdrive instance for the redeem withdrawal shares
    ///      tests.
    /// @param _hyperdrive The Hyperdrive instance.
    /// @param _contribution The contribution amount.
    /// @param _asBase A flag indicating whether or not the contribution is in
    ///        base or vault shares.
    /// @return The amount of LP shares procured.
    function _prepareHyperdrive(
        IHyperdrive _hyperdrive,
        uint256 _contribution,
        bool _asBase
    ) internal returns (uint256) {
        // If we're adding liquidity with the base token, approve Hyperdrive to
        // spend base tokens.
        if (_asBase) {
            IERC20(_hyperdrive.baseToken()).approve(
                address(_hyperdrive),
                type(uint256).max
            );
        }
        // Otherwise, approve Hyperdrive to spend vault shares.
        else {
            IERC20(_hyperdrive.vaultSharesToken()).approve(
                address(_hyperdrive),
                type(uint256).max
            );
        }

        // Add liquidity to the Hyperdrive pool.
        uint256 lpShares = _hyperdrive.addLiquidity(
            _contribution,
            0,
            0,
            type(uint256).max,
            IHyperdrive.Options({
                destination: alice,
                asBase: _asBase,
                extraData: new bytes(0)
            })
        );

        // Alice opens a large short.
        uint256 shortAmount = _hyperdrive.calculateMaxShort() -
            _hyperdrive.getPoolConfig().minimumTransactionAmount;
        (uint256 maturityTime, ) = _hyperdrive.openShort(
            shortAmount,
            type(uint256).max,
            0,
            IHyperdrive.Options({
                destination: alice,
                asBase: _asBase,
                extraData: new bytes(0)
            })
        );

        // Alice removes her liquidity. We ensure that she received some
        // withdrawal shares.
        (, uint256 withdrawalShares) = _hyperdrive.removeLiquidity(
            lpShares,
            0,
            IHyperdrive.Options({
                destination: alice,
                asBase: _asBase,
                extraData: new bytes(0)
            })
        );
        assertGt(withdrawalShares, 0);

        // Advance to maturity and mint a chcekpoint. Ensure that the withdrawal
        // shares are paid out now that the short is closed.
        vm.warp(maturityTime);
        _hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);
        assertEq(
            _hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw,
            withdrawalShares
        );

        // Set an approval on the zap to spend the LP shares.
        _hyperdrive.setApproval(
            AssetId._WITHDRAWAL_SHARE_ASSET_ID,
            address(zap),
            withdrawalShares
        );

        return withdrawalShares;
    }

    /// Tests ///

    /// @notice Ensure that zapping out of `redeemWithdrawalShares` will fail when the
    ///         recipient of `redeemWithdrawalShares` isn't the zap contract.
    function test_redeemWithdrawalSharesZap_failure_invalidRecipient()
        external
    {
        vm.expectRevert(IUniV3Zap.InvalidRecipient.selector);
        zap.redeemWithdrawalSharesZap(
            SDAI_HYPERDRIVE,
            withdrawalSharesSDAI, // lp shares
            0, // minimum output per share
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
            }),
            false // should wrap
        );
    }

    /// @notice Ensure that zapping out of `redeemWithdrawalShares` will fail
    ///         when the recipient of `redeemWithdrawalShares` isn't the zap
    ///         contract.
    function test_redeemWithdrawalSharesZap_failure_invalidSwap() external {
        vm.expectRevert(IUniV3Zap.InvalidSwap.selector);
        zap.redeemWithdrawalSharesZap(
            SDAI_HYPERDRIVE,
            withdrawalSharesSDAI, // lp shares
            0, // minimum output per share
            IHyperdrive.Options({
                destination: address(zap),
                asBase: true,
                extraData: ""
            }),
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(DAI, LOWEST_FEE_TIER, DAI),
                recipient: bob,
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e18,
                amountOutMinimum: 999e18
            }),
            false // should wrap
        );
    }

    /// @notice Ensure that zapping out of `redeemWithdrawalShares` with base will fail
    ///         when the input isn't the base token.
    function test_redeemWithdrawalSharesZap_failure_invalidInputToken_asBase()
        external
    {
        vm.expectRevert(IUniV3Zap.InvalidInputToken.selector);
        zap.redeemWithdrawalSharesZap(
            SDAI_HYPERDRIVE,
            withdrawalSharesSDAI, // lp shares
            0, // minimum output per share
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
            }),
            false // should wrap
        );
    }

    /// @notice Ensure that zapping out of `redeemWithdrawalShares` with vault shares
    ///         will fail when the input isn't the vault shares token.
    function test_redeemWithdrawalSharesZap_failure_invalidInputToken_asShares()
        external
    {
        vm.expectRevert(IUniV3Zap.InvalidInputToken.selector);
        zap.redeemWithdrawalSharesZap(
            SDAI_HYPERDRIVE,
            withdrawalSharesSDAI, // lp shares
            0, // minimum output per share
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
            }),
            false // should wrap
        );
    }

    /// @notice Ensure that zapping out of `redeemWithdrawalShares` with base will
    ///         succeed when the base token is WETH. This ensures that WETH is
    ///         handled properly despite the zap unwrapping WETH into ETH in
    ///         some cases.
    function test_redeemWithdrawalSharesZap_success_asBase_withWETH() external {
        _verifyRedeemWithdrawalSharesZap(
            WETH_VAULT_HYPERDRIVE,
            withdrawalSharesWETHVault, // lp shares
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(WETH, LOW_FEE_TIER, DAI),
                recipient: alice,
                deadline: block.timestamp + 1 minutes,
                // NOTE: The amount in is smaller than the proceeds will be.
                // This will automatically be adjusted up.
                amountIn: 0.3882e18,
                amountOutMinimum: 999e18
            }),
            false, // should wrap
            true // as base
        );
    }

    /// @notice Ensure that zapping out of `redeemWithdrawalShares` with base will
    ///         succeed when the yield source is rebasing and when the input is
    ///         the base token.
    /// @dev This also tests using ETH as the output assets and verifies that
    ///      we can properly convert to WETH.
    function test_redeemWithdrawalSharesZap_success_rebasing_asBase() external {
        _verifyRedeemWithdrawalSharesZap(
            RETH_HYPERDRIVE,
            withdrawalSharesRETH, // lp shares
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(WETH, LOW_FEE_TIER, DAI),
                recipient: alice,
                deadline: block.timestamp + 1 minutes,
                // NOTE: The amount in is smaller than the proceeds will be.
                // This will automatically be adjusted up.
                amountIn: 0.3882e18,
                amountOutMinimum: 999e18
            }),
            true, // should wrap
            true // as base
        );
    }

    /// @notice Ensure that zapping out of `redeemWithdrawalShares` with vault shares
    ///         will succeed when the yield source is rebasing and when the
    ///         input is the vault shares token.
    function test_redeemWithdrawalSharesZap_success_rebasing_asShares()
        external
    {
        _verifyRedeemWithdrawalSharesZap(
            STETH_HYPERDRIVE,
            withdrawalSharesStETH, // lp shares
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(
                    WSTETH,
                    LOWEST_FEE_TIER,
                    WETH,
                    LOW_FEE_TIER,
                    USDC
                ),
                recipient: alice,
                deadline: block.timestamp + 1 minutes,
                // NOTE: The amount in is smaller than the proceeds will be.
                // This will automatically be adjusted up.
                amountIn: 0.32796e18,
                amountOutMinimum: 950e6
            }),
            true, // should wrap
            false // as base
        );
    }

    /// @notice Ensure that zapping out of `redeemWithdrawalShares` with base will
    ///         succeed when the yield source is non-rebasing and when the input is
    ///         the base token.
    function test_redeemWithdrawalSharesZap_success_nonRebasing_asBase()
        external
    {
        _verifyRedeemWithdrawalSharesZap(
            SDAI_HYPERDRIVE,
            withdrawalSharesSDAI, // lp shares
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(DAI, LOW_FEE_TIER, WETH),
                recipient: alice,
                deadline: block.timestamp + 1 minutes,
                // NOTE: The amount in is larger than the proceeds will be.
                // This will automatically be adjusted down.
                amountIn: 1_000e18,
                amountOutMinimum: 0.38e18
            }),
            false, // should wrap
            true // as base
        );
    }

    /// @notice Ensure that zapping out of `redeemWithdrawalShares` with vault shares
    ///         will succeed when the yield source is non-rebasing and when the
    ///         input is the vault shares token.
    function test_redeemWithdrawalSharesZap_success_nonRebasing_asShares()
        external
    {
        _verifyRedeemWithdrawalSharesZap(
            SDAI_HYPERDRIVE,
            withdrawalSharesSDAI, // lp shares
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(
                    SDAI,
                    LOW_FEE_TIER,
                    WETH,
                    LOW_FEE_TIER,
                    USDC
                ),
                recipient: alice,
                deadline: block.timestamp + 1 minutes,
                // NOTE: The amount in is larger than the proceeds will be.
                // This will automatically be adjusted down.
                amountIn: 885e18,
                amountOutMinimum: 900e6
            }),
            false, // should wrap
            false // as base
        );
    }

    /// @dev Verify that `redeemWithdrawalSharesZap` performs correctly under the
    ///      specified conditions.
    /// @param _hyperdrive The Hyperdrive instance.
    /// @param _withdrawalShares The amount of withdrawal shares to remove.
    /// @param _swapParams The Uniswap multi-hop swap parameters.
    /// @param _shouldWrap A flag indicating whether or not the proceeds should
    ///        be wrapped before the swap.
    /// @param _asBase A flag indicating whether or not the deposit should be in
    ///        base.
    function _verifyRedeemWithdrawalSharesZap(
        IHyperdrive _hyperdrive,
        uint256 _withdrawalShares,
        ISwapRouter.ExactInputParams memory _swapParams,
        bool _shouldWrap,
        bool _asBase
    ) internal {
        // Simulate closing the position without using the zap.
        uint256 expectedHyperdriveVaultSharesBalanceAfter;
        uint256 expectedWithdrawalSharesRedeemed;
        {
            uint256 snapshotId = vm.snapshot();
            (, expectedWithdrawalSharesRedeemed) = _hyperdrive
                .redeemWithdrawalShares(
                    _withdrawalShares,
                    0, // min output per shares
                    IHyperdrive.Options({
                        destination: alice,
                        asBase: _asBase,
                        extraData: new bytes(0)
                    })
                );
            expectedHyperdriveVaultSharesBalanceAfter = IERC20(
                _hyperdrive.vaultSharesToken()
            ).balanceOf(address(_hyperdrive));
            vm.revertTo(snapshotId);
        }

        // Get some data before executing the zap.
        uint256 withdrawalSharesReadyToWithdrawBefore = _hyperdrive
            .getPoolInfo()
            .withdrawalSharesReadyToWithdraw;
        uint256 aliceOutputBalanceBefore;
        address tokenOut = _swapParams.path.tokenOut();
        if (tokenOut == WETH) {
            aliceOutputBalanceBefore = alice.balance;
        } else {
            aliceOutputBalanceBefore = IERC20(tokenOut).balanceOf(alice);
        }
        uint256 aliceWithdrawalSharesBefore = _hyperdrive.balanceOf(
            AssetId._WITHDRAWAL_SHARE_ASSET_ID,
            alice
        );

        // Execute the zap.
        IHyperdrive hyperdrive = _hyperdrive; // avoid stack-too-deep
        uint256 withdrawalShares = _withdrawalShares; // avoid stack-too-deep
        ISwapRouter.ExactInputParams memory swapParams = _swapParams; // avoid stack-too-deep
        bool shouldWrap = _shouldWrap; // avoid stack-too-deep
        bool asBase = _asBase; // avoid stack-too-deep
        (uint256 proceeds, uint256 withdrawalSharesRedeemed) = zap
            .redeemWithdrawalSharesZap(
                hyperdrive,
                withdrawalShares, // withdrawal shares
                0, // minimum output per share
                IHyperdrive.Options({
                    destination: address(zap),
                    asBase: asBase,
                    extraData: ""
                }),
                swapParams,
                shouldWrap
            );

        // Ensure that Alice received the expected proceeds.
        if (tokenOut == WETH) {
            assertEq(alice.balance, aliceOutputBalanceBefore + proceeds);
        } else {
            assertEq(
                IERC20(tokenOut).balanceOf(alice),
                aliceOutputBalanceBefore + proceeds
            );
        }

        // Ensure that the withdrawal shares redeemed were equal to the expected
        // withdrawal shares redeemed.
        assertEq(withdrawalSharesRedeemed, expectedWithdrawalSharesRedeemed);

        // Ensure that the vault shares balance is what we would predict from
        // the simulation.
        assertEq(
            IERC20(hyperdrive.vaultSharesToken()).balanceOf(
                address(hyperdrive)
            ),
            expectedHyperdriveVaultSharesBalanceAfter
        );

        // Ensure that the withdrawal shares ready to withdraw and Alice's
        // balance of withdrawal shares decreased by the withdrawal shares
        // redeemed.
        assertEq(
            hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw,
            withdrawalSharesReadyToWithdrawBefore - withdrawalSharesRedeemed
        );
        assertEq(
            hyperdrive.balanceOf(AssetId._WITHDRAWAL_SHARE_ASSET_ID, alice),
            aliceWithdrawalSharesBefore - withdrawalSharesRedeemed
        );
    }
}
