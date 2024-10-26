// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { console2 as console } from "forge-std/console2.sol";
import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { IMorphoFlashLoanCallback } from "morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { EtchingUtils } from "../../utils/EtchingUtils.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

// FIXME: Eventually, this will need to support rebasing.
//
// FIXME: Eventually, this should handle ETH.
//
// FIXME: This is super insecure as written.
//
// FIXME: This will need to support combinations of `asBase = true` and
//        `asBase = false`.
//
// FIXME: This can be re-architected to fire off the flash loan call itself and
//        do some initial valuation.
contract HyperdriveOTC is IMorphoFlashLoanCallback {
    // FIXME
    using HyperdriveUtils for *;
    using Lib for *;

    // FIXME: Set this up properly.
    IMorpho public constant MORPHO =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    // FIXME: This has the same data as the other struct. Clean this up.
    struct Trade {
        uint256 amount;
        uint256 slippageGuard;
        uint256 minVaultSharePrice;
        IHyperdrive.Options options;
    }

    // FIXME: Write a function that calls Morpho for flash loans.
    //
    // FIXME: I need more info for the LP side of the equation for things like
    // asBase and extraData.
    function executeOTC(
        IHyperdrive _hyperdrive,
        address _long,
        address _short,
        Trade calldata _longTrade,
        Trade calldata _shortTrade,
        uint256 _lpAmount,
        IHyperdrive.Options calldata _addLiquidityOptions,
        IHyperdrive.Options calldata _removeLiquidityOptions
    ) external {
        // FIXME: Perform more validation to ensure that this is a valid use of
        //        funds.
        //
        // FIXME: Validate the add and remove liquidity options.
        //
        // Send off the flash loan call to Morpho. The remaining execution logic
        // will be executed in the `onMorphoFlashLoan` callback.
        address loanToken;
        if (_addLiquidityOptions.asBase) {
            loanToken = _hyperdrive.baseToken();
        } else {
            loanToken = _hyperdrive.vaultSharesToken();
        }
        MORPHO.flashLoan(
            loanToken,
            _lpAmount,
            abi.encode(
                _hyperdrive,
                _long,
                _short,
                _longTrade,
                _shortTrade,
                _lpAmount,
                _addLiquidityOptions,
                _removeLiquidityOptions
            )
        );
    }

    // FIXME: Document this.
    //
    /// @notice Callback called when a flash loan occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param assets The amount of assets that was flash loaned.
    /// @param data Arbitrary data passed to the `flashLoan` function.
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
        // FIXME: Comment this.
        console.log("onMorphoFlashLoan: 1");
        (
            IHyperdrive hyperdrive,
            address long,
            address short,
            Trade memory longTrade,
            Trade memory shortTrade,
            uint256 lpAmount,
            IHyperdrive.Options memory addLiquidityOptions,
            IHyperdrive.Options memory removeLiquidityOptions
        ) = abi.decode(
                data,
                (
                    IHyperdrive,
                    address,
                    address,
                    Trade,
                    Trade,
                    uint256,
                    IHyperdrive.Options,
                    IHyperdrive.Options
                )
            );
        console.log("onMorphoFlashLoan: 2");

        // FIXME: Ensure that the add liquidity options forward the funds to
        // this contract.
        //
        // FIXME: Support more options.
        //
        // Add liquidity to the pool.
        IERC20 addLiquidityToken;
        if (addLiquidityOptions.asBase) {
            addLiquidityToken = IERC20(hyperdrive.baseToken());
        } else {
            addLiquidityToken = IERC20(hyperdrive.vaultSharesToken());
        }
        console.log("onMorphoFlashLoan: 3");
        // FIXME: forceApprove
        console.log("lpAmount = %s", lpAmount.toString(6));
        addLiquidityToken.approve(address(hyperdrive), lpAmount + 1);
        uint256 lpShares = hyperdrive.addLiquidity(
            lpAmount,
            0,
            0,
            type(uint256).max,
            addLiquidityOptions
        );
        console.log("lp shares = %s", lpShares.toString(6));
        console.log("onMorphoFlashLoan: 4");

        // FIXME: Refund the short.
        //
        // Open the short and send it to the short trader.
        IERC20 shortAsset;
        if (shortTrade.options.asBase) {
            shortAsset = IERC20(hyperdrive.baseToken());
        } else {
            // FIXME
            revert("unimplemented");
        }
        console.log("onMorphoFlashLoan: 5");
        shortAsset.transferFrom(short, address(this), shortTrade.slippageGuard);
        shortAsset.approve(address(hyperdrive), shortTrade.slippageGuard + 1);
        console.log("onMorphoFlashLoan: 6");
        console.log(
            "maxShort = %s",
            hyperdrive.calculateMaxShort().toString(6)
        );
        console.log(
            "slippage guards = %s",
            shortTrade.slippageGuard.toString(6)
        );
        (uint256 maturityTime, uint256 shortPaid) = hyperdrive.openShort(
            shortTrade.amount,
            shortTrade.slippageGuard,
            shortTrade.minVaultSharePrice,
            shortTrade.options
        );
        if (shortTrade.slippageGuard > shortPaid) {
            // FIXME: Use safe transfer.
            shortAsset.transfer(short, shortTrade.slippageGuard - shortPaid);
        }
        console.log("onMorphoFlashLoan: 7");

        // Open the long and send it to the long trader.
        IERC20 longAsset;
        if (longTrade.options.asBase) {
            longAsset = IERC20(hyperdrive.baseToken());
        } else {
            // FIXME
            revert("unimplemented");
        }
        longAsset.transferFrom(short, address(this), longTrade.amount);
        longAsset.approve(address(hyperdrive), longTrade.amount + 1);
        console.log("onMorphoFlashLoan: 8");

        // FIXME: Handle the case where we can only add liquidity with base and
        // remove with shares. We'll probably need a zap for this case.
        //
        // Remove liquidity. This will repay the flash loan. We revert if there
        // are any withdrawal shares.
        (uint256 proceeds, uint256 withdrawalShares) = hyperdrive
            .removeLiquidity(lpShares, 0, removeLiquidityOptions);
        require(withdrawalShares == 0, "Invalid withdrawal shares");
        console.log("onMorphoFlashLoan: 9");

        // FIXME: Send any excess proceeds back to the sender.
        //
        // // FIXME: We'll need to make sure this is in the same basis.
        // //
        // // FIXME: We could send this to the short.
        // //
        // // Send the profits to the long.
        // if (proceeds > lpAmount) {
        //     // FIXME: SafeTransfer
        //     baseToken.transfer(msg.sender, proceeds - lpAmount);
        // }
    }
}

