// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { IMorpho, MarketParams } from "morpho-blue/src/interfaces/IMorpho.sol";
import { MarketParamsLib } from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { MorphoBlueConversions } from "../../../contracts/src/instances/morpho-blue/MorphoBlueConversions.sol";
import { MorphoBlueHyperdrive } from "../../../contracts/src/instances/morpho-blue/MorphoBlueHyperdrive.sol";
import { MorphoBlueTarget0 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget0.sol";
import { MorphoBlueTarget1 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget1.sol";
import { MorphoBlueTarget2 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget2.sol";
import { MorphoBlueTarget3 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget3.sol";
import { MorphoBlueTarget4 } from "../../../contracts/src/instances/morpho-blue/MorphoBlueTarget4.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveMatchingEngineV2 } from "../../../contracts/src/interfaces/IHyperdriveMatchingEngineV2.sol";
import { IMorphoBlueHyperdrive } from "../../../contracts/src/interfaces/IMorphoBlueHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMatchingEngineV2 } from "../../../contracts/src/matching/HyperdriveMatchingEngineV2.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";
import { IRestakeManager, IRenzoOracle } from "../../../contracts/src/interfaces/IRenzo.sol";
import { EzETHHyperdrive } from "../../../contracts/src/instances/ezETH/EzETHHyperdrive.sol";
import { EzETHTarget0 } from "../../../contracts/src/instances/ezETH/EzETHTarget0.sol";
import { EzETHTarget1 } from "../../../contracts/src/instances/ezETH/EzETHTarget1.sol";
import { EzETHTarget2 } from "../../../contracts/src/instances/ezETH/EzETHTarget2.sol";
import { EzETHTarget3 } from "../../../contracts/src/instances/ezETH/EzETHTarget3.sol";
import { EzETHTarget4 } from "../../../contracts/src/instances/ezETH/EzETHTarget4.sol";
import { EzETHConversions } from "../../../contracts/src/instances/ezETH/EzETHConversions.sol";

/// @dev This test suite tests if TOKEN_AMOUNT_BUFFER in HyperdriveMatchingEngineV2
///      is sufficient for successful minting operations across different pools.
contract TokenBufferTest is HyperdriveTest {
    using FixedPointMath for *;
    using HyperdriveUtils for *;
    using Lib for *;
    using MarketParamsLib for MarketParams;

    /// @dev The Morpho Blue address
    IMorpho internal constant MORPHO =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    /// @dev The DAI token address
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    /// @dev The USDe token address
    address internal constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;

    /// @dev The USDC token address
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @dev The wstETH token address
    address internal constant WSTETH =
        0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @dev The oracle for wstETH/USDC pool
    address internal constant WSTETH_ORACLE =
        0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2;

    /// @dev The oracle for USDe/DAI pool
    address internal constant USDE_ORACLE =
        0xaE4750d0813B5E37A51f7629beedd72AF1f9cA35;

    /// @dev The interest rate model for Morpho pools
    address internal constant IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;

    /// @dev The liquidation loan to value for Morpho pools
    uint256 internal constant LLTV = 860000000000000000;

    /// @dev Charlie will be the surplus recipient
    address internal constant CHARLIE =
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    /// @dev The initializer of the pools
    address internal constant INITIALIZER =
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    /// @dev The Hyperdrive matching engine that is deployed
    IHyperdriveMatchingEngineV2 internal matchingEngine;

    /// @dev The USDe/DAI Hyperdrive instance
    IHyperdrive internal usdeDaiHyperdrive;

    /// @dev The wstETH/USDC Hyperdrive instance
    IHyperdrive internal wstethUsdcHyperdrive;

    /// @dev The Renzo RestakeManager contract
    IRestakeManager internal constant RESTAKE_MANAGER =
        IRestakeManager(0x74a09653A083691711cF8215a6ab074BB4e99ef5);

    /// @dev The Renzo Oracle contract
    IRenzoOracle internal constant RENZO_ORACLE =
        IRenzoOracle(0x5a12796f7e7EBbbc8a402667d266d2e65A814042);

    /// @dev The ezETH token contract
    address internal constant EZETH =
        0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;

    /// @dev The placeholder address for ETH.
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev The EzETH Hyperdrive instance
    IHyperdrive internal ezethHyperdrive;

    /// @dev Sets up the test harness on a mainnet fork
    function setUp() public override __mainnet_fork(21_931_000) {
        // Run the higher-level setup logic
        super.setUp();

        // Deploy the Hyperdrive matching engine
        matchingEngine = IHyperdriveMatchingEngineV2(
            address(
                new HyperdriveMatchingEngineV2("Hyperdrive Matching Engine V2")
            )
        );

        // Deploy a Morpho Blue wstETH/USDC pool
        IMorphoBlueHyperdrive.MorphoBlueParams
            memory wstethParams = IMorphoBlueHyperdrive.MorphoBlueParams({
                morpho: MORPHO,
                collateralToken: WSTETH,
                oracle: WSTETH_ORACLE,
                irm: IRM,
                lltv: LLTV
            });

        IHyperdrive.PoolConfig memory wstethConfig = testConfig(
            0.04e18,
            182 days
        );
        wstethConfig.baseToken = IERC20(USDC);
        wstethConfig.vaultSharesToken = IERC20(address(0));
        wstethConfig.fees.curve = 0.01e18;
        wstethConfig.fees.flat = 0.0005e18;
        wstethConfig.fees.governanceLP = 0.15e18;
        wstethConfig.minimumShareReserves = 1e6;
        wstethConfig.minimumTransactionAmount = 1e6;
        wstethConfig.initialVaultSharePrice = MorphoBlueConversions
            .convertToBase(
                MORPHO,
                wstethConfig.baseToken,
                wstethParams.collateralToken,
                wstethParams.oracle,
                wstethParams.irm,
                wstethParams.lltv,
                ONE
            );

        wstethUsdcHyperdrive = IHyperdrive(
            address(
                new MorphoBlueHyperdrive(
                    "MorphoBlueHyperdrive-wstETH-USDC",
                    wstethConfig,
                    adminController,
                    address(
                        new MorphoBlueTarget0(
                            wstethConfig,
                            adminController,
                            wstethParams
                        )
                    ),
                    address(
                        new MorphoBlueTarget1(
                            wstethConfig,
                            adminController,
                            wstethParams
                        )
                    ),
                    address(
                        new MorphoBlueTarget2(
                            wstethConfig,
                            adminController,
                            wstethParams
                        )
                    ),
                    address(
                        new MorphoBlueTarget3(
                            wstethConfig,
                            adminController,
                            wstethParams
                        )
                    ),
                    address(
                        new MorphoBlueTarget4(
                            wstethConfig,
                            adminController,
                            wstethParams
                        )
                    ),
                    wstethParams
                )
            )
        );

        // Deploy a Morpho Blue USDe/DAI pool
        IMorphoBlueHyperdrive.MorphoBlueParams
            memory usdeParams = IMorphoBlueHyperdrive.MorphoBlueParams({
                morpho: MORPHO,
                collateralToken: USDE,
                oracle: USDE_ORACLE,
                irm: IRM,
                lltv: LLTV
            });

        IHyperdrive.PoolConfig memory usdeConfig = testConfig(
            0.04e18,
            182 days
        );
        usdeConfig.baseToken = IERC20(DAI);
        usdeConfig.vaultSharesToken = IERC20(address(0));
        usdeConfig.fees.curve = 0.01e18;
        usdeConfig.fees.flat = 0.0005e18;
        usdeConfig.fees.governanceLP = 0.15e18;
        usdeConfig.minimumShareReserves = 1e18;
        usdeConfig.minimumTransactionAmount = 1e18;
        usdeConfig.initialVaultSharePrice = MorphoBlueConversions.convertToBase(
            MORPHO,
            usdeConfig.baseToken,
            usdeParams.collateralToken,
            usdeParams.oracle,
            usdeParams.irm,
            usdeParams.lltv,
            ONE
        );

        usdeDaiHyperdrive = IHyperdrive(
            address(
                new MorphoBlueHyperdrive(
                    "MorphoBlueHyperdrive-USDe-DAI",
                    usdeConfig,
                    adminController,
                    address(
                        new MorphoBlueTarget0(
                            usdeConfig,
                            adminController,
                            usdeParams
                        )
                    ),
                    address(
                        new MorphoBlueTarget1(
                            usdeConfig,
                            adminController,
                            usdeParams
                        )
                    ),
                    address(
                        new MorphoBlueTarget2(
                            usdeConfig,
                            adminController,
                            usdeParams
                        )
                    ),
                    address(
                        new MorphoBlueTarget3(
                            usdeConfig,
                            adminController,
                            usdeParams
                        )
                    ),
                    address(
                        new MorphoBlueTarget4(
                            usdeConfig,
                            adminController,
                            usdeParams
                        )
                    ),
                    usdeParams
                )
            )
        );

        // Deploy an EzETH Hyperdrive pool
        IHyperdrive.PoolConfig memory ezethConfig = testConfig(
            0.04e18,
            15 days
        );
        ezethConfig.baseToken = IERC20(ETH);
        ezethConfig.vaultSharesToken = IERC20(EZETH);
        ezethConfig.fees.curve = 0.01e18;
        ezethConfig.fees.flat = 0.0005e18;
        ezethConfig.fees.governanceLP = 0.15e18;
        ezethConfig.minimumShareReserves = 1e15;
        ezethConfig.minimumTransactionAmount = 1e15;

        // Use EzETHConversions to calculate the initialVaultSharePrice
        ezethConfig.initialVaultSharePrice = EzETHConversions.convertToBase(
            RENZO_ORACLE,
            RESTAKE_MANAGER,
            IERC20(EZETH),
            ONE
        );

        emit log_named_uint(
            "EzETH Initial vault share price",
            ezethConfig.initialVaultSharePrice
        );

        ezethHyperdrive = IHyperdrive(
            address(
                new EzETHHyperdrive(
                    "EzETHHyperdrive",
                    ezethConfig,
                    adminController,
                    address(
                        new EzETHTarget0(
                            ezethConfig,
                            adminController,
                            RESTAKE_MANAGER
                        )
                    ),
                    address(
                        new EzETHTarget1(
                            ezethConfig,
                            adminController,
                            RESTAKE_MANAGER
                        )
                    ),
                    address(
                        new EzETHTarget2(
                            ezethConfig,
                            adminController,
                            RESTAKE_MANAGER
                        )
                    ),
                    address(
                        new EzETHTarget3(
                            ezethConfig,
                            adminController,
                            RESTAKE_MANAGER
                        )
                    ),
                    address(
                        new EzETHTarget4(
                            ezethConfig,
                            adminController,
                            RESTAKE_MANAGER
                        )
                    ),
                    RESTAKE_MANAGER
                )
            )
        );

        // Fund accounts with tokens
        deal(DAI, alice, 10_000_000e18);
        deal(USDE, alice, 10_000_000e18);
        deal(USDC, alice, 10_000_000e6);
        deal(WSTETH, alice, 1000e18);

        deal(DAI, bob, 10_000_000e18);
        deal(USDE, bob, 10_000_000e18);
        deal(USDC, bob, 10_000_000e6);
        deal(WSTETH, bob, 1000e18);

        deal(DAI, INITIALIZER, 10_000_000e18);
        deal(USDE, INITIALIZER, 10_000_000e18);
        deal(USDC, INITIALIZER, 10_000_000e6);
        deal(WSTETH, INITIALIZER, 1000e18);

        deal(EZETH, alice, 10_000e18);
        deal(EZETH, bob, 10_000e18);
        deal(EZETH, INITIALIZER, 10_000e18);

        // Approve tokens
        _approveTokens(alice, address(usdeDaiHyperdrive), IERC20(DAI));
        _approveTokens(alice, address(usdeDaiHyperdrive), IERC20(USDE));
        _approveTokens(alice, address(wstethUsdcHyperdrive), IERC20(USDC));
        _approveTokens(alice, address(wstethUsdcHyperdrive), IERC20(WSTETH));
        _approveTokens(alice, address(matchingEngine), IERC20(DAI));
        _approveTokens(alice, address(matchingEngine), IERC20(USDE));
        _approveTokens(alice, address(matchingEngine), IERC20(USDC));
        _approveTokens(alice, address(matchingEngine), IERC20(WSTETH));

        _approveTokens(bob, address(usdeDaiHyperdrive), IERC20(DAI));
        _approveTokens(bob, address(usdeDaiHyperdrive), IERC20(USDE));
        _approveTokens(bob, address(wstethUsdcHyperdrive), IERC20(USDC));
        _approveTokens(bob, address(wstethUsdcHyperdrive), IERC20(WSTETH));
        _approveTokens(bob, address(matchingEngine), IERC20(DAI));
        _approveTokens(bob, address(matchingEngine), IERC20(USDE));
        _approveTokens(bob, address(matchingEngine), IERC20(USDC));
        _approveTokens(bob, address(matchingEngine), IERC20(WSTETH));

        _approveTokens(INITIALIZER, address(usdeDaiHyperdrive), IERC20(DAI));
        _approveTokens(INITIALIZER, address(usdeDaiHyperdrive), IERC20(USDE));
        _approveTokens(
            INITIALIZER,
            address(wstethUsdcHyperdrive),
            IERC20(USDC)
        );
        _approveTokens(
            INITIALIZER,
            address(wstethUsdcHyperdrive),
            IERC20(WSTETH)
        );

        _approveTokens(alice, address(ezethHyperdrive), IERC20(EZETH));
        _approveTokens(bob, address(ezethHyperdrive), IERC20(EZETH));
        _approveTokens(INITIALIZER, address(ezethHyperdrive), IERC20(EZETH));
        _approveTokens(alice, address(matchingEngine), IERC20(EZETH));
        _approveTokens(bob, address(matchingEngine), IERC20(EZETH));

        // Initialize the Hyperdrive pools
        vm.startPrank(INITIALIZER);

        // Initialize wstETH/USDC pool
        wstethUsdcHyperdrive.initialize(
            1_000_000e6, // 1M USDC
            0.0361e18,
            IHyperdrive.Options({
                asBase: true,
                destination: INITIALIZER,
                extraData: ""
            })
        );

        // Initialize USDe/DAI pool
        usdeDaiHyperdrive.initialize(
            1_000_000e18, // 1M DAI
            0.0361e18,
            IHyperdrive.Options({
                asBase: true,
                destination: INITIALIZER,
                extraData: ""
            })
        );

        // Initialize EzETH Hyperdrive pool
        ezethHyperdrive.initialize(
            1_000e18, // 1000 ezETH
            0.0361e18,
            IHyperdrive.Options({
                asBase: false,
                destination: INITIALIZER,
                extraData: ""
            })
        );

        vm.stopPrank();
    }

    /// @dev Tests if TOKEN_AMOUNT_BUFFER is sufficient for USDe/DAI pool.
    /// This test uses fixed time and iterates through increasing bond amounts.
    function test_tokenBuffer_USDe_DAI() external {
        // Use a fixed time elapsed
        uint256 timeElapsed = 1 days;

        // Advance time to simulate real-world conditions
        vm.warp(block.timestamp + timeElapsed);

        // Initialize counters for this test
        uint256 localSuccessfulTrades = 0;
        uint256 localFailedTrades = 0;

        // Start with 20000e18 and increment by 50000e18 each time, for 20 iterations
        for (uint256 i = 0; i < 20; i++) {
            uint256 bondAmount = 20000e18 + (i * 50000e18);

            // Calculate fund amounts and double it to make it more than sufficient
            uint256 totalFunds = 2 * bondAmount;

            // Split funds between Alice and Bob
            uint256 aliceFundAmount = totalFunds / 2;
            uint256 bobFundAmount = totalFunds - aliceFundAmount;

            // Create orders
            IHyperdriveMatchingEngineV2.OrderIntent
                memory longOrder = _createOrderIntent(
                    alice,
                    bob,
                    usdeDaiHyperdrive,
                    aliceFundAmount,
                    bondAmount,
                    true, // asBase
                    IHyperdriveMatchingEngineV2.OrderType.OpenLong
                );

            IHyperdriveMatchingEngineV2.OrderIntent
                memory shortOrder = _createOrderIntent(
                    bob,
                    alice,
                    usdeDaiHyperdrive,
                    bobFundAmount,
                    bondAmount,
                    true, // asBase
                    IHyperdriveMatchingEngineV2.OrderType.OpenShort
                );

            // Sign orders
            longOrder.signature = _signOrderIntent(longOrder, alicePK);
            shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

            // Try to match orders and record success/failure
            try matchingEngine.matchOrders(longOrder, shortOrder, CHARLIE) {
                localSuccessfulTrades++;

                // Log successful trade
                emit log_named_uint(
                    "Successful trade with bond amount",
                    bondAmount
                );

                // Verify positions were created
                uint256 aliceLongBalance = usdeDaiHyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Long,
                        usdeDaiHyperdrive.latestCheckpoint() +
                            usdeDaiHyperdrive.getPoolConfig().positionDuration
                    ),
                    alice
                );

                uint256 bobShortBalance = usdeDaiHyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Short,
                        usdeDaiHyperdrive.latestCheckpoint() +
                            usdeDaiHyperdrive.getPoolConfig().positionDuration
                    ),
                    bob
                );

                assertGt(
                    aliceLongBalance,
                    0,
                    "Alice should have long position"
                );
                assertGt(bobShortBalance, 0, "Bob should have short position");
            } catch {
                localFailedTrades++;

                // Log failed trade
                emit log_named_uint(
                    "Failed trade with bond amount",
                    bondAmount
                );
            }

            // Advance block to avoid nonce issues
            vm.roll(block.number + 1);
        }

        // Log summary
        emit log_named_uint(
            "USDe/DAI - Total successful trades",
            localSuccessfulTrades
        );
        emit log_named_uint(
            "USDe/DAI - Total failed trades",
            localFailedTrades
        );
    }

    /// @dev Tests if TOKEN_AMOUNT_BUFFER is sufficient for wstETH/USDC pool.
    /// This test uses fixed time and iterates through increasing bond amounts.
    function test_tokenBuffer_wstETH_USDC() external {
        // Use a fixed time elapsed
        uint256 timeElapsed = 1 days;

        // Advance time to simulate real-world conditions
        vm.warp(block.timestamp + timeElapsed);

        // Initialize counters for this test
        uint256 localSuccessfulTrades = 0;
        uint256 localFailedTrades = 0;

        // Start with 2000e6 and increment by 5000e6 each time, for 20 iterations
        for (uint256 i = 0; i < 20; i++) {
            uint256 bondAmount = 2000e6 + (i * 5000e6);

            // Calculate fund amounts and make it more than sufficient
            uint256 totalFunds = 2 * bondAmount;

            // Split funds between Alice and Bob
            uint256 aliceFundAmount = totalFunds / 2;
            uint256 bobFundAmount = totalFunds - aliceFundAmount;

            // Create orders
            IHyperdriveMatchingEngineV2.OrderIntent
                memory longOrder = _createOrderIntent(
                    alice,
                    bob,
                    wstethUsdcHyperdrive,
                    aliceFundAmount,
                    bondAmount,
                    true, // asBase
                    IHyperdriveMatchingEngineV2.OrderType.OpenLong
                );

            IHyperdriveMatchingEngineV2.OrderIntent
                memory shortOrder = _createOrderIntent(
                    bob,
                    alice,
                    wstethUsdcHyperdrive,
                    bobFundAmount,
                    bondAmount,
                    true, // asBase
                    IHyperdriveMatchingEngineV2.OrderType.OpenShort
                );

            // Sign orders
            longOrder.signature = _signOrderIntent(longOrder, alicePK);
            shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

            // Try to match orders and record success/failure
            try matchingEngine.matchOrders(longOrder, shortOrder, CHARLIE) {
                localSuccessfulTrades++;

                // Log successful trade
                emit log_named_uint(
                    "Successful trade with bond amount",
                    bondAmount
                );

                // Verify positions were created
                uint256 aliceLongBalance = wstethUsdcHyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Long,
                        wstethUsdcHyperdrive.latestCheckpoint() +
                            wstethUsdcHyperdrive
                                .getPoolConfig()
                                .positionDuration
                    ),
                    alice
                );

                uint256 bobShortBalance = wstethUsdcHyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Short,
                        wstethUsdcHyperdrive.latestCheckpoint() +
                            wstethUsdcHyperdrive
                                .getPoolConfig()
                                .positionDuration
                    ),
                    bob
                );

                assertGt(
                    aliceLongBalance,
                    0,
                    "Alice should have long position"
                );
                assertGt(bobShortBalance, 0, "Bob should have short position");
            } catch {
                localFailedTrades++;

                // Log failed trade
                emit log_named_uint(
                    "Failed trade with bond amount",
                    bondAmount
                );
            }

            // Advance block to avoid nonce issues
            vm.roll(block.number + 1);
        }

        // Log summary
        emit log_named_uint(
            "wstETH/USDC - Total successful trades",
            localSuccessfulTrades
        );
        emit log_named_uint(
            "wstETH/USDC - Total failed trades",
            localFailedTrades
        );
    }

    /// @dev Tests if TOKEN_AMOUNT_BUFFER is sufficient for EzETH pool.
    /// This test uses fixed time and iterates through increasing bond amounts.
    function test_tokenBuffer_EzETH_notAsBase() external {
        // Use a fixed time elapsed
        uint256 timeElapsed = 1 days;

        // Advance time to simulate real-world conditions
        vm.warp(block.timestamp + timeElapsed);

        // Initialize counters for this test
        uint256 localSuccessfulTrades = 0;
        uint256 localFailedTrades = 0;

        // Start with 2e18 and increment by 5e18 each time, for 20 iterations
        for (uint256 i = 0; i < 20; i++) {
            uint256 bondAmount = 2e18 + (i * 5e18);

            // Calculate fund amounts and make it more than sufficient
            uint256 totalFunds = 2 * bondAmount;

            // Split funds between Alice and Bob
            uint256 aliceFundAmount = totalFunds / 2;
            uint256 bobFundAmount = totalFunds - aliceFundAmount;

            // Create orders
            IHyperdriveMatchingEngineV2.OrderIntent
                memory longOrder = _createOrderIntent(
                    alice,
                    bob,
                    ezethHyperdrive,
                    aliceFundAmount,
                    bondAmount,
                    false, // asBase
                    IHyperdriveMatchingEngineV2.OrderType.OpenLong
                );

            IHyperdriveMatchingEngineV2.OrderIntent
                memory shortOrder = _createOrderIntent(
                    bob,
                    alice,
                    ezethHyperdrive,
                    bobFundAmount,
                    bondAmount,
                    false, // asBase
                    IHyperdriveMatchingEngineV2.OrderType.OpenShort
                );

            // Sign orders
            longOrder.signature = _signOrderIntent(longOrder, alicePK);
            shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

            // Try to match orders and record success/failure
            try matchingEngine.matchOrders(longOrder, shortOrder, CHARLIE) {
                localSuccessfulTrades++;

                // Log successful trade
                emit log_named_uint(
                    "Successful trade with bond amount",
                    bondAmount
                );

                // Verify positions were created
                uint256 aliceLongBalance = ezethHyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Long,
                        ezethHyperdrive.latestCheckpoint() +
                            ezethHyperdrive.getPoolConfig().positionDuration
                    ),
                    alice
                );

                uint256 bobShortBalance = ezethHyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Short,
                        ezethHyperdrive.latestCheckpoint() +
                            ezethHyperdrive.getPoolConfig().positionDuration
                    ),
                    bob
                );

                assertGt(
                    aliceLongBalance,
                    0,
                    "Alice should have long position"
                );
                assertGt(bobShortBalance, 0, "Bob should have short position");
            } catch {
                localFailedTrades++;

                // Log failed trade
                emit log_named_uint(
                    "Failed trade with bond amount",
                    bondAmount
                );
            }

            // Advance block to avoid nonce issues
            vm.roll(block.number + 1);
        }

        // Log summary
        emit log_named_uint(
            "EzETH - Total successful trades",
            localSuccessfulTrades
        );
        emit log_named_uint("EzETH - Total failed trades", localFailedTrades);
    }

    /// @dev Helper function to create an order intent
    function _createOrderIntent(
        address _trader,
        address _counterparty,
        IHyperdrive _hyperdrive,
        uint256 _fundAmount,
        uint256 _bondAmount,
        bool _asBase,
        IHyperdriveMatchingEngineV2.OrderType _orderType
    ) internal view returns (IHyperdriveMatchingEngineV2.OrderIntent memory) {
        return
            IHyperdriveMatchingEngineV2.OrderIntent({
                trader: _trader,
                counterparty: _counterparty,
                hyperdrive: _hyperdrive,
                fundAmount: _fundAmount,
                bondAmount: _bondAmount,
                minVaultSharePrice: 0,
                options: IHyperdrive.Options({
                    asBase: _asBase,
                    destination: _trader,
                    extraData: ""
                }),
                orderType: _orderType,
                minMaturityTime: 0,
                maxMaturityTime: type(uint256).max,
                expiry: block.timestamp + 1 hours,
                salt: bytes32(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                _trader,
                                _orderType,
                                block.timestamp
                            )
                        )
                    )
                ),
                signature: new bytes(0)
            });
    }

    /// @dev Helper function to sign an order intent
    function _signOrderIntent(
        IHyperdriveMatchingEngineV2.OrderIntent memory _order,
        uint256 _privateKey
    ) internal view returns (bytes memory) {
        bytes32 orderHash = matchingEngine.hashOrderIntent(_order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, orderHash);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Helper function to approve tokens
    function _approveTokens(
        address _owner,
        address _spender,
        IERC20 _token
    ) internal {
        vm.startPrank(_owner);
        _token.approve(_spender, type(uint256).max);
        vm.stopPrank();
    }
}
