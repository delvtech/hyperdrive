// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveMatchingEngineV2 } from "../../../contracts/src/interfaces/IHyperdriveMatchingEngineV2.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMatchingEngineV2 } from "../../../contracts/src/matching/HyperdriveMatchingEngineV2.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

/// @dev This test suite tests if TOKEN_AMOUNT_BUFFER in HyperdriveMatchingEngineV2
///      is sufficient for successful minting operations across different pools.
contract TokenBufferTest is HyperdriveTest {
    using FixedPointMath for *;
    using HyperdriveUtils for *;
    using Lib for *;

    /// @dev The USDe/DAI Hyperdrive pool on mainnet.
    address internal constant USDE_DAI_POOL =
        0xA29A771683b4857bBd16e1e4f27D5B6bfF53209B;

    /// @dev The wstETH/USDC Hyperdrive pool on mainnet.
    address internal constant WSTETH_USDC_POOL =
        0xc8D47DE20F7053Cc02504600596A647A482Bbc46;

    /// @dev The DAI token address.
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    /// @dev The USDe token address.
    address internal constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;

    /// @dev The USDC token address.
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @dev The wstETH token address.
    address internal constant WSTETH =
        0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @dev Charlie will be the surplus recipient.
    address internal constant CHARLIE =
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    /// @dev The Hyperdrive matching engine that is deployed.
    IHyperdriveMatchingEngineV2 internal matchingEngine;

    /// @dev The USDe/DAI Hyperdrive instance.
    IHyperdrive internal usdeDaiHyperdrive;

    /// @dev The wstETH/USDC Hyperdrive instance.
    IHyperdrive internal wstethUsdcHyperdrive;

    /// @dev Counter for successful trades.
    uint256 public successfulTrades;

    /// @dev Counter for failed trades.
    uint256 public failedTrades;

    /// @dev Sets up the test harness on a mainnet fork.
    function setUp() public override __mainnet_fork(21_931_000) {
        // Run the higher-level setup logic.
        super.setUp();

        // Deploy the Hyperdrive matching engine.
        matchingEngine = IHyperdriveMatchingEngineV2(
            address(
                new HyperdriveMatchingEngineV2("Hyperdrive Matching Engine V2")
            )
        );

        // Set up the Hyperdrive instances.
        usdeDaiHyperdrive = IHyperdrive(USDE_DAI_POOL);
        wstethUsdcHyperdrive = IHyperdrive(WSTETH_USDC_POOL);

        // Fund Alice and Bob with tokens.
        deal(DAI, alice, 10_000_000e18);
        deal(USDE, alice, 10_000_000e18);
        deal(USDC, alice, 10_000_000e6);
        deal(WSTETH, alice, 1000e18);

        deal(DAI, bob, 10_000_000e18);
        deal(USDE, bob, 10_000_000e18);
        deal(USDC, bob, 10_000_000e6);
        deal(WSTETH, bob, 1000e18);

        // Approve tokens for Alice and Bob.
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
    }

    /// @dev Tests if TOKEN_AMOUNT_BUFFER is sufficient for USDe/DAI pool.
    /// This test uses fixed time and iterates through increasing bond amounts.
    function test_tokenBuffer_USDe_DAI() external {
        // Use a fixed time elapsed.
        uint256 timeElapsed = 1 days;

        // Advance time to simulate real-world conditions.
        vm.warp(block.timestamp + timeElapsed);

        // Initialize counters for this test.
        uint256 localSuccessfulTrades = 0;
        uint256 localFailedTrades = 0;

        // Start with 2000e18 and increment by 50000e18 each time, for 20 iterations.
        for (uint256 i = 0; i < 20; i++) {
            uint256 bondAmount = 2000e18 + (i * 50000e18);

            // Calculate fund amounts and make it more than sufficient.
            uint256 totalFunds = 2 * bondAmount;

            // Split funds between Alice and Bob.
            uint256 aliceFundAmount = totalFunds / 2;
            uint256 bobFundAmount = totalFunds - aliceFundAmount;

            // Create orders.
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

            // Sign orders.
            longOrder.signature = _signOrderIntent(longOrder, alicePK);
            shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

            // Try to match orders and record success/failure.
            try matchingEngine.matchOrders(longOrder, shortOrder, CHARLIE) {
                localSuccessfulTrades++;

                // Log successful trade.
                emit log_named_uint(
                    "Successful trade with bond amount",
                    bondAmount
                );

                // Verify positions were created.
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

                // Log failed trade.
                emit log_named_uint(
                    "Failed trade with bond amount",
                    bondAmount
                );
            }

            // Advance block to avoid nonce issues.
            vm.roll(block.number + 1);
        }

        // Log summary.
        emit log_named_uint(
            "USDe/DAI - Total successful trades",
            localSuccessfulTrades
        );
        emit log_named_uint(
            "USDe/DAI - Total failed trades",
            localFailedTrades
        );
    }

    /// @dev Helper function to create an order intent.
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

    /// @dev Helper function to sign an order intent.
    function _signOrderIntent(
        IHyperdriveMatchingEngineV2.OrderIntent memory _order,
        uint256 _privateKey
    ) internal view returns (bytes memory) {
        bytes32 orderHash = matchingEngine.hashOrderIntent(_order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, orderHash);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Helper function to approve tokens.
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
