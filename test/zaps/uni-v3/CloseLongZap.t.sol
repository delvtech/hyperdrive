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

contract CloseLongZapTest is UniV3ZapTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using UniV3Path for bytes;

    /// @dev The maturity time for the long position in the sDAI pool.
    uint256 internal maturityTimeSDAI;

    /// @dev The maturity time for the long position in the rETH pool.
    uint256 internal maturityTimeRETH;

    /// @dev The maturity time for the long position in the stETH pool.
    uint256 internal maturityTimeStETH;

    /// @dev The maturity time for the long position in the WETH pool.
    uint256 internal maturityTimeWETHVault;

    /// @dev The long amount in the sDAI pool.
    uint256 internal longAmountSDAI;

    /// @dev The long amount in the rETH pool.
    uint256 internal longAmountRETH;

    /// @dev The long amount in the stETH pool.
    uint256 internal longAmountStETH;

    /// @dev The long amount in the WETH pool.
    uint256 internal longAmountWETHVault;

    /// Set Up ///

    /// @notice Prepare long positions in each of the Hyperdrive markets.
    function setUp() public override {
        // Sets up the underlying test infrastructure.
        super.setUp();

        // Prepare the sDAI, rETH, stETH, and WETH vault Hyperdrive markets.
        (maturityTimeSDAI, longAmountSDAI) = _prepareHyperdrive(
            SDAI_HYPERDRIVE,
            500e18,
            true
        );
        (maturityTimeRETH, longAmountRETH) = _prepareHyperdrive(
            RETH_HYPERDRIVE,
            0.01e18,
            false
        );
        (maturityTimeStETH, longAmountStETH) = _prepareHyperdrive(
            STETH_HYPERDRIVE,
            0.01e18,
            false
        );
        (maturityTimeWETHVault, longAmountWETHVault) = _prepareHyperdrive(
            WETH_VAULT_HYPERDRIVE,
            0.01e18,
            true
        );
    }

    /// @dev Prepares the Hyperdrive instance for the close long tests.
    /// @param _hyperdrive The Hyperdrive instance.
    /// @param _amount The amount of base or vault shares to invest in long
    ///        positions.
    /// @param _asBase A flag indicating whether or not the contribution is in
    ///        base or vault shares.
    /// @return The maturity time of the long positions.
    /// @return The amount of long positions that were opened.
    function _prepareHyperdrive(
        IHyperdrive _hyperdrive,
        uint256 _amount,
        bool _asBase
    ) internal returns (uint256, uint256) {
        // If we're opening longs with the base token, approve Hyperdrive to
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

        // Add a large amount of liquidity to ensure that there is adequate
        // liquidity to open the long.
        _hyperdrive.addLiquidity(
            _amount.mulDown(1_000e18),
            0,
            0,
            type(uint256).max,
            IHyperdrive.Options({
                destination: alice,
                asBase: _asBase,
                extraData: new bytes(0)
            })
        );

        // Open longs in the Hyperdrive pool.
        (uint256 maturityTime, uint256 longAmount) = _hyperdrive.openLong(
            _amount,
            0,
            0,
            IHyperdrive.Options({
                destination: alice,
                asBase: _asBase,
                extraData: new bytes(0)
            })
        );

        // Set an approval on the zap to spend the long positions.
        _hyperdrive.setApproval(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            address(zap),
            longAmount
        );

        return (maturityTime, longAmount);
    }

    /// Tests ///

    /// @notice Ensure that zapping out of `closeLong` will fail when the
    ///         recipient of `closeLong` isn't the zap contract.
    function test_closeLongZap_failure_invalidRecipient() external {
        vm.expectRevert(IUniV3Zap.InvalidRecipient.selector);
        zap.closeLongZap(
            SDAI_HYPERDRIVE,
            maturityTimeSDAI, // maturity time
            longAmountSDAI, // long amount
            0, // min output
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

    /// @notice Ensure that zapping out of `closeLong` will fail when the
    ///         recipient of `closeLong` isn't the zap contract.
    function test_closeLongZap_failure_invalidSwap() external {
        vm.expectRevert(IUniV3Zap.InvalidSwap.selector);
        zap.closeLongZap(
            SDAI_HYPERDRIVE,
            maturityTimeSDAI, // maturity time
            longAmountSDAI, // long amount
            0, // min output
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

    /// @notice Ensure that zapping out of `closeLong` with base will fail
    ///         when the input isn't the base token.
    function test_closeLongZap_failure_invalidInputToken_asBase() external {
        vm.expectRevert(IUniV3Zap.InvalidInputToken.selector);
        zap.closeLongZap(
            SDAI_HYPERDRIVE,
            maturityTimeSDAI, // maturity time
            longAmountSDAI, // long amount
            0, // min output
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

    /// @notice Ensure that zapping out of `closeLong` with vault shares
    ///         will fail when the input isn't the vault shares token.
    function test_closeLongZap_failure_invalidInputToken_asShares() external {
        vm.expectRevert(IUniV3Zap.InvalidInputToken.selector);
        zap.closeLongZap(
            SDAI_HYPERDRIVE,
            maturityTimeSDAI, // maturity time
            longAmountSDAI, // long amount
            0, // min output
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

    /// @notice Ensure that zapping out of `closeLong` with base will
    ///         succeed when the base token is WETH. This ensures that WETH is
    ///         handled properly despite the zap unwrapping WETH into ETH in
    ///         some cases.
    function test_closeLongZap_success_asBase_withWETH() external {
        _verifyCloseLongZap(
            WETH_VAULT_HYPERDRIVE,
            maturityTimeWETHVault, // maturity time
            longAmountWETHVault, // long amount
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

    /// @notice Ensure that zapping out of `closeLong` with base will
    ///         succeed when the yield source is rebasing and when the input is
    ///         the base token.
    /// @dev This also tests using ETH as the output assets and verifies that
    ///      we can properly convert to WETH.
    function test_closeLongZap_success_rebasing_asBase() external {
        _verifyCloseLongZap(
            RETH_HYPERDRIVE,
            maturityTimeRETH, // maturity time
            longAmountRETH, // long amount
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

    /// @notice Ensure that zapping out of `closeLong` with vault shares
    ///         will succeed when the yield source is rebasing and when the
    ///         input is the vault shares token.
    function test_closeLongZap_success_rebasing_asShares() external {
        _verifyCloseLongZap(
            STETH_HYPERDRIVE,
            maturityTimeStETH, // maturity time
            longAmountStETH, // long amount
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

    /// @notice Ensure that zapping out of `closeLong` with base will
    ///         succeed when the yield source is non-rebasing and when the input is
    ///         the base token.
    function test_closeLongZap_success_nonRebasing_asBase() external {
        _verifyCloseLongZap(
            SDAI_HYPERDRIVE,
            maturityTimeSDAI, // maturity time
            longAmountSDAI, // long amount
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

    /// @notice Ensure that zapping out of `closeLong` with vault shares
    ///         will succeed when the yield source is non-rebasing and when the
    ///         input is the vault shares token.
    function test_closeLongZap_success_nonRebasing_asShares() external {
        _verifyCloseLongZap(
            SDAI_HYPERDRIVE,
            maturityTimeSDAI, // maturity time
            longAmountSDAI, // long amount
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

    /// @dev Verify that `closeLongZap` performs correctly under the
    ///      specified conditions.
    /// @param _hyperdrive The Hyperdrive instance.
    /// @param _maturityTime The maturity time of the long position.
    /// @param _bondAmount The amount of longs to close.
    /// @param _swapParams The Uniswap multi-hop swap parameters.
    /// @param _shouldWrap A flag indicating whether or not the proceeds should
    ///        be wrapped before the swap.
    /// @param _asBase A flag indicating whether or not the deposit should be in
    ///        base.
    function _verifyCloseLongZap(
        IHyperdrive _hyperdrive,
        uint256 _maturityTime,
        uint256 _bondAmount,
        ISwapRouter.ExactInputParams memory _swapParams,
        bool _shouldWrap,
        bool _asBase
    ) internal {
        // Simulate closing the position without using the zap.
        uint256 expectedHyperdriveVaultSharesBalanceAfter;
        {
            uint256 snapshotId = vm.snapshot();
            _hyperdrive.closeLong(
                _maturityTime,
                _bondAmount,
                0, // min output
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
        uint256 longsOutstandingBefore = _hyperdrive
            .getPoolInfo()
            .longsOutstanding;
        uint256 aliceOutputBalanceBefore;
        address tokenOut = _swapParams.path.tokenOut();
        if (tokenOut == WETH) {
            aliceOutputBalanceBefore = alice.balance;
        } else {
            aliceOutputBalanceBefore = IERC20(tokenOut).balanceOf(alice);
        }
        uint256 aliceLongBalanceBefore = _hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _maturityTime),
            alice
        );

        // Execute the zap.
        IHyperdrive hyperdrive = _hyperdrive; // avoid stack-too-deep
        uint256 maturityTime = _maturityTime; // avoid stack-too-deep
        uint256 bondAmount = _bondAmount; // avoid stack-too-deep
        ISwapRouter.ExactInputParams memory swapParams = _swapParams; // avoid stack-too-deep
        bool shouldWrap = _shouldWrap; // avoid stack-too-deep
        bool asBase = _asBase; // avoid stack-too-deep
        uint256 proceeds = zap.closeLongZap(
            hyperdrive,
            maturityTime, // maturity time
            bondAmount, // bond amount
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

        // Ensure that the vault shares balance is what we would predict from
        // the simulation.
        assertEq(
            IERC20(hyperdrive.vaultSharesToken()).balanceOf(
                address(hyperdrive)
            ),
            expectedHyperdriveVaultSharesBalanceAfter
        );

        // Ensure that the longs outstanding and Alice's balance of longs
        // decreased by the bond amount
        assertEq(
            hyperdrive.getPoolInfo().longsOutstanding,
            longsOutstandingBefore - bondAmount
        );
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                alice
            ),
            aliceLongBalanceBefore - bondAmount
        );
    }
}
