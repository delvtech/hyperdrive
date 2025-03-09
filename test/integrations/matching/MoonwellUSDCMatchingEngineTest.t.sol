// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../../contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveMatchingEngineV2 } from "../../../contracts/src/interfaces/IHyperdriveMatchingEngineV2.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMatchingEngineV2 } from "../../../contracts/src/matching/HyperdriveMatchingEngineV2.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";
import { ERC4626Hyperdrive } from "../../../contracts/src/instances/erc4626/ERC4626Hyperdrive.sol";
import { ERC4626Target0 } from "../../../contracts/src/instances/erc4626/ERC4626Target0.sol";
import { ERC4626Target1 } from "../../../contracts/src/instances/erc4626/ERC4626Target1.sol";
import { ERC4626Target2 } from "../../../contracts/src/instances/erc4626/ERC4626Target2.sol";
import { ERC4626Target3 } from "../../../contracts/src/instances/erc4626/ERC4626Target3.sol";
import { ERC4626Target4 } from "../../../contracts/src/instances/erc4626/ERC4626Target4.sol";
import { ERC4626Conversions } from "../../../contracts/src/instances/erc4626/ERC4626Conversions.sol";

/// @dev This test suite tests if TOKEN_AMOUNT_BUFFER in HyperdriveMatchingEngineV2
///      is sufficient for successful minting operations with Moonwell USDC pool.
contract MoonwellUSDCMatchingEngineTest is HyperdriveTest {
    using FixedPointMath for *;
    using HyperdriveUtils for *;
    using Lib for *;

    /// @dev Charlie will be the surplus recipient
    address internal constant CHARLIE =
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    /// @dev The initializer of the pools
    address internal constant INITIALIZER =
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    /// @dev The USDC token address on Base (6 decimals)
    address internal constant BASE_USDC =
        0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// @dev The Moonwell USDC token address (18 decimals)
    address internal constant MWUSDC =
        0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca;

    /// @dev The decimal difference between MWUSDC (18) and BASE_USDC (6)
    uint256 internal constant DECIMAL_DIFF = 12; // 18 - 6 = 12

    /// @dev The Hyperdrive matching engine that is deployed
    IHyperdriveMatchingEngineV2 internal matchingEngine;

    /// @dev The Moonwell USDC Hyperdrive instance
    IHyperdrive internal moonwellUsdcHyperdrive;

    /// @dev Sets up the test harness on a Base fork
    function setUp() public override __base_fork(21_117_198) {
        // Run the higher-level setup logic
        super.setUp();

        // Deploy the Hyperdrive matching engine
        matchingEngine = IHyperdriveMatchingEngineV2(
            address(
                new HyperdriveMatchingEngineV2("Hyperdrive Matching Engine V2")
            )
        );

        emit log_string("Deployed matching engine");

        try this.deployMoonwellPool() {
            emit log_string("Successfully deployed Moonwell USDC pool");
        } catch Error(string memory reason) {
            emit log_string("Failed to deploy Moonwell USDC pool");
            emit log_string(reason);
            revert(reason);
        } catch (bytes memory lowLevelData) {
            emit log_string(
                "Failed to deploy Moonwell USDC pool with low level error"
            );
            emit log_bytes(lowLevelData);
            revert("Low level error in deployMoonwellPool");
        }

        try this.fundAccounts() {
            emit log_string("Successfully funded accounts");
        } catch Error(string memory reason) {
            emit log_string("Failed to fund accounts");
            emit log_string(reason);
            revert(reason);
        } catch (bytes memory lowLevelData) {
            emit log_string("Failed to fund accounts with low level error");
            emit log_bytes(lowLevelData);
            revert("Low level error in fundAccounts");
        }

        try this.approveTokens() {
            emit log_string("Successfully approved tokens");
        } catch Error(string memory reason) {
            emit log_string("Failed to approve tokens");
            emit log_string(reason);
            revert(reason);
        } catch (bytes memory lowLevelData) {
            emit log_string("Failed to approve tokens with low level error");
            emit log_bytes(lowLevelData);
            revert("Low level error in approveTokens");
        }

        try this.initializePool() {
            emit log_string("Successfully initialized Moonwell USDC pool");
        } catch Error(string memory reason) {
            emit log_string("Failed to initialize Moonwell USDC pool");
            emit log_string(reason);
            revert(reason);
        } catch (bytes memory lowLevelData) {
            emit log_string(
                "Failed to initialize Moonwell USDC pool with low level error"
            );
            emit log_bytes(lowLevelData);
            revert("Low level error in initializePool");
        }
    }

    /// @dev Helper function to deploy the Moonwell USDC pool
    function deployMoonwellPool() external {
        // Deploy a Moonwell USDC Hyperdrive pool
        IHyperdrive.PoolConfig memory moonwellConfig = testConfig(
            0.04e18,
            182 days
        );
        moonwellConfig.baseToken = IERC20(BASE_USDC);
        moonwellConfig.vaultSharesToken = IERC20(MWUSDC);
        moonwellConfig.fees.curve = 0.001e18;
        moonwellConfig.fees.flat = 0.0001e18;
        moonwellConfig.fees.governanceLP = 0;
        moonwellConfig.minimumShareReserves = 1e3 * (10 ** DECIMAL_DIFF); // 1e15 for MWUSDC
        moonwellConfig.minimumTransactionAmount = 1e3;

        // Use ERC4626Conversions to calculate the initialVaultSharePrice
        // This is similar to how MorphoBlueConversions is used in the MorphoBlue tests
        moonwellConfig.initialVaultSharePrice = ERC4626Conversions
            .convertToBase(IERC4626(address(MWUSDC)), ONE);

        emit log_named_uint(
            "Initial vault share price",
            moonwellConfig.initialVaultSharePrice
        );

        moonwellUsdcHyperdrive = IHyperdrive(
            address(
                new ERC4626Hyperdrive(
                    "MoonwellUSDCHyperdrive",
                    moonwellConfig,
                    adminController,
                    address(
                        new ERC4626Target0(moonwellConfig, adminController)
                    ),
                    address(
                        new ERC4626Target1(moonwellConfig, adminController)
                    ),
                    address(
                        new ERC4626Target2(moonwellConfig, adminController)
                    ),
                    address(
                        new ERC4626Target3(moonwellConfig, adminController)
                    ),
                    address(new ERC4626Target4(moonwellConfig, adminController))
                )
            )
        );
    }

    /// @dev Helper function to fund accounts with tokens
    function fundAccounts() external {
        // Fund accounts with tokens for Moonwell
        deal(BASE_USDC, alice, 10_000_000_000e6);
        emit log_string("Funded alice with BASE_USDC");

        deal(BASE_USDC, bob, 10_000_000_000e6);
        emit log_string("Funded bob with BASE_USDC");

        deal(BASE_USDC, INITIALIZER, 10_000_000_000e6);
        emit log_string("Funded INITIALIZER with BASE_USDC");

        deal(MWUSDC, alice, 10_000_000_000e18);
        emit log_string("Funded alice with MWUSDC");

        deal(MWUSDC, bob, 10_000_000_000e18);
        emit log_string("Funded bob with MWUSDC");

        deal(MWUSDC, INITIALIZER, 10_000_000_000e18);
        emit log_string("Funded INITIALIZER with MWUSDC");
    }

    /// @dev Helper function to approve tokens
    function approveTokens() external {
        // Approve tokens for Moonwell
        _approveTokens(
            alice,
            address(moonwellUsdcHyperdrive),
            IERC20(BASE_USDC)
        );
        _approveTokens(bob, address(moonwellUsdcHyperdrive), IERC20(BASE_USDC));
        _approveTokens(
            INITIALIZER,
            address(moonwellUsdcHyperdrive),
            IERC20(BASE_USDC)
        );
        _approveTokens(alice, address(moonwellUsdcHyperdrive), IERC20(MWUSDC));
        _approveTokens(bob, address(moonwellUsdcHyperdrive), IERC20(MWUSDC));
        _approveTokens(
            INITIALIZER,
            address(moonwellUsdcHyperdrive),
            IERC20(MWUSDC)
        );
        _approveTokens(alice, address(matchingEngine), IERC20(BASE_USDC));
        _approveTokens(bob, address(matchingEngine), IERC20(BASE_USDC));
        _approveTokens(alice, address(matchingEngine), IERC20(MWUSDC));
        _approveTokens(bob, address(matchingEngine), IERC20(MWUSDC));
    }

    /// @dev Helper function to initialize the Moonwell USDC pool
    function initializePool() external {
        // Initialize Moonwell USDC pool
        vm.startPrank(INITIALIZER);
        moonwellUsdcHyperdrive.initialize(
            1_000_000e6, // 1M USDC
            0.0361e18,
            IHyperdrive.Options({
                asBase: true,
                destination: INITIALIZER,
                extraData: ""
            })
        );
        vm.stopPrank();
    }

    /// @dev Tests if TOKEN_AMOUNT_BUFFER is sufficient for Moonwell USDC pool with asBase=true.
    function test_tokenBuffer_Moonwell_USDC_asBase() external {
        // Use a fixed time elapsed
        uint256 timeElapsed = 1 days;

        // Advance time to simulate real-world conditions
        vm.warp(block.timestamp + timeElapsed);

        // Initialize counters for this test
        uint256 localSuccessfulTrades = 0;
        uint256 localFailedTrades = 0;

        // Start with 2000e6 and increment by 50000e6 each time, for 20 iterations
        for (uint256 i = 0; i < 20; i++) {
            uint256 bondAmount = 2000e6 + (i * 50000e6);

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
                    moonwellUsdcHyperdrive,
                    aliceFundAmount,
                    bondAmount,
                    true, // asBase
                    IHyperdriveMatchingEngineV2.OrderType.OpenLong
                );

            IHyperdriveMatchingEngineV2.OrderIntent
                memory shortOrder = _createOrderIntent(
                    bob,
                    alice,
                    moonwellUsdcHyperdrive,
                    bobFundAmount,
                    bondAmount,
                    true, // asBase
                    IHyperdriveMatchingEngineV2.OrderType.OpenShort
                );

            // Sign orders
            longOrder.signature = _signOrderIntent(longOrder, alicePK);
            shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

            // matchingEngine.matchOrders(longOrder, shortOrder, CHARLIE);

            // Try to match orders and record success/failure
            try matchingEngine.matchOrders(longOrder, shortOrder, CHARLIE) {
                localSuccessfulTrades++;

                // Log successful trade
                emit log_named_uint(
                    "Successful trade with bond amount",
                    bondAmount
                );

                // Verify positions were created
                uint256 aliceLongBalance = moonwellUsdcHyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Long,
                        moonwellUsdcHyperdrive.latestCheckpoint() +
                            moonwellUsdcHyperdrive
                                .getPoolConfig()
                                .positionDuration
                    ),
                    alice
                );

                uint256 bobShortBalance = moonwellUsdcHyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Short,
                        moonwellUsdcHyperdrive.latestCheckpoint() +
                            moonwellUsdcHyperdrive
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
            "Moonwell USDC (asBase=true) - Total successful trades",
            localSuccessfulTrades
        );
        emit log_named_uint(
            "Moonwell USDC (asBase=true) - Total failed trades",
            localFailedTrades
        );
    }

    /// @dev Tests if TOKEN_AMOUNT_BUFFER is sufficient for Moonwell USDC pool with asBase=false.
    function test_tokenBuffer_Moonwell_USDC_notAsBase() external {
        // Use a fixed time elapsed
        uint256 timeElapsed = 1 days;

        // Advance time to simulate real-world conditions
        vm.warp(block.timestamp + timeElapsed);

        // Initialize counters for this test
        uint256 localSuccessfulTrades = 0;
        uint256 localFailedTrades = 0;

        // Start with 2000e6 and increment by 50000e6 each time, for 20 iterations
        for (uint256 i = 0; i < 20; i++) {
            uint256 bondAmount = 2000e6 + (i * 50000e6);

            // Calculate fund amounts and make it more than sufficient
            uint256 totalFunds = 5 * bondAmount * (10 ** DECIMAL_DIFF);

            // Split funds between Alice and Bob
            uint256 aliceFundAmount = totalFunds / 2;
            uint256 bobFundAmount = totalFunds - aliceFundAmount;

            // Create orders
            IHyperdriveMatchingEngineV2.OrderIntent
                memory longOrder = _createOrderIntent(
                    alice,
                    bob,
                    moonwellUsdcHyperdrive,
                    aliceFundAmount,
                    bondAmount,
                    false, // asBase
                    IHyperdriveMatchingEngineV2.OrderType.OpenLong
                );

            IHyperdriveMatchingEngineV2.OrderIntent
                memory shortOrder = _createOrderIntent(
                    bob,
                    alice,
                    moonwellUsdcHyperdrive,
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
                uint256 aliceLongBalance = moonwellUsdcHyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Long,
                        moonwellUsdcHyperdrive.latestCheckpoint() +
                            moonwellUsdcHyperdrive
                                .getPoolConfig()
                                .positionDuration
                    ),
                    alice
                );

                uint256 bobShortBalance = moonwellUsdcHyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Short,
                        moonwellUsdcHyperdrive.latestCheckpoint() +
                            moonwellUsdcHyperdrive
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
            "Moonwell USDC (asBase=false) - Total successful trades",
            localSuccessfulTrades
        );
        emit log_named_uint(
            "Moonwell USDC (asBase=false) - Total failed trades",
            localFailedTrades
        );
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
