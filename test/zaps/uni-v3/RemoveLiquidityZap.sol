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

    /// @dev The LP shares in the sDAI pool.
    uint256 internal lpSharesSDAI;

    /// @dev The LP shares in the rETH pool.
    uint256 internal lpSharesRETH;

    /// @dev The LP shares in the stETH pool.
    uint256 internal lpSharesStETH;

    /// @dev The LP shares in the WETH pool.
    uint256 internal lpSharesWETHVault;

    /// @notice Add liquidity in each of the markets so there are LP shares to
    ///         remove.
    function setUp() public override {
        // Sets up the underlying test infrastructure.
        super.setUp();

        // Add liquidity in the sDAI, rETH, stETH, and WETH vault Hyperdrive
        // markets.
        IERC20(DAI).approve(address(SDAI_HYPERDRIVE), type(uint256).max);
        lpSharesSDAI = SDAI_HYPERDRIVE.addLiquidity(
            500e18,
            0,
            0,
            type(uint256).max,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );
        SDAI_HYPERDRIVE.setApproval(
            AssetId._LP_ASSET_ID,
            address(zap),
            lpSharesSDAI
        );
        IERC20(RETH).approve(address(RETH_HYPERDRIVE), type(uint256).max);
        lpSharesRETH = RETH_HYPERDRIVE.addLiquidity(
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
        RETH_HYPERDRIVE.setApproval(
            AssetId._LP_ASSET_ID,
            address(zap),
            lpSharesRETH
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
        STETH_HYPERDRIVE.setApproval(
            AssetId._LP_ASSET_ID,
            address(zap),
            lpSharesStETH
        );
        IERC20(WETH).approve(address(WETH_VAULT_HYPERDRIVE), type(uint256).max);
        lpSharesWETHVault = WETH_VAULT_HYPERDRIVE.addLiquidity(
            1e18,
            0,
            0,
            type(uint256).max,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );
        WETH_VAULT_HYPERDRIVE.setApproval(
            AssetId._LP_ASSET_ID,
            address(zap),
            lpSharesWETHVault
        );
    }

    /// @notice Ensure that zapping out of `removeLiquidity` will fail when the
    ///         recipient of `removeLong` isn't the zap contract.
    function test_removeLiquidityZap_failure_invalidRecipient() external {
        // Ensure that the zap fails when the recipient isn't Hyperdrive.
        vm.expectRevert(IUniV3Zap.InvalidRecipient.selector);
        zap.removeLiquidityZap(
            SDAI_HYPERDRIVE,
            lpSharesSDAI, // lp shares
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
            0 // dust buffer
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
            lpSharesSDAI, // lp shares
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
            0 // dust buffer
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
            lpSharesSDAI, // lp shares
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
            0 // dust buffer
        );
    }

    /// @notice Ensure that zapping out of `removeLiquidity` with base will
    ///         succeed when the base token is WETH. This ensures that WETH is
    ///         handled properly despite the zap unwrapping WETH into ETH in
    ///         some cases.
    function test_removeLiquidityZap_success_asBase_withWETH() external {
        _verifyRemoveLiquidityZap(
            WETH_VAULT_HYPERDRIVE,
            lpSharesWETHVault, // lp shares
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(WETH, LOW_FEE_TIER, DAI),
                recipient: alice,
                deadline: block.timestamp + 1 minutes,
                // NOTE: The amount in is smaller than the proceeds will be.
                // This will automatically be adjusted up.
                amountIn: 0.3882e18,
                amountOutMinimum: 999e18
            }),
            0, // dust buffer
            true // as base
        );
    }

    /// @notice Ensure that zapping out of `removeLiquidity` with base will
    ///         succeed when the yield source is rebasing and when the input is
    ///         the base token.
    /// @dev This also tests using ETH as the output assets and verifies that
    ///      we can properly convert to WETH.
    function test_removeLiquidityZap_success_rebasing_asBase() external {
        _verifyRemoveLiquidityZap(
            RETH_HYPERDRIVE,
            lpSharesRETH, // lp shares
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(WETH, LOW_FEE_TIER, DAI),
                recipient: alice,
                deadline: block.timestamp + 1 minutes,
                // NOTE: The amount in is smaller than the proceeds will be.
                // This will automatically be adjusted up.
                amountIn: 0.3882e18,
                amountOutMinimum: 999e18
            }),
            0, // dust buffer
            true // as base
        );
    }

    /// @notice Ensure that zapping out of `removeLiquidity` with vault shares
    ///         will succeed when the yield source is rebasing and when the
    ///         input is the vault shares token.
    function test_removeLiquidityZap_success_rebasing_asShares() external {
        _verifyRemoveLiquidityZap(
            STETH_HYPERDRIVE,
            lpSharesStETH, // lp shares
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(
                    STETH,
                    HIGH_FEE_TIER,
                    WETH,
                    MEDIUM_FEE_TIER,
                    USDC
                ),
                recipient: alice,
                deadline: block.timestamp + 1 minutes,
                // NOTE: The amount in is smaller than the proceeds will be.
                // This will automatically be adjusted up.
                amountIn: 0.3882e18,
                amountOutMinimum: 0e6
            }),
            100, // dust buffer
            false // as base
        );
    }

    /// @notice Ensure that zapping out of `removeLiquidity` with base will
    ///         succeed when the yield source is non-rebasing and when the input is
    ///         the base token.
    function test_removeLiquidityZap_success_nonRebasing_asBase() external {
        _verifyRemoveLiquidityZap(
            SDAI_HYPERDRIVE,
            lpSharesSDAI, // lp shares
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(DAI, LOW_FEE_TIER, WETH),
                recipient: alice,
                deadline: block.timestamp + 1 minutes,
                // NOTE: The amount in is larger than the proceeds will be.
                // This will automatically be adjusted down.
                amountIn: 1_000e18,
                amountOutMinimum: 0.38e18
            }),
            0, // dust buffer
            true // as base
        );
    }

    /// @notice Ensure that zapping out of `removeLiquidity` with vault shares
    ///         will succeed when the yield source is non-rebasing and when the
    ///         input is the vault shares token.
    function test_removeLiquidityZap_success_nonRebasing_asShares() external {
        _verifyRemoveLiquidityZap(
            SDAI_HYPERDRIVE,
            lpSharesSDAI, // lp shares
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
            0, // dust buffer
            false // as base
        );
    }

    /// @dev Verify that `removeLiquidityZap` performs correctly under the
    ///      specified conditions.
    /// @param _hyperdrive The Hyperdrive instance.
    /// @param _lpShares The amount of LP shares to remove.
    /// @param _swapParams The Uniswap multi-hop swap parameters.
    /// @param _dustBuffer Some tokens (like stETH) have transfer methods that
    ///        are imprecise. This may result in token transfers sending less
    ///        funds than expected to Uniswap's swap router. To work around this
    ///        issue, a dust buffer can be specified that will reduce the input
    ///        amount of the swap to reduce the likelihood of failures.
    /// @param _asBase A flag indicating whether or not the deposit should be in
    ///        base.
    function _verifyRemoveLiquidityZap(
        IHyperdrive _hyperdrive,
        uint256 _lpShares,
        ISwapRouter.ExactInputParams memory _swapParams,
        uint256 _dustBuffer,
        bool _asBase
    ) internal {
        // Simulate closing the position without using the zap.
        uint256 expectedHyperdriveVaultSharesBalanceAfter;
        uint256 expectedWithdrawalShares;
        {
            uint256 snapshotId = vm.snapshot();
            (, expectedWithdrawalShares) = _hyperdrive.removeLiquidity(
                _lpShares,
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
        uint256 lpTotalSupplyBefore = _hyperdrive.getPoolInfo().lpTotalSupply;
        uint256 aliceOutputBalanceBefore;
        address tokenOut = _swapParams.path.tokenOut();
        if (tokenOut == WETH) {
            aliceOutputBalanceBefore = alice.balance;
        } else {
            aliceOutputBalanceBefore = IERC20(tokenOut).balanceOf(alice);
        }
        uint256 aliceLPSharesBefore = _hyperdrive.balanceOf(
            AssetId._LP_ASSET_ID,
            alice
        );
        uint256 aliceWithdrawalSharesBefore = _hyperdrive.balanceOf(
            AssetId._WITHDRAWAL_SHARE_ASSET_ID,
            alice
        );

        // Execute the zap.
        IHyperdrive hyperdrive = _hyperdrive; // avoid stack-too-deep
        uint256 lpShares = _lpShares; // avoid stack-too-deep
        ISwapRouter.ExactInputParams memory swapParams = _swapParams; // avoid stack-too-deep
        uint256 dustBuffer = _dustBuffer; // avoid stack-too-deep
        bool asBase = _asBase; // avoid stack-too-deep
        (uint256 proceeds, uint256 withdrawalShares) = zap.removeLiquidityZap(
            hyperdrive,
            lpShares, // lp shares
            0, // minimum output per share
            IHyperdrive.Options({
                destination: address(zap),
                asBase: asBase,
                extraData: ""
            }),
            swapParams,
            dustBuffer
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

        // Ensure that the withdrawal shares were equal to the expected
        // withdrawal shares.
        assertEq(withdrawalShares, expectedWithdrawalShares);

        // Ensure that the vault shares balance is what we would predict from
        // the simulation.
        assertEq(
            IERC20(hyperdrive.vaultSharesToken()).balanceOf(
                address(hyperdrive)
            ),
            expectedHyperdriveVaultSharesBalanceAfter
        );

        // Ensure that the LP total supply decreased by the LP shares minus the
        // number of withdrawal shares and that Alice's balance of LP shares
        // decreased by the LP shares.
        assertEq(
            hyperdrive.getPoolInfo().lpTotalSupply,
            lpTotalSupplyBefore - (lpShares - withdrawalShares)
        );
        assertEq(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            aliceLPSharesBefore - lpShares
        );
        assertEq(
            hyperdrive.balanceOf(AssetId._WITHDRAWAL_SHARE_ASSET_ID, alice),
            aliceWithdrawalSharesBefore - withdrawalShares
        );
    }
}
