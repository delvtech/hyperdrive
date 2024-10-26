// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { console2 as console } from "forge-std/console2.sol";
import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { IMorphoFlashLoanCallback } from "morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import { MorphoBlueHyperdrive } from "../../../contracts/src/instances/morpho-blue/MorphoBlueHyperdrive.sol";
import { MorphoBlueTarget0 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget0.sol";
import { MorphoBlueTarget1 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget1.sol";
import { MorphoBlueTarget2 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget2.sol";
import { MorphoBlueTarget3 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget3.sol";
import { MorphoBlueTarget4 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget4.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IMorphoBlueHyperdrive } from "../../../contracts/src/interfaces/IMorphoBlueHyperdrive.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
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
        console.log(
            "effective share reserves = %s",
            HyperdriveMath
                .calculateEffectiveShareReserves(
                    hyperdrive.getPoolInfo().shareReserves,
                    hyperdrive.getPoolInfo().shareAdjustment
                )
                .toString(6)
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
    using HyperdriveUtils for *;
    using Lib for *;

    /// @dev The address of the Morpho Blue pool.
    IMorpho internal constant MORPHO =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    /// @dev This is the initializer of the JIT pool.
    address internal constant INITIALIZER =
        0x54edC2D90BBfE50526E333c7FfEaD3B0F22D39F0;

    /// @dev This is the LP we'll use to provide JIT liquidity..
    address internal constant LP = 0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;

    /// @dev This is the address that will buy the short to hedge their borrow
    ///      position.
    address internal constant HEDGER =
        0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;

    // NOTE: In prod, we'd want to use the wBTC/USDC or cbBTC/USDC market, but
    //       this is a good stand-in.
    //
    /// @dev The Morpho Blue cbETH/USDC pool on Base.
    // IHyperdrive internal constant hyperdrive =
    //     IHyperdrive(0xFcdaF9A4A731C24ed2E1BFd6FA918d9CF7F50137);

    /// @dev Sets up the test harness on a base fork.
    function setUp() public override __mainnet_fork(21_046_731) {
        // Run the higher-level setup logic.
        super.setUp();

        // Deploy a Morpho Blue cbBTC/USDC pool and etch it.
        IHyperdrive.PoolConfig memory config = testConfig(
            0.04e18,
            POSITION_DURATION
        );
        config.baseToken = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        config.vaultSharesToken = IERC20(address(0));
        config.fees.curve = 0.01e18;
        config.fees.flat = 0.0005e18;
        config.fees.governanceLP = 0.15e18;
        config.minimumShareReserves = 1e6;
        config.minimumTransactionAmount = 1e6;
        IMorphoBlueHyperdrive.MorphoBlueParams
            memory params = IMorphoBlueHyperdrive.MorphoBlueParams({
                morpho: MORPHO,
                collateralToken: address(
                    0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf
                ),
                oracle: address(0xA6D6950c9F177F1De7f7757FB33539e3Ec60182a),
                irm: address(0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC),
                lltv: 860000000000000000
            });
        hyperdrive = IHyperdrive(
            address(
                new MorphoBlueHyperdrive(
                    "MorphoBlueHyperdrive",
                    config,
                    adminController,
                    address(
                        new MorphoBlueTarget0(config, adminController, params)
                    ),
                    address(
                        new MorphoBlueTarget1(config, adminController, params)
                    ),
                    address(
                        new MorphoBlueTarget2(config, adminController, params)
                    ),
                    address(
                        new MorphoBlueTarget3(config, adminController, params)
                    ),
                    address(
                        new MorphoBlueTarget4(config, adminController, params)
                    ),
                    params
                )
            )
        );

        // Approve Hyperdrive with each of the whales.
        vm.stopPrank();
        vm.startPrank(HEDGER);
        IERC20(hyperdrive.baseToken()).approve(
            address(hyperdrive),
            type(uint256).max
        );
        vm.stopPrank();
        vm.startPrank(INITIALIZER);
        IERC20(hyperdrive.baseToken()).approve(
            address(hyperdrive),
            type(uint256).max
        );
        vm.stopPrank();
        vm.startPrank(LP);
        IERC20(hyperdrive.baseToken()).approve(
            address(hyperdrive),
            type(uint256).max
        );

        // Initialize the Hyperdrive pool.
        vm.stopPrank();
        vm.startPrank(INITIALIZER);
        console.log("setUp: 1");
        hyperdrive.initialize(
            100e6,
            0.0361e18,
            IHyperdrive.Options({
                asBase: true,
                destination: INITIALIZER,
                extraData: ""
            })
        );
        console.log("setUp: 2");
        console.log(
            "spot rate = %s",
            hyperdrive.calculateSpotAPR().toString(18)
        );
    }

    /// @dev This test demonstrates that JIT liquidity can be provided and
    ///      includes some relevant statistics.
    function test_jit_liquidity() external {
        // The LP adds JIT liquidity.
        vm.stopPrank();
        vm.startPrank(LP);
        uint256 contribution = 25_000_000e6;
        uint256 lpShares = hyperdrive.addLiquidity(
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
        (uint256 maturityTime, uint256 shortPaid) = hyperdrive.openShort(
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
        (maturityTime, longAmount) = hyperdrive.openLong(
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
        (uint256 baseProceeds, uint256 withdrawalShares) = hyperdrive
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
                            hyperdrive.getPoolConfig().fees.flat
                        )),
                shortAmount,
                hyperdrive.getPoolConfig().positionDuration.divDown(365 days)
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
                hyperdrive.getPoolConfig().positionDuration.divDown(365 days)
            ) * 100).toString(18)
        );
        console.log(
            "long fixed rate (adjusted) = %s%",
            (HyperdriveUtils.calculateAPRFromRealizedPrice(
                longPaid - (baseProceeds - contribution),
                longAmount,
                hyperdrive.getPoolConfig().positionDuration.divDown(365 days)
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
        IERC20(hyperdrive.baseToken()).approve(address(otc), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(HEDGER);
        IERC20(hyperdrive.baseToken()).approve(address(otc), type(uint256).max);
        otc.executeOTC(
            hyperdrive,
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