contract JITLiquidityTest is HyperdriveTest, EtchingUtils {
    using FixedPointMath for *;
    using Lib for *;

    /// @dev This is the LP we'll use to provide JIT liquidity. This whale has
    ///      over 260 million USDC on Base.
    address internal constant LP = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    /// @dev This is the address that will buy the short to hedge their borrow
    ///      position. This whale has 128 million USDC on Base.
    address internal constant HEDGER =
        0x3304E22DDaa22bCdC5fCa2269b418046aE7b566A;

    // NOTE: In prod, we'd want to use the wBTC/USDC or cbBTC/USDC market, but
    //       this is a good stand-in.
    //
    /// @dev The Morpho Blue cbETH/USDC pool on Base.
    IHyperdrive internal constant HYPERDRIVE =
        IHyperdrive(0xFcdaF9A4A731C24ed2E1BFd6FA918d9CF7F50137);

    /// @dev Sets up the test harness on a base fork.
    function setUp() public override __base_fork(21_545_771) {
        // Run the higher-level setup logic.
        super.setUp();

        // Etch the Hyperdrive instance.
        etchHyperdrive(address(HYPERDRIVE));

        // Approve Hyperdrive with each of the whales.
        vm.stopPrank();
        vm.startPrank(LP);
        IERC20(HYPERDRIVE.baseToken()).approve(
            address(HYPERDRIVE),
            type(uint256).max
        );
        vm.stopPrank();
        vm.startPrank(HEDGER);
        IERC20(HYPERDRIVE.baseToken()).approve(
            address(HYPERDRIVE),
            type(uint256).max
        );
    }

    /// @dev This test demonstrates that JIT liquidity can be provided and
    ///      includes some relevant statistics.
    function test_jit_liquidity() external {
        // The LP adds JIT liquidity.
        vm.stopPrank();
        vm.startPrank(LP);
        uint256 contribution = 25_000_000e6;
        uint256 lpShares = HYPERDRIVE.addLiquidity(
            contribution,
            0,
            0,
            type(uint256).max,
            IHyperdrive.Options({
                asBase: true,
                destination: LP,
                extraData: ""
            })
        );

        // The hedger opens a short.
        vm.stopPrank();
        vm.startPrank(HEDGER);
        uint256 shortAmount = 5_000_000e6;
        (uint256 maturityTime, uint256 shortPaid) = HYPERDRIVE.openShort(
            shortAmount,
            type(uint256).max,
            0,
            IHyperdrive.Options({
                asBase: true,
                destination: HEDGER,
                extraData: ""
            })
        );

        // The LP opens a long to net out with the hedger's position.
        vm.stopPrank();
        vm.startPrank(LP);
        uint256 longPaid = 4_924_947e6;
        uint256 longAmount;
        (maturityTime, longAmount) = HYPERDRIVE.openLong(
            longPaid,
            0,
            0,
            IHyperdrive.Options({
                asBase: true,
                destination: LP,
                extraData: ""
            })
        );

        // The LP removes their liquidity.
        vm.stopPrank();
        vm.startPrank(LP);
        (uint256 baseProceeds, uint256 withdrawalShares) = HYPERDRIVE
            .removeLiquidity(
                lpShares,
                0,
                IHyperdrive.Options({
                    asBase: true,
                    destination: LP,
                    extraData: ""
                })
            );

        // Logs
        console.log("# Short");
        console.log("shortPaid                  = %s", shortPaid.toString(6));
        console.log("shortAmount                = %s", shortAmount.toString(6));
        console.log(
            "short fixed rate           = %s%",
            (HyperdriveUtils.calculateAPRFromRealizedPrice(
                shortAmount -
                    (shortPaid -
                        shortAmount.mulDown(
                            HYPERDRIVE.getPoolConfig().fees.flat
                        )),
                shortAmount,
                HYPERDRIVE.getPoolConfig().positionDuration.divDown(365 days)
            ) * 100).toString(18)
        );
        console.log("");
        console.log("# Long");
        console.log("longPaid                   = %s", longPaid.toString(6));
        console.log("longAmount                 = %s", longAmount.toString(6));
        console.log(
            "long fixed rate            = %s%",
            (HyperdriveUtils.calculateAPRFromRealizedPrice(
                longPaid,
                longAmount,
                HYPERDRIVE.getPoolConfig().positionDuration.divDown(365 days)
            ) * 100).toString(18)
        );
        console.log(
            "long fixed rate (adjusted) = %s%",
            (HyperdriveUtils.calculateAPRFromRealizedPrice(
                longPaid - (baseProceeds - contribution),
                longAmount,
                HYPERDRIVE.getPoolConfig().positionDuration.divDown(365 days)
            ) * 100).toString(18)
        );
        console.log("");
        console.log("# LP");
        console.log("baseProceeds     = %s", baseProceeds.toString(6));
        console.log("withdrawalShares = %s", withdrawalShares.toString(6));
    }

    /// @dev This test demonstrates that JIT liquidity can be provided using
    ///      free Morpho flash loans and includes some relevant statistics.
    function test_jit_liquidity_flash_loan() external {
        // FIXME: Instead of looking at returndata, I'll need to get what
        // happened from state changes or events.
        //
        // FIXME: Set up a call for JIT Liquidity through the OTC contract.
        HyperdriveOTC otc = new HyperdriveOTC();
        vm.stopPrank();
        vm.startPrank(LP);
        IERC20(HYPERDRIVE.baseToken()).approve(address(otc), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(HEDGER);
        IERC20(HYPERDRIVE.baseToken()).approve(address(otc), type(uint256).max);
        otc.executeOTC(
            HYPERDRIVE,
            LP,
            HEDGER,
            HyperdriveOTC.Trade({
                amount: 4_924_947e6,
                slippageGuard: 4_999_999e6,
                minVaultSharePrice: 0,
                options: IHyperdrive.Options({
                    asBase: true,
                    destination: LP,
                    extraData: ""
                })
            }),
            HyperdriveOTC.Trade({
                amount: 5_000_000e6,
                slippageGuard: 80_000e6,
                minVaultSharePrice: 0,
                options: IHyperdrive.Options({
                    asBase: true,
                    destination: LP,
                    extraData: ""
                })
            }),
            12_000_000e6,
            IHyperdrive.Options({
                asBase: true,
                destination: address(otc),
                extraData: ""
            }),
            IHyperdrive.Options({
                asBase: true,
                destination: address(otc),
                extraData: ""
            })
        );
    }
}
