// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IMorpho, Market, MarketParams, Id } from "morpho-blue/src/interfaces/IMorpho.sol";
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
import { IHyperdriveMatchingEngine } from "../../../contracts/src/interfaces/IHyperdriveMatchingEngine.sol";
import { IMorphoBlueHyperdrive } from "../../../contracts/src/interfaces/IMorphoBlueHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMatchingEngine } from "../../../contracts/src/matching/HyperdriveMatchingEngine.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

/// @dev This test suite demonstrates how two traders can be matched directly
///      using the Hyperdrive Matching Engine.
contract DirectMatchTest is HyperdriveTest {
    using FixedPointMath for *;
    using HyperdriveUtils for *;
    using MarketParamsLib for MarketParams;
    using Lib for *;

    /// @dev The cbBTC address.
    address internal constant CB_BTC =
        0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    /// @dev The USDC address.
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @dev The address of the Morpho Blue pool.
    IMorpho internal constant MORPHO =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    /// @dev The address of the oracle for Morpho's cbBTC/USDC pool.
    address internal constant ORACLE =
        0xA6D6950c9F177F1De7f7757FB33539e3Ec60182a;

    /// @dev The address of the interest rate model for Morpho's cbBTC/USDC pool.
    address internal constant IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;

    /// @dev The liquidation loan to value for Morpho's cbBTC/USDC pool.
    uint256 internal constant LLTV = 860000000000000000;

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
    function setUp() public override __mainnet_fork(21_239_626) {
        // Run the higher-level setup logic.
        super.setUp();

        // Deploy a Morpho Blue cbBTC/USDC pool.
        IMorphoBlueHyperdrive.MorphoBlueParams
            memory params = IMorphoBlueHyperdrive.MorphoBlueParams({
                morpho: MORPHO,
                collateralToken: address(CB_BTC),
                oracle: address(ORACLE),
                irm: address(IRM),
                lltv: LLTV
            });
        IHyperdrive.PoolConfig memory config = testConfig(0.04e18, 182 days);
        config.baseToken = IERC20(USDC);
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

    /// @dev This test demonstrates matching two traders using the Hyperdrive
    ///      matching engine. The short receives a rate better than 5.11% and
    ///      the long receives a rate better than 5.02%. We add a random jitter
    ///      at the beginning of the test by advancing some time and accruing
    ///      interest. This demonstrates that orders aren't brittle and can be
    ///      signed and then executed several days later while interest is
    ///      accruing. Having this jitter does increase the spread between the
    ///      borrow and supply rates (the fixed lender would get a rate higher
    ///      than 5.09% without the jitter).
    /// @param _timeElapsed The random jitter to advance before executing the
    ///        trade.
    /// @param _variableRate The random amount of interest to accrue during the
    ///        jitter.
    function test_direct_match(
        uint256 _timeElapsed,
        uint256 _variableRate
    ) external {
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

        // Advance the time and accrue some interest. By fuzzing over the time
        // to advance and the variable rate, we demonstrate that the orders that
        // we create aren't "brittle." Once we find a set of orders that works
        // to directly match two parties, the orders should still work several
        // days later.
        _timeElapsed = _timeElapsed.normalizeToRange(0, 3 days);
        _variableRate = _variableRate.normalizeToRange(0, 0.1e18);
        advanceTime(_timeElapsed, int256(_variableRate));

        // Create the two orders and sign them.
        IHyperdriveMatchingEngine.OrderIntent
            memory longOrder = IHyperdriveMatchingEngine.OrderIntent({
                hyperdrive: hyperdrive,
                amount: 2_440_000e6,
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
                slippageGuard: 65_000e6,
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

        // Update the short order's extra data after signing. This simulates
        // what the DFB UI will do to ensure an up-to-date quote. Since the
        // extra data isn't baked into the hash, this will not cause issues with
        // signature verification.
        shortOrder.options.extraData = hex"deadbeefbabefade6660";

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
            18_500_000e6,
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

        // Create two more orders and sign them.
        longOrder = IHyperdriveMatchingEngine.OrderIntent({
            hyperdrive: hyperdrive,
            amount: 2_440_000e6,
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
            salt: bytes32(uint256(0xbeefdead))
        });
        shortOrder = IHyperdriveMatchingEngine.OrderIntent({
            hyperdrive: hyperdrive,
            amount: 2_500_000e6,
            slippageGuard: 65_000e6,
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
            salt: bytes32(uint256(0xbabebeef))
        });
        (v, r, s) = vm.sign(LP_PK, matchingEngine.hashOrderIntent(longOrder));
        longOrder.signature = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(
            HEDGER_PK,
            matchingEngine.hashOrderIntent(shortOrder)
        );
        shortOrder.signature = abi.encodePacked(r, s, v);

        // Update the short order's extra data after signing. This simulates
        // what the DFB UI will do to ensure an up-to-date quote. Since the
        // extra data isn't baked into the hash, this will not cause issues with
        // signature verification.
        shortOrder.options.extraData = hex"deadbeefbabefade6660";

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
            18_500_000e6,
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

        // Ensure that the short received 5,000,000 bonds and that their rate
        // was lower than 5.11%.
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
            uint256 prepaidInterest = shortAmount.mulDown(
                hyperdrive.getPoolInfo().vaultSharePrice -
                    hyperdrive
                        .getCheckpoint(hyperdrive.latestCheckpoint())
                        .vaultSharePrice
            );
            shortPaid -= prepaidInterest;
            uint256 shortFixedRate = HyperdriveUtils
                .calculateAPRFromRealizedPrice(
                    shortAmount -
                        (shortPaid -
                            shortAmount.mulDown(
                                hyperdrive.getPoolConfig().fees.flat
                            )),
                    shortAmount,
                    hyperdrive.getPoolConfig().positionDuration.divDown(
                        365 days
                    )
                );
            assertEq(shortAmount, 5_000_000e6);
            assertLt(shortFixedRate, 0.0511e18);
        }

        // Ensure that the long received 5,000,000 or more bonds and that their
        // rate was higher than 5.02%.
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
            uint256 longFixedRate = HyperdriveUtils
                .calculateAPRFromRealizedPrice(
                    longPaid,
                    longAmount,
                    hyperdrive.getPoolConfig().positionDuration.divDown(
                        365 days
                    )
                );
            assertGt(longAmount, 5_000_000e6);
            assertGt(longFixedRate, 0.0502e18);
        }
    }

    /// @dev Advance time and accrue interest.
    /// @param timeDelta The time to advance.
    /// @param variableRate The variable rate.
    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in the Morpho market. This amounts to manually
        // updating the total supply assets and the last update time.
        Id marketId = MarketParams({
            loanToken: USDC,
            collateralToken: CB_BTC,
            oracle: ORACLE,
            irm: IRM,
            lltv: LLTV
        }).id();
        Market memory market = MORPHO.market(marketId);
        (uint256 totalSupplyAssets, ) = uint256(market.totalSupplyAssets)
            .calculateInterest(variableRate, timeDelta);
        bytes32 marketLocation = keccak256(abi.encode(marketId, 3));
        vm.store(
            address(MORPHO),
            marketLocation,
            bytes32(
                (uint256(market.totalSupplyShares) << 128) | totalSupplyAssets
            )
        );
        vm.store(
            address(MORPHO),
            bytes32(uint256(marketLocation) + 2),
            bytes32((uint256(market.fee) << 128) | uint256(block.timestamp))
        );

        // In order to prevent transfers from failing, we also need to increase
        // the DAI balance of the Morpho vault to match the total assets.
        mintBaseTokens(address(MORPHO), totalSupplyAssets);
    }

    /// @dev Mints base tokens to a specified account.
    /// @param _recipient The recipient of the minted tokens.
    /// @param _amount The amount of tokens to mint.
    function mintBaseTokens(address _recipient, uint256 _amount) internal {
        bytes32 balanceLocation = keccak256(abi.encode(address(_recipient), 9));
        vm.store(USDC, balanceLocation, bytes32(_amount));
    }
}
