// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

// FIXME
import { console2 as console } from "forge-std/console2.sol";
import { Lib } from "test/utils/Lib.sol";

import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../../contracts/src/interfaces/IERC4626.sol";
import { ILido } from "../../../contracts/src/interfaces/ILido.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { ISwapRouter } from "../../../contracts/src/interfaces/ISwapRouter.sol";
import { IUniV3Zap } from "../../../contracts/src/interfaces/IUniV3Zap.sol";
import { IWETH } from "../../../contracts/src/interfaces/IWETH.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { UniV3Path } from "../../../contracts/src/libraries/UniV3Path.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { UniV3Zap } from "../../../contracts/src/zaps/UniV3Zap.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";

// FIXME: Add test comments.
contract UniV3ZapTest is HyperdriveTest {
    // FIXME
    using Lib for *;

    using FixedPointMath for uint256;
    using UniV3Path for bytes;

    /// @dev The name of the zap contract.
    string internal constant NAME = "DELV Uniswap v3 Zap";

    /// @dev We can assume that almost all Hyperdrive deployments have the
    ///      `convertToBase` and `convertToShares` functions, but there is
    ///      one legacy sDAI pool that was deployed before these functions
    ///      were written. We explicitly special case conversions for this
    ///      pool.
    address internal constant LEGACY_SDAI_HYPERDRIVE =
        address(0x324395D5d835F84a02A75Aa26814f6fD22F25698);

    /// @dev We can assume that almost all Hyperdrive deployments have the
    ///      `convertToBase` and `convertToShares` functions, but there is
    ///      a legacy stETH pool that was deployed before these functions were
    ///      written. We explicitly special case conversions for this pool.
    address internal constant LEGACY_STETH_HYPERDRIVE =
        address(0xd7e470043241C10970953Bd8374ee6238e77D735);

    /// @dev Uniswap's lowest fee tier.
    uint24 internal constant LOWEST_FEE_TIER = 100;

    /// @dev Uniswap's low fee tier.
    uint24 internal constant LOW_FEE_TIER = 500;

    /// @dev Uniswap's medium fee tier.
    uint24 internal constant MEDIUM_FEE_TIER = 3_000;

    /// @dev Uniswap's high fee tier.
    uint24 internal constant HIGH_FEE_TIER = 10_000;

    /// @dev The USDC token address.
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @dev The DAI token address.
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    /// @dev The sDAI token address.
    address internal constant SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;

    /// @dev The Wrapped Ether token address.
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @dev The stETH token address.
    address internal constant STETH =
        0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    /// @dev The USDC whale address
    address internal constant USDC_WHALE =
        0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;

    /// @dev The DAI whale address
    address internal constant DAI_WHALE =
        0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf;

    /// @dev The sDAI whale address
    address internal constant SDAI_WHALE =
        0x4C612E3B15b96Ff9A6faED838F8d07d479a8dD4c;

    /// @dev The stETH whale address
    address internal constant STETH_WHALE =
        0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @dev The Uniswap swap router.
    ISwapRouter internal constant SWAP_ROUTER =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    /// @dev The Hyperdrive mainnet sDAI pool.
    IHyperdrive internal constant SDAI_HYPERDRIVE =
        IHyperdrive(0x324395D5d835F84a02A75Aa26814f6fD22F25698);

    /// @dev The Hyperdrive mainnet stETH pool.
    IHyperdrive internal constant STETH_HYPERDRIVE =
        IHyperdrive(0xd7e470043241C10970953Bd8374ee6238e77D735);

    /// @dev The Uniswap v3 zap contract.
    IUniV3Zap internal zap;

    function setUp() public override __mainnet_fork(20_830_093) {
        // Run the higher-level setup logic.
        super.setUp();

        // Instantiate the zap contract.
        zap = IUniV3Zap(new UniV3Zap(NAME, SWAP_ROUTER, IWETH(WETH)));

        // Set up Alice as the sender.
        vm.stopPrank();
        vm.startPrank(alice);

        // Fund Alice from some whale accounts.
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        fundAccounts(address(zap), IERC20(USDC), USDC_WHALE, accounts);
        fundAccounts(address(zap), IERC20(DAI), DAI_WHALE, accounts);
        fundAccounts(address(zap), IERC20(SDAI), SDAI_WHALE, accounts);
        fundAccounts(address(zap), IERC20(STETH), STETH_WHALE, accounts);
    }

    /// Metadata ///

    // FIXME: Test the metadata.

    // FIXME: These tests can be refactored.
    //
    /// Add Liquidity ///

    function test_addLiquidityZap_failure_invalidRecipient() external {
        // Ensure that the zap fails when the recipient isn't Hyperdrive.
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

    function test_addLiquidityZap_failure_invalidOutputToken_asBase() external {
        // Ensure that the zap fails when `asBase` is true and the output token
        // isn't the base token.
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

    function test_addLiquidityZap_failure_invalidOutputToken_asShares()
        external
    {
        // Ensure that the zap fails when `asBase` is false and the output token
        // isn't the vault shares token.
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

    /// @dev Ensure that Alice can pay for a zap from WETH to DAI with ETH.
    ///      We send extra ETH in the zap to ensure that Alice gets refunded
    ///      for the excess.
    function test_addLiquidityZap_success_asBase_withETH() external {
        // Instantiate the swap parameters for this zap.
        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter
            .ExactInputParams({
                path: abi.encodePacked(WETH, LOW_FEE_TIER, DAI),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 0.3882e18,
                amountOutMinimum: 999e18
            });

        // Gets some data about the trader and the pool before the zap.
        uint256 aliceBalanceBefore = alice.balance;
        uint256 hyperdriveVaultSharesBalanceBefore = IERC20(
            SDAI_HYPERDRIVE.vaultSharesToken()
        ).balanceOf(address(SDAI_HYPERDRIVE));
        uint256 lpTotalSupplyBefore = SDAI_HYPERDRIVE
            .getPoolInfo()
            .lpTotalSupply;
        uint256 lpSharesBefore = SDAI_HYPERDRIVE.balanceOf(
            AssetId._LP_ASSET_ID,
            alice
        );

        // Zaps into `addLiquidity` with `asBase` as `false` from USDC to sDAI.
        uint256 lpShares = zap.addLiquidityZap{ value: 10e18 }(
            SDAI_HYPERDRIVE,
            0, // minimum LP share price
            0, // minimum APR
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: ""
            }),
            false, // is rebasing
            swapParams
        );

        // Ensure that Alice was charged the correct amount of ETH.
        assertEq(alice.balance, aliceBalanceBefore - swapParams.amountIn);

        // Ensure that Hyperdrive received more than the minimum output of the
        // swap.
        //
        // NOTE: Since the vault shares don't rebase, the units are in shares.
        uint256 hyperdriveVaultSharesBalanceAfter = IERC20(
            SDAI_HYPERDRIVE.vaultSharesToken()
        ).balanceOf(address(SDAI_HYPERDRIVE));
        assertGt(
            hyperdriveVaultSharesBalanceAfter,
            hyperdriveVaultSharesBalanceBefore +
                _convertToShares(SDAI_HYPERDRIVE, swapParams.amountOutMinimum)
        );

        // Ensure that Alice received an appropriate amount of LP shares and
        // that the LP total supply increased.
        assertGt(
            lpShares,
            swapParams.amountOutMinimum.divDown(
                SDAI_HYPERDRIVE.getPoolInfo().lpSharePrice
            )
        );
        assertEq(
            SDAI_HYPERDRIVE.balanceOf(AssetId._LP_ASSET_ID, alice),
            lpSharesBefore + lpShares
        );
        assertEq(
            SDAI_HYPERDRIVE.getPoolInfo().lpTotalSupply,
            lpTotalSupplyBefore + lpShares
        );
    }

    /// @dev Ensure that Alice can pay for a zap from WETH to sDAI with ETH.
    ///      We send extra ETH in the zap to ensure that Alice gets refunded
    ///      for the excess.
    function test_addLiquidityZap_success_asShares_withETH() external {
        // Instantiate the swap parameters for this zap.
        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter
            .ExactInputParams({
                path: abi.encodePacked(WETH, LOW_FEE_TIER, SDAI),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 0.3882e18,
                amountOutMinimum: 886e18
            });

        // Gets some data about the trader and the pool before the zap.
        uint256 aliceBalanceBefore = alice.balance;
        uint256 hyperdriveVaultSharesBalanceBefore = IERC20(
            SDAI_HYPERDRIVE.vaultSharesToken()
        ).balanceOf(address(SDAI_HYPERDRIVE));
        uint256 lpTotalSupplyBefore = SDAI_HYPERDRIVE
            .getPoolInfo()
            .lpTotalSupply;
        uint256 lpSharesBefore = SDAI_HYPERDRIVE.balanceOf(
            AssetId._LP_ASSET_ID,
            alice
        );

        // Zaps into `addLiquidity` with `asBase` as `false` from USDC to sDAI.
        uint256 lpShares = zap.addLiquidityZap{ value: 10e18 }(
            SDAI_HYPERDRIVE,
            0, // minimum LP share price
            0, // minimum APR
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: ""
            }),
            false, // is rebasing
            swapParams
        );

        // Ensure that Alice was charged the correct amount of ETH.
        assertEq(alice.balance, aliceBalanceBefore - swapParams.amountIn);

        // Ensure that Hyperdrive received more than the minimum output of the
        // swap.
        //
        // NOTE: Since the vault shares don't rebase, the units are in shares.
        uint256 hyperdriveVaultSharesBalanceAfter = IERC20(
            SDAI_HYPERDRIVE.vaultSharesToken()
        ).balanceOf(address(SDAI_HYPERDRIVE));
        assertGt(
            hyperdriveVaultSharesBalanceAfter,
            hyperdriveVaultSharesBalanceBefore + swapParams.amountOutMinimum
        );

        // Ensure that Alice received an appropriate amount of LP shares and
        // that the LP total supply increased.
        assertGt(
            lpShares,
            swapParams.amountOutMinimum.divDown(
                SDAI_HYPERDRIVE.getPoolInfo().lpSharePrice
            )
        );
        assertEq(
            SDAI_HYPERDRIVE.balanceOf(AssetId._LP_ASSET_ID, alice),
            lpSharesBefore + lpShares
        );
        assertEq(
            SDAI_HYPERDRIVE.getPoolInfo().lpTotalSupply,
            lpTotalSupplyBefore + lpShares
        );
    }

    function test_addLiquidityZap_success_rebasing_asBase() external {
        // Instantiate the swap parameters for this zap.
        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter
            .ExactInputParams({
                path: abi.encodePacked(USDC, MEDIUM_FEE_TIER, WETH),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e6,
                // FIXME
                amountOutMinimum: 0.38e18
            });

        // Gets some data about the trader and the pool before the zap.
        uint256 aliceBalanceBefore = IERC20(swapParams.path.tokenIn())
            .balanceOf(alice);
        uint256 hyperdriveVaultSharesBalanceBefore = IERC20(
            STETH_HYPERDRIVE.vaultSharesToken()
        ).balanceOf(address(STETH_HYPERDRIVE));
        uint256 lpTotalSupplyBefore = STETH_HYPERDRIVE
            .getPoolInfo()
            .lpTotalSupply;
        uint256 lpSharesBefore = STETH_HYPERDRIVE.balanceOf(
            AssetId._LP_ASSET_ID,
            alice
        );

        // Zaps into `addLiquidity` with `asBase` as `true` from USDC to ETH.
        uint256 lpShares = zap.addLiquidityZap(
            STETH_HYPERDRIVE,
            0, // minimum LP share price
            0, // minimum APR
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: ""
            }),
            true, // is rebasing
            swapParams
        );

        // Ensure that Alice was charged the correct amount of the input token.
        assertEq(
            IERC20(swapParams.path.tokenIn()).balanceOf(alice),
            aliceBalanceBefore - swapParams.amountIn
        );

        // Ensure that Hyperdrive received more than the minimum output of the
        // swap.
        //
        // NOTE: Since the vault shares rebase, the units are in base.
        uint256 hyperdriveVaultSharesBalanceAfter = IERC20(
            STETH_HYPERDRIVE.vaultSharesToken()
        ).balanceOf(address(STETH_HYPERDRIVE));
        assertGt(
            hyperdriveVaultSharesBalanceAfter,
            hyperdriveVaultSharesBalanceBefore + swapParams.amountOutMinimum
        );

        // Ensure that Alice received an appropriate amount of LP shares and
        // that the LP total supply increased.
        assertGt(
            lpShares,
            swapParams.amountOutMinimum.divDown(
                STETH_HYPERDRIVE.getPoolInfo().lpSharePrice
            )
        );
        assertEq(
            STETH_HYPERDRIVE.balanceOf(AssetId._LP_ASSET_ID, alice),
            lpSharesBefore + lpShares
        );
        assertEq(
            STETH_HYPERDRIVE.getPoolInfo().lpTotalSupply,
            lpTotalSupplyBefore + lpShares
        );
    }

    // FIXME: Find a route that makes sense for this.
    function test_addLiquidityZap_success_rebasing_asShares() external {
        // Instantiate the swap parameters for this zap.
        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter
            .ExactInputParams({
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
            });

        // Gets some data about the trader and the pool before the zap.
        uint256 aliceBalanceBefore = IERC20(swapParams.path.tokenIn())
            .balanceOf(alice);
        uint256 hyperdriveVaultSharesBalanceBefore = IERC20(
            STETH_HYPERDRIVE.vaultSharesToken()
        ).balanceOf(address(STETH_HYPERDRIVE));
        uint256 lpTotalSupplyBefore = STETH_HYPERDRIVE
            .getPoolInfo()
            .lpTotalSupply;
        uint256 lpSharesBefore = STETH_HYPERDRIVE.balanceOf(
            AssetId._LP_ASSET_ID,
            alice
        );

        // FIXME: Update this comment.
        //
        // Zaps into `addLiquidity` with `asBase` as `false` from USDC to stETH.
        uint256 lpShares = zap.addLiquidityZap(
            STETH_HYPERDRIVE,
            0, // minimum LP share price
            0, // minimum APR
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: ""
            }),
            true, // is rebasing
            swapParams
        );

        // Ensure that Alice was charged the correct amount of the input token.
        assertEq(
            IERC20(swapParams.path.tokenIn()).balanceOf(alice),
            aliceBalanceBefore - swapParams.amountIn
        );

        // Ensure that Hyperdrive received more than the minimum output of the
        // swap.
        //
        // NOTE: Since the vault shares rebase, the units are in base.
        uint256 hyperdriveVaultSharesBalanceAfter = IERC20(
            STETH_HYPERDRIVE.vaultSharesToken()
        ).balanceOf(address(STETH_HYPERDRIVE));
        assertGt(
            hyperdriveVaultSharesBalanceAfter,
            hyperdriveVaultSharesBalanceBefore + swapParams.amountOutMinimum
        );

        // Ensure that Alice received an appropriate amount of LP shares and
        // that the LP total supply increased.
        assertGt(
            lpShares,
            swapParams.amountOutMinimum.divDown(
                STETH_HYPERDRIVE.getPoolInfo().lpSharePrice
            )
        );
        assertEq(
            STETH_HYPERDRIVE.balanceOf(AssetId._LP_ASSET_ID, alice),
            lpSharesBefore + lpShares
        );
        assertEq(
            STETH_HYPERDRIVE.getPoolInfo().lpTotalSupply,
            lpTotalSupplyBefore + lpShares
        );
    }

    function test_addLiquidityZap_success_nonRebasing_asBase() external {
        // Instantiate the swap parameters for this zap.
        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter
            .ExactInputParams({
                path: abi.encodePacked(USDC, LOWEST_FEE_TIER, DAI),
                recipient: address(zap),
                deadline: block.timestamp + 1 minutes,
                amountIn: 1_000e6,
                amountOutMinimum: 999e18
            });

        // Gets some data about the trader and the pool before the zap.
        uint256 aliceBalanceBefore = IERC20(swapParams.path.tokenIn())
            .balanceOf(alice);
        uint256 hyperdriveVaultSharesBalanceBefore = IERC20(
            SDAI_HYPERDRIVE.vaultSharesToken()
        ).balanceOf(address(SDAI_HYPERDRIVE));
        uint256 lpTotalSupplyBefore = SDAI_HYPERDRIVE
            .getPoolInfo()
            .lpTotalSupply;
        uint256 lpSharesBefore = SDAI_HYPERDRIVE.balanceOf(
            AssetId._LP_ASSET_ID,
            alice
        );

        // Zaps into `addLiquidity` with `asBase` as `true` from USDC to DAI.
        uint256 lpShares = zap.addLiquidityZap(
            SDAI_HYPERDRIVE,
            0, // minimum LP share price
            0, // minimum APR
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: ""
            }),
            false, // is rebasing
            swapParams
        );

        // Ensure that Alice was charged the correct amount of the input token.
        assertEq(
            IERC20(swapParams.path.tokenIn()).balanceOf(alice),
            aliceBalanceBefore - swapParams.amountIn
        );

        // Ensure that Hyperdrive received more than the minimum output of the
        // swap.
        //
        // NOTE: Since the vault shares don't rebase, the units are in shares.
        uint256 hyperdriveVaultSharesBalanceAfter = IERC20(
            SDAI_HYPERDRIVE.vaultSharesToken()
        ).balanceOf(address(SDAI_HYPERDRIVE));
        assertGt(
            hyperdriveVaultSharesBalanceAfter,
            hyperdriveVaultSharesBalanceBefore +
                _convertToShares(SDAI_HYPERDRIVE, swapParams.amountOutMinimum)
        );

        // Ensure that Alice received an appropriate amount of LP shares and
        // that the LP total supply increased.
        assertGt(
            lpShares,
            swapParams.amountOutMinimum.divDown(
                SDAI_HYPERDRIVE.getPoolInfo().lpSharePrice
            )
        );
        assertEq(
            SDAI_HYPERDRIVE.balanceOf(AssetId._LP_ASSET_ID, alice),
            lpSharesBefore + lpShares
        );
        assertEq(
            SDAI_HYPERDRIVE.getPoolInfo().lpTotalSupply,
            lpTotalSupplyBefore + lpShares
        );
    }

    function test_addLiquidityZap_success_nonRebasing_asShares() external {
        // Instantiate the swap parameters for this zap.
        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter
            .ExactInputParams({
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
            });

        // Gets some data about the trader and the pool before the zap.
        uint256 aliceBalanceBefore = IERC20(swapParams.path.tokenIn())
            .balanceOf(alice);
        uint256 hyperdriveVaultSharesBalanceBefore = IERC20(
            SDAI_HYPERDRIVE.vaultSharesToken()
        ).balanceOf(address(SDAI_HYPERDRIVE));
        uint256 lpTotalSupplyBefore = SDAI_HYPERDRIVE
            .getPoolInfo()
            .lpTotalSupply;
        uint256 lpSharesBefore = SDAI_HYPERDRIVE.balanceOf(
            AssetId._LP_ASSET_ID,
            alice
        );

        // Zaps into `addLiquidity` with `asBase` as `false` from USDC to sDAI.
        uint256 lpShares = zap.addLiquidityZap(
            SDAI_HYPERDRIVE,
            0, // minimum LP share price
            0, // minimum APR
            type(uint256).max, // maximum APR
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: ""
            }),
            false, // is rebasing
            swapParams
        );

        // Ensure that Alice was charged the correct amount of the input token.
        assertEq(
            IERC20(swapParams.path.tokenIn()).balanceOf(alice),
            aliceBalanceBefore - swapParams.amountIn
        );

        // Ensure that Hyperdrive received more than the minimum output of the
        // swap.
        //
        // NOTE: Since the vault shares don't rebase, the units are in shares.
        uint256 hyperdriveVaultSharesBalanceAfter = IERC20(
            SDAI_HYPERDRIVE.vaultSharesToken()
        ).balanceOf(address(SDAI_HYPERDRIVE));
        assertGt(
            hyperdriveVaultSharesBalanceAfter,
            hyperdriveVaultSharesBalanceBefore + swapParams.amountOutMinimum
        );

        // Ensure that Alice received an appropriate amount of LP shares and
        // that the LP total supply increased.
        assertGt(
            lpShares,
            swapParams.amountOutMinimum.divDown(
                SDAI_HYPERDRIVE.getPoolInfo().lpSharePrice
            )
        );
        assertEq(
            SDAI_HYPERDRIVE.balanceOf(AssetId._LP_ASSET_ID, alice),
            lpSharesBefore + lpShares
        );
        assertEq(
            SDAI_HYPERDRIVE.getPoolInfo().lpTotalSupply,
            lpTotalSupplyBefore + lpShares
        );
    }

    /// Remove Liquidity ///

    // FIXME

    /// Redeem Withdrawal Shares ///

    // FIXME

    /// Open Long ///

    // FIXME

    /// Close Long ///

    // FIXME

    /// Open Short ///

    // FIXME

    /// Close Short ///

    // FIXME

    /// Helpers ///

    /// @dev Converts a quantity to shares. This works for all Hyperdrive pools.
    function _convertToShares(
        IHyperdrive _hyperdrive,
        uint256 _baseAmount
    ) internal view returns (uint256) {
        // If this is a mainnet deployment and the address is the legacy stETH
        // pool, we have to convert the proceeds to shares manually using Lido's
        // `getSharesByPooledEth` function.
        if (
            block.chainid == 1 &&
            address(_hyperdrive) == LEGACY_STETH_HYPERDRIVE
        ) {
            return
                ILido(_hyperdrive.vaultSharesToken()).getSharesByPooledEth(
                    _baseAmount
                );
        }
        // If this is a mainnet deployment and the address is the legacy stETH
        // pool, we have to convert the proceeds to shares manually using Lido's
        // `getSharesByPooledEth` function.
        else if (
            block.chainid == 1 && address(_hyperdrive) == LEGACY_SDAI_HYPERDRIVE
        ) {
            return
                IERC4626(_hyperdrive.vaultSharesToken()).convertToShares(
                    _baseAmount
                );
        }
        // Otherwise, we can use the built-in `convertToShares` function.
        else {
            return _hyperdrive.convertToShares(_baseAmount);
        }
    }
}
