// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { console2 as console } from "forge-std/console2.sol";
import { IMorpho, Id } from "morpho-blue/src/interfaces/IMorpho.sol";
import { MorphoBlueConversions } from "../../../contracts/src/instances/morpho-blue/MorphoBlueConversions.sol";
import { MorphoBlueHyperdrive } from "../../../contracts/src/instances/morpho-blue/MorphoBlueHyperdrive.sol";
import { MorphoBlueTarget0 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget0.sol";
import { MorphoBlueTarget1 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget1.sol";
import { MorphoBlueTarget2 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget2.sol";
import { MorphoBlueTarget3 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget3.sol";
import { MorphoBlueTarget4 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget4.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveMatchingEngine } from "../../../contracts/src/interfaces/IHyperdriveMatchingEngine.sol";
import { IMorphoBlueHyperdrive } from "../../../contracts/src/interfaces/IMorphoBlueHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMatchingEngine } from "../../../contracts/src/matching/HyperdriveMatchingEngine.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract JITLiquidityTest is HyperdriveTest {
    using FixedPointMath for *;
    using HyperdriveUtils for *;
    using Lib for *;

    /// @dev The address of the Morpho Blue pool.
    IMorpho internal constant MORPHO =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    /// @dev The whale addresses that have large balances of USDC.
    address[] internal WHALES = [
        0x54edC2D90BBfE50526E333c7FfEaD3B0F22D39F0,
        0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341,
        0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa
    ];

    /// @dev This is the initializer of the JIT pool.
    address internal constant INITIALIZER =
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    /// @dev This is the LP we'll use to provide JIT liquidity..
    address internal constant LP = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    /// @dev The private key of the LP.
    uint256 internal constant LP_PK =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /// @dev This is the address that will buy the short to hedge their borrow
    ///      position.
    address internal constant HEDGER =
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    /// @dev The private key of the Hedger.
    uint256 internal constant HEDGER_PK =
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;

    /// @dev The Hyperdrive matching engine that is deployed.
    IHyperdriveMatchingEngine internal matchingEngine;

    /// @dev Sets up the test harness on a mainnet fork and complete the
    ///      following actions:
    ///
    ///      1. Deploy the Morpho Blue cbBTC/USDC pool.
    ///      2. Deploy the Hyperdrive matching engine.
    ///      3. Set up whale accounts.
    ///      4. Initialize the Hyperdrive pool.
    function setUp() public override __mainnet_fork(21_224_875) {
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

        // Deploy the Hyperdrive matching engine.
        matchingEngine = IHyperdriveMatchingEngine(
            new HyperdriveMatchingEngine("Hyperdrive Matching Engine", MORPHO)
        );

        // Fund each of the accounts from the whale accounts.
        IERC20 baseToken = IERC20(hyperdrive.baseToken());
        address[] memory accounts = new address[](3);
        accounts[0] = INITIALIZER;
        accounts[1] = LP;
        accounts[2] = HEDGER;
        for (uint256 i = 0; i < WHALES.length; i++) {
            uint256 balance = baseToken.balanceOf(WHALES[i]);
            for (uint256 j = 0; j < accounts.length; j++) {
                vm.stopPrank();
                vm.startPrank(WHALES[i]);
                baseToken.transfer(accounts[j], balance / accounts.length);
            }
        }

        // Approve Hyperdrive and the matching engine with each of the whales.
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.stopPrank();
            vm.startPrank(accounts[i]);
            baseToken.approve(address(hyperdrive), type(uint256).max);
            baseToken.approve(address(matchingEngine), type(uint256).max);
        }

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

    // FIXME: Update this to work so that the short gets a rate of 5.11%.
    //
    /// @dev This test demonstrates that JIT liquidity can be provided using
    ///      free Morpho flash loans and includes some relevant statistics.
    function test_jit_liquidity_flash_loan() external {
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

        // FIXME: Add the DFB extra data.
        //
        // Create the two orders and sign them.
        IHyperdriveMatchingEngine.OrderIntent
            memory longOrder = IHyperdriveMatchingEngine.OrderIntent({
                hyperdrive: hyperdrive,
                amount: 2_439_250e6,
                slippageGuard: 2_499_999e6,
                minVaultSharePrice: hyperdrive
                    .getCheckpoint(hyperdrive.latestCheckpoint())
                    .vaultSharePrice,
                options: IHyperdrive.Options({
                    asBase: true,
                    destination: LP,
                    extraData: ""
                }),
                orderType: IHyperdriveMatchingEngine.OrderType.OpenLong,
                signature: new bytes(0),
                expiry: block.timestamp + 1 hours,
                salt: bytes32(uint256(0xdeadbeef))
            });
        IHyperdriveMatchingEngine.OrderIntent
            memory shortOrder = IHyperdriveMatchingEngine.OrderIntent({
                hyperdrive: hyperdrive,
                amount: 2_500_000e6,
                slippageGuard: 100_000e6,
                minVaultSharePrice: hyperdrive
                    .getCheckpoint(hyperdrive.latestCheckpoint())
                    .vaultSharePrice,
                options: IHyperdrive.Options({
                    asBase: true,
                    destination: HEDGER,
                    extraData: ""
                }),
                orderType: IHyperdriveMatchingEngine.OrderType.OpenShort,
                signature: new bytes(0),
                expiry: block.timestamp + 1 hours,
                salt: bytes32(uint256(0xbeefbabe))
            });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            LP_PK,
            matchingEngine.hashOrderIntent(longOrder)
        );
        longOrder.signature = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(
            HEDGER_PK,
            matchingEngine.hashOrderIntent(shortOrder)
        );
        shortOrder.signature = abi.encodePacked(r, s, v);

        // Match the two counterparties using flash loans.
        matchingEngine.matchOrders(
            // long
            LP,
            // short
            HEDGER,
            // long order
            longOrder,
            // short order
            shortOrder,
            // flash loan amount
            17_750_000e6,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            LP,
            false
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
            // FIXME: Send the fees to the long.
            console.log("# Long");
            console.log(
                "fixed rate = %s%",
                (HyperdriveUtils.calculateAPRFromRealizedPrice(
                    longPaid,
                    longAmount,
                    hyperdrive.getPoolConfig().positionDuration.divDown(
                        365 days
                    )
                ) * 100).toString(18)
            );
        }
    }

    // FIXME: Get this working. Something that would be cool is building this
    // into a CLI.
    //
    // FIXME: This isn't working correctly.
    //
    /// @dev This test does the math to compute the gap rate.
    // function test_gap_rate() external {
    //     // Get the Morpho interest rate model's rate at target.
    //     IMorphoBlueHyperdrive morphoBlueHyperdrive = IMorphoBlueHyperdrive(
    //         address(hyperdrive)
    //     );
    //     IAdaptiveCurveIrm irm = IAdaptiveCurveIrm(morphoBlueHyperdrive.irm());
    //     uint256 rateAtTarget = uint256(
    //         irm.rateAtTarget(morphoBlueHyperdrive.id())
    //     );
    //     console.log(
    //         "id = %s",
    //         vm.toString(Id.unwrap(morphoBlueHyperdrive.id()))
    //     );
    //     console.log("rateAtTarget = %s", rateAtTarget.toString(18));
    //
    //     // FIXME: Does this work? Double check the utilization.
    //     //
    //     // Get the average borrow rate if the pool is at a utilization of 35%.
    //     // We create a market that has this utilization and only specify the
    //     // parameters that are actually used in the calculation.
    //     uint256 borrowRate = irm.borrowRateView(
    //         MarketParams({
    //             loanToken: morphoBlueHyperdrive.baseToken(),
    //             collateralToken: morphoBlueHyperdrive.collateralToken(),
    //             oracle: morphoBlueHyperdrive.oracle(),
    //             irm: morphoBlueHyperdrive.irm(),
    //             lltv: morphoBlueHyperdrive.lltv()
    //         }),
    //         Market({
    //             totalSupplyAssets: 1e18,
    //             totalSupplyShares: 0,
    //             totalBorrowAssets: 0.35e18,
    //             totalBorrowShares: 0,
    //             lastUpdate: MORPHO.market(morphoBlueHyperdrive.id()).lastUpdate,
    //             fee: 0
    //         })
    //     );
    //     console.log("borrowRate = %s", borrowRate.toString(18));
    //
    //     // Since Morpho's fee is zero, the supply rate is just the borrow rate
    //     // scaled by the utilization.
    //     uint256 supplyRate = borrowRate.mulUp(0.35e18);
    //     console.log("supplyRate = %s", supplyRate.toString(18));
    //
    //     // Convert the borrow and supply rates to APYs.
    //     uint256 borrowAPY = _getAPY(borrowRate);
    //     console.log("borrowAPY = %s", borrowAPY.toString(18));
    //     uint256 supplyAPY = _getAPY(supplyRate);
    //     console.log("supplyAPY = %s", supplyAPY.toString(18));
    //
    //     // FIXME: Compute the gapAPY as borrowAPY - supplyAPY
    //     uint256 gapAPY = borrowAPY - supplyAPY;
    //     console.log("gapAPY = %s", gapAPY.toString(18));
    //     // FIXME: Look into the conversion that they do with the short rate.
    //     //        At a surface level, this looks really weird to me.
    // }

    // /// @dev Gets the APY implied by the rate.
    // /// @param _rate The rate to compound.
    // /// @return The APY implied by the rate.
    // function _getAPY(uint256 _rate) internal pure returns (uint256) {
    //     uint256 firstTerm = _rate * 365 days;
    //     uint256 secondTerm = firstTerm.mulDivDown(firstTerm, 2e18);
    //     uint256 thirdTerm = secondTerm.mulDivDown(firstTerm, 3e18);
    //
    //     return firstTerm + secondTerm + thirdTerm;
    // }
}
