// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { console2 as console } from "forge-std/console2.sol";
import { IMorpho, Market, MarketParams, Id } from "morpho-blue/src/interfaces/IMorpho.sol";
import { IIrm } from "morpho-blue/src/interfaces/IIrm.sol";
import { IMorphoFlashLoanCallback } from "morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { MorphoBlueConversions } from "../../../contracts/src/instances/morpho-blue/MorphoBlueConversions.sol";
import { MorphoBlueHyperdrive } from "../../../contracts/src/instances/morpho-blue/MorphoBlueHyperdrive.sol";
import { MorphoBlueTarget0 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget0.sol";
import { MorphoBlueTarget1 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget1.sol";
import { MorphoBlueTarget2 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget2.sol";
import { MorphoBlueTarget3 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget3.sol";
import { MorphoBlueTarget4 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget4.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IMorphoBlueHyperdrive } from "../../../contracts/src/interfaces/IMorphoBlueHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { EtchingUtils } from "../../utils/EtchingUtils.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

// FIXME: Vendoring this to work around type weirdness.
//
/// @title IAdaptiveCurveIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Interface exposed by the AdaptiveCurveIrm.
interface IAdaptiveCurveIrm is IIrm {
    /// @notice Address of Morpho.
    function MORPHO() external view returns (address);

    /// @notice Rate at target utilization.
    /// @dev Tells the height of the curve.
    function rateAtTarget(Id id) external view returns (int256);
}

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
    using FixedPointMath for *;
    using HyperdriveUtils for *;
    using Lib for *;

    using SafeERC20 for ERC20;

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

    // FIXME: Re-architect this before documenting it.
    //
    /// @notice Executes an OTC trade.
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

    // FIXME: Rewrite this function and clean it up. There are a few things we
    // need to think through.
    //
    // 1. [ ] Consolidate the arguments.
    // 2. [ ] Add validation for the orders. We'll also need cancels.
    // 3. [ ] Reduce the complexity of the function. Can we DRY up the logic?
    //
    // FIXME: Document this.
    //
    /// @notice Callback called when a flash loan occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param assets The amount of assets that was flash loaned.
    /// @param data Arbitrary data passed to the `flashLoan` function.
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
        // Decode the execution parameters. This encodes the information
        // required to execute the LP, long, and short operations.
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

        // FIXME: Handle rebasing tokens.
        //
        // Add liquidity to the pool.
        ERC20 addLiquidityToken;
        if (addLiquidityOptions.asBase) {
            addLiquidityToken = ERC20(hyperdrive.baseToken());
        } else {
            addLiquidityToken = ERC20(hyperdrive.vaultSharesToken());
        }
        addLiquidityToken.forceApprove(address(hyperdrive), lpAmount + 1);
        uint256 lpShares = hyperdrive.addLiquidity(
            lpAmount,
            0,
            0,
            type(uint256).max,
            addLiquidityOptions
        );

        // FIXME: Handle rebasing tokens.
        //
        // Open the short and send it to the short trader.
        ERC20 shortAsset;
        if (shortTrade.options.asBase) {
            shortAsset = ERC20(hyperdrive.baseToken());
        } else {
            shortAsset = ERC20(hyperdrive.vaultSharesToken());
        }
        shortAsset.safeTransferFrom(
            short,
            address(this),
            shortTrade.slippageGuard
        );
        shortAsset.forceApprove(
            address(hyperdrive),
            shortTrade.slippageGuard + 1
        );
        (, uint256 shortPaid) = hyperdrive.openShort(
            shortTrade.amount,
            shortTrade.slippageGuard,
            shortTrade.minVaultSharePrice,
            shortTrade.options
        );
        if (shortTrade.slippageGuard > shortPaid) {
            shortAsset.safeTransfer(
                short,
                shortTrade.slippageGuard - shortPaid
            );
        }

        // FIXME: Handle rebasing tokens.
        //
        // Open the long and send it to the long trader.
        ERC20 longAsset;
        if (longTrade.options.asBase) {
            longAsset = ERC20(hyperdrive.baseToken());
        } else {
            longAsset = ERC20(hyperdrive.vaultSharesToken());
        }
        longAsset.safeTransferFrom(long, address(this), longTrade.amount);
        longAsset.forceApprove(address(hyperdrive), longTrade.amount + 1);
        (, uint256 longAmount) = hyperdrive.openLong(
            longTrade.amount,
            longTrade.slippageGuard,
            longTrade.minVaultSharePrice,
            longTrade.options
        );

        // FIXME: Handle the case where we can only add liquidity with base and
        // remove with shares. We'll probably need a zap for this case.
        //
        // Remove liquidity. This will repay the flash loan. We revert if there
        // are any withdrawal shares.
        IHyperdrive hyperdrive_ = hyperdrive; // avoid stack-too-deep
        (uint256 proceeds, uint256 withdrawalShares) = hyperdrive_
            .removeLiquidity(lpShares, 0, removeLiquidityOptions);
        require(withdrawalShares == 0, "Invalid withdrawal shares");

        // FIXME: Send any excess proceeds back to the long.
        console.log("proceeds = %s", (proceeds - lpAmount).toString(18));

        // Approve Morpho Blue to take back the assets that were provided.
        ERC20 loanToken;
        if (addLiquidityOptions.asBase) {
            loanToken = ERC20(hyperdrive_.baseToken());
        } else {
            loanToken = ERC20(hyperdrive_.vaultSharesToken());
        }
        loanToken.forceApprove(address(MORPHO), lpAmount);
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

    /// @dev Sets up the test harness on a base fork.
    function setUp() public override __mainnet_fork(21_046_731) {
        // Run the higher-level setup logic.
        super.setUp();

        // Deploy a Morpho Blue cbBTC/USDC pool.
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
        IHyperdrive.PoolConfig memory config = testConfig(0.04e18, 182 days);
        config.baseToken = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        config.vaultSharesToken = IERC20(address(0));
        config.fees.curve = 0.01e18;
        config.fees.flat = 0.0005e18;
        config.fees.governanceLP = 0.15e18;
        config.minimumShareReserves = 1e6;
        config.minimumTransactionAmount = 1e6;
        config.initialVaultSharePrice = MorphoBlueConversions.convertToBase(
            MORPHO,
            config.baseToken,
            params.collateralToken,
            params.oracle,
            params.irm,
            params.lltv,
            ONE
        );
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
        hyperdrive.initialize(
            100e6,
            0.0361e18,
            IHyperdrive.Options({
                asBase: true,
                destination: INITIALIZER,
                extraData: ""
            })
        );
    }

    /// @dev This test does the math to compute the gap rate.
    function test_gap_rate() external {
        // Get the Morpho interest rate model's rate at target.
        IMorphoBlueHyperdrive morphoBlueHyperdrive = IMorphoBlueHyperdrive(
            address(hyperdrive)
        );
        IAdaptiveCurveIrm irm = IAdaptiveCurveIrm(morphoBlueHyperdrive.irm());
        uint256 rateAtTarget = uint256(
            irm.rateAtTarget(morphoBlueHyperdrive.id())
        );
        console.log(
            "id = %s",
            vm.toString(Id.unwrap(morphoBlueHyperdrive.id()))
        );
        console.log("rateAtTarget = %s", rateAtTarget.toString(18));

        // FIXME: Does this work? Double check the utilization.
        //
        // Get the average borrow rate if the pool is at a utilization of 35%.
        // We create a market that has this utilization and only specify the
        // parameters that are actually used in the calculation.
        uint256 borrowRate = irm.borrowRateView(
            MarketParams({
                loanToken: morphoBlueHyperdrive.baseToken(),
                collateralToken: morphoBlueHyperdrive.collateralToken(),
                oracle: morphoBlueHyperdrive.oracle(),
                irm: morphoBlueHyperdrive.irm(),
                lltv: morphoBlueHyperdrive.lltv()
            }),
            Market({
                totalSupplyAssets: 1e18,
                totalSupplyShares: 0,
                totalBorrowAssets: 0.35e18,
                totalBorrowShares: 0,
                lastUpdate: MORPHO.market(morphoBlueHyperdrive.id()).lastUpdate,
                fee: 0
            })
        );
        console.log("borrowRate = %s", borrowRate.toString(18));

        // Since Morpho's fee is zero, the supply rate is just the borrow rate
        // scaled by the utilization.
        uint256 supplyRate = borrowRate.mulUp(0.35e18);
        console.log("supplyRate = %s", supplyRate.toString(18));

        // Convert the borrow and supply rates to APYs.
        uint256 borrowAPY = _getAPY(borrowRate);
        console.log("borrowAPY = %s", borrowAPY.toString(18));
        uint256 supplyAPY = _getAPY(supplyRate);
        console.log("supplyAPY = %s", supplyAPY.toString(18));

        // FIXME: Compute the gapAPY as borrowAPY - supplyAPY
        uint256 gapAPY = borrowAPY - supplyAPY;
        console.log("gapAPY = %s", gapAPY.toString(18));
        // FIXME: Look into the conversion that they do with the short rate.
        //        At a surface level, this looks really weird to me.
    }

    /// @dev This test demonstrates that JIT liquidity can be provided and
    ///      includes some relevant statistics.
    function test_jit_liquidity() external {
        // The LP adds JIT liquidity.
        vm.stopPrank();
        vm.startPrank(LP);
        uint256 contribution = 21_000_000e6;
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
        // Deploy the OTC contract and have the whales approve.
        HyperdriveOTC otc = new HyperdriveOTC();
        vm.stopPrank();
        vm.startPrank(LP);
        IERC20(hyperdrive.baseToken()).approve(address(otc), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(HEDGER);
        IERC20(hyperdrive.baseToken()).approve(address(otc), type(uint256).max);

        // Get some information before the trade.
        uint256 lpBaseBalanceBefore = IERC20(hyperdrive.baseToken()).balanceOf(
            LP
        );
        uint256 lpLongBalanceBefore = hyperdrive.balanceOf(
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Long,
                hyperdrive.latestCheckpoint()
            ),
            LP
        );
        uint256 hedgerBaseBalanceBefore = IERC20(hyperdrive.baseToken())
            .balanceOf(HEDGER);
        uint256 hedgerShortBalanceBefore = hyperdrive.balanceOf(
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Short,
                hyperdrive.latestCheckpoint()
            ),
            HEDGER
        );

        // FIXME: Clean up this function call. How should this be structured?
        //
        // Execute an OTC trade between two counterparties using flash loans.
        otc.executeOTC(
            hyperdrive,
            LP,
            HEDGER,
            // long trade
            HyperdriveOTC.Trade({
                amount: 4_831_102e6,
                slippageGuard: 4_999_999e6,
                minVaultSharePrice: 0,
                options: IHyperdrive.Options({
                    asBase: true,
                    destination: LP,
                    extraData: ""
                })
            }),
            // short trade
            HyperdriveOTC.Trade({
                amount: 5_000_000e6,
                slippageGuard: 200_000e6,
                minVaultSharePrice: 0,
                options: IHyperdrive.Options({
                    asBase: true,
                    destination: HEDGER,
                    extraData: ""
                })
            }),
            // flash loan amount
            19_000_000e6,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(otc),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(otc),
                extraData: ""
            })
        );

        // FIXME: Logs
        {
            uint256 shortPaid = hedgerBaseBalanceBefore -
                IERC20(hyperdrive.baseToken()).balanceOf(HEDGER);
            uint256 shortAmount = hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    hyperdrive.latestCheckpoint() +
                        hyperdrive.getPoolConfig().positionDuration
                ),
                HEDGER
            ) - hedgerShortBalanceBefore;
            console.log("# Short");
            console.log(
                "fixed rate = %s%",
                (HyperdriveUtils.calculateAPRFromRealizedPrice(
                    shortAmount -
                        (shortPaid -
                            shortAmount.mulDown(
                                hyperdrive.getPoolConfig().fees.flat
                            )),
                    shortAmount,
                    hyperdrive.getPoolConfig().positionDuration.divDown(
                        365 days
                    )
                ) * 100).toString(18)
            );
            console.log("");
        }
        {
            uint256 longPaid = lpBaseBalanceBefore -
                IERC20(hyperdrive.baseToken()).balanceOf(LP);
            uint256 longAmount = hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Long,
                    hyperdrive.latestCheckpoint() +
                        hyperdrive.getPoolConfig().positionDuration
                ),
                LP
            ) - lpLongBalanceBefore;
            console.log("# Long");
            console.log(
                "fixed rate = %s%",
                (HyperdriveUtils.calculateAPRFromRealizedPrice(
                    longPaid - 3776809450,
                    longAmount,
                    hyperdrive.getPoolConfig().positionDuration.divDown(
                        365 days
                    )
                ) * 100).toString(18)
            );
        }
    }

    /// @dev Gets the APY implied by the rate.
    /// @param _rate The rate to compound.
    /// @return The APY implied by the rate.
    function _getAPY(uint256 _rate) internal pure returns (uint256) {
        uint256 firstTerm = _rate * 365 days;
        uint256 secondTerm = firstTerm.mulDivDown(firstTerm, 2e18);
        uint256 thirdTerm = secondTerm.mulDivDown(firstTerm, 3e18);

        return firstTerm + secondTerm + thirdTerm;
    }
}
