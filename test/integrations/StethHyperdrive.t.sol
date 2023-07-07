// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { StethHyperdriveDeployer } from "contracts/src/factory/StethHyperdriveDeployer.sol";
import { StethHyperdriveFactory } from "contracts/src/factory/StethHyperdriveFactory.sol";
import { StethHyperdrive } from "contracts/src/instances/StethHyperdrive.sol";
import { StethHyperdriveDataProvider } from "contracts/src/instances/StethHyperdriveDataProvider.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract StethHyperdriveTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using stdStorage for StdStorage;
    using Lib for *;

    uint256 internal constant FIXED_RATE = 0.05e18;

    // The Lido storage location that tracks buffered ether reserves. We can
    // simulate the accrual of interest by updating this value.
    bytes32 internal constant BUFFERED_ETHER_POSITION =
        keccak256("lido.Lido.bufferedEther");

    ILido internal constant LIDO =
        ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    address internal STETH_WHALE = 0x1982b2F5814301d4e9a8b0201555376e62F82428;
    address internal ETH_WHALE = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    StethHyperdriveFactory factory;

    function setUp() public override __mainnet_fork(17_376_154) {
        super.setUp();

        // Deploy the StethHyperdrive deployer and factory.
        vm.startPrank(deployer);
        StethHyperdriveDeployer simpleDeployer = new StethHyperdriveDeployer(
            LIDO
        );
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ForwarderFactory();
        factory = new StethHyperdriveFactory(
            alice,
            simpleDeployer,
            bob,
            bob,
            IHyperdrive.Fees(0, 0, 0),
            defaults,
            address(forwarderFactory),
            forwarderFactory.ERC20LINK_HASH(),
            LIDO
        );

        // Alice deploys the hyperdrive instance.
        vm.stopPrank();
        vm.startPrank(alice);
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: IERC20(ETH),
            initialSharePrice: LIDO.getTotalPooledEther().divDown(
                LIDO.getTotalShares()
            ),
            minimumShareReserves: 1e15,
            positionDuration: POSITION_DURATION,
            checkpointDuration: CHECKPOINT_DURATION,
            timeStretch: HyperdriveUtils.calculateTimeStretch(0.05e18),
            governance: governance,
            feeCollector: feeCollector,
            fees: IHyperdrive.Fees({ curve: 0, flat: 0, governance: 0 }),
            oracleSize: ORACLE_SIZE,
            updateGap: UPDATE_GAP
        });
        uint256 contribution = 10_000e18;
        hyperdrive = factory.deployAndInitialize{ value: contribution }(
            config,
            new bytes32[](0),
            contribution,
            FIXED_RATE
        );

        // Ensure that Bob received the correct amount of LP tokens. She should
        // receive LP shares totaling the amount of shares that she contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's intial LP contribution.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            contribution.divDown(config.initialSharePrice) -
                2 *
                config.minimumShareReserves,
            1e5
        );

        // Fund the test accounts with stETH and ETH.
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = celine;
        fundAccounts(address(hyperdrive), IERC20(LIDO), STETH_WHALE, accounts);

        // Start recording event logs.
        vm.recordLogs();
    }

    /// Deploy and Initialize ///

    function test__steth__deployAndInitialize() external {
        vm.stopPrank();
        vm.startPrank(bob);
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: IERC20(ETH),
            initialSharePrice: LIDO.getTotalPooledEther().divDown(
                LIDO.getTotalShares()
            ),
            minimumShareReserves: 1e15,
            positionDuration: POSITION_DURATION,
            checkpointDuration: CHECKPOINT_DURATION,
            timeStretch: HyperdriveUtils.calculateTimeStretch(0.05e18),
            governance: governance,
            feeCollector: feeCollector,
            fees: IHyperdrive.Fees({ curve: 0, flat: 0, governance: 0 }),
            oracleSize: ORACLE_SIZE,
            updateGap: UPDATE_GAP
        });
        uint256 contribution = 10_000e18;
        hyperdrive = factory.deployAndInitialize{ value: contribution }(
            config,
            new bytes32[](0),
            contribution,
            FIXED_RATE
        );

        // Ensure that Bob received the correct amount of LP tokens. He should
        // receive LP shares totaling the amount of shares that he contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's intial LP contribution.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, bob),
            contribution.divDown(config.initialSharePrice) -
                2 *
                config.minimumShareReserves,
            1e5
        );

        // Ensure that the share reserves and LP total supply are equal and correct.
        assertApproxEqAbs(
            hyperdrive.getPoolInfo().shareReserves,
            contribution.mulDivDown(
                LIDO.getTotalShares(),
                LIDO.getTotalPooledEther()
            ),
            1
        );
        assertEq(
            hyperdrive.getPoolInfo().lpTotalSupply,
            hyperdrive.getPoolInfo().shareReserves - config.minimumShareReserves
        );

        // Verify that the correct events were emitted.
        verifyFactoryEvents(
            factory,
            bob,
            contribution,
            FIXED_RATE,
            config.minimumShareReserves,
            new bytes32[](0),
            1e5 // NOTE: We need some tolerance since stETH uses mulDivDown for share calculations.
        );
    }

    /// Price Per Share ///

    function test__pricePerShare(uint256 basePaid) external {
        // Ensure that the share price is the expected value.
        uint256 totalPooledEther = LIDO.getTotalPooledEther();
        uint256 totalShares = LIDO.getTotalShares();
        uint256 sharePrice = hyperdrive.getPoolInfo().sharePrice;
        assertEq(sharePrice, totalPooledEther.divDown(totalShares));

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of ETH. This will
        // be an approximation since Lido uses `mulDivDown` whereas this test
        // pre-computes the share price.
        basePaid = basePaid.normalizeToRange(
            0.00001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        uint256 hyperdriveSharesBefore = LIDO.sharesOf(address(hyperdrive));
        openLong(bob, basePaid);
        assertApproxEqAbs(
            LIDO.sharesOf(address(hyperdrive)),
            hyperdriveSharesBefore + basePaid.divDown(sharePrice),
            1e4
        );
    }

    /// Long ///

    function test_open_long_with_ETH(uint256 basePaid) external {
        // Get some balance information before the deposit.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a long by depositing ETH.
        basePaid = basePaid.normalizeToRange(
            0.00001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        openLong(bob, basePaid);

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyDeposit(
            bob,
            basePaid,
            true,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_open_long_failures() external {
        // Too little eth
        vm.expectRevert(IHyperdrive.TransferFailed.selector);
        hyperdrive.openLong{ value: 1e18 - 1 }(1e18, 0, bob, true);
        // Paying eth to the steth flow
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openLong{ value: 1 }(1e18, 0, bob, false);
    }

    function test_open_long_with_steth(uint256 basePaid) external {
        // Get some balance information before the deposit.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a long by depositing stETH.
        basePaid = basePaid.normalizeToRange(
            0.00001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        openLong(bob, basePaid, false);

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyDeposit(
            bob,
            basePaid,
            false,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_close_long_with_ETH(uint256 basePaid) external {
        // Bob opens a long.
        basePaid = basePaid.normalizeToRange(
            0.00001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Bob attempts to close his long with ETH as the target asset. This
        // fails since ETH isn't supported as a withdrawal asset.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        hyperdrive.closeLong(maturityTime, longAmount, 0, bob, true);
    }

    function test_close_long_with_steth(uint256 basePaid) external {
        // Bob opens a long.
        basePaid = basePaid.normalizeToRange(
            0.00001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Get some balance information before the withdrawal.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with stETH as the target asset.
        uint256 baseProceeds = closeLong(bob, maturityTime, longAmount, false);

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyStethWithdrawal(
            bob,
            baseProceeds,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// Short ///

    function test_open_short_with_ETH() external {
        // Get some balance information before the deposit.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );
        uint256 shortAmount = 0.001e18;
        // Bob opens a short by depositing ETH.
        shortAmount = shortAmount.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        uint256 balanceBefore = bob.balance;
        vm.deal(bob, shortAmount);
        (, uint256 basePaid) = openShort(bob, shortAmount);
        vm.deal(bob, balanceBefore - basePaid);
        // Ensure that the amount of base paid by the short is reasonable.
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            1e18
        );

        assertGt(basePaid, 0);
        assertGe(realizedRate, FIXED_RATE);

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyDeposit(
            bob,
            basePaid,
            true,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_open_short_with_steth(uint256 shortAmount) external {
        // Get some balance information before the deposit.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a short by depositing ETH.
        shortAmount = shortAmount.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        (, uint256 basePaid) = openShort(bob, shortAmount, false);

        // Ensure that the amount of base paid by the short is reasonable.
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            1e18
        );
        assertGt(basePaid, 0);
        assertGe(realizedRate, FIXED_RATE);

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyDeposit(
            bob,
            basePaid,
            false,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_close_short_with_ETH(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        // Bob opens a short.
        shortAmount = shortAmount.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        uint256 balanceBefore = bob.balance;
        vm.deal(bob, shortAmount);
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);
        vm.deal(bob, balanceBefore - basePaid);
        // The term passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Bob attempts to close his short with ETH as the target asset. This
        // fails since ETH isn't supported as a withdrawal asset.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        hyperdrive.closeShort(maturityTime, shortAmount, 0, bob, true);
    }

    function test_close_short_with_steth(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        // Bob opens a short.
        shortAmount = shortAmount.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        uint256 balanceBefore = bob.balance;
        vm.deal(bob, shortAmount);
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);
        vm.deal(bob, balanceBefore - basePaid);

        // The term passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Get some balance information before closing the short.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his short with stETH as the target asset. Bob's proceeds
        // should be the variable interest that accrued on the shorted bonds.
        (, int256 expectedBaseProceeds) = HyperdriveUtils.calculateInterest(
            shortAmount,
            variableRate,
            POSITION_DURATION
        );
        uint256 baseProceeds = closeShort(
            bob,
            maturityTime,
            shortAmount,
            false
        );
        assertApproxEqAbs(baseProceeds, uint256(expectedBaseProceeds), 1e9);

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyStethWithdrawal(
            bob,
            baseProceeds,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_attack_long_stEth() external {
        // Get some balance information before the deposit.
        LIDO.sharesOf(address(hyperdrive));

        // Bob opens a long by depositing ETH.
        uint256 basePaid = HyperdriveUtils.calculateMaxLong(hyperdrive);
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Get some balance information before the withdrawal.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with stETH as the target asset.
        uint256 baseProceeds = closeLong(bob, maturityTime, longAmount, false);

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyStethWithdrawal(
            bob,
            baseProceeds,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test__DOSStethHyperdriveCloseLong() external {
        //###########################################################################"
        //#### TEST: Denial of Service when LIDO's `TotalPooledEther` decreases. ####"
        //###########################################################################"

        // Ensure that the share price is the expected value.
        uint256 totalPooledEther = LIDO.getTotalPooledEther();
        uint256 totalShares = LIDO.getTotalShares();
        uint256 sharePrice = hyperdrive.getPoolInfo().sharePrice;
        assertEq(sharePrice, totalPooledEther.divDown(totalShares));

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of ETH. This will
        // be an approximation since Lido uses `mulDivDown` whereas this test
        // pre-computes the share price.
        uint256 basePaid = HyperdriveUtils.calculateMaxLong(hyperdrive) / 10;
        uint256 hyperdriveSharesBefore = LIDO.sharesOf(address(hyperdrive));

        // Bob calls openLong()
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);
        // Bob paid basePaid == ", basePaid);
        // Bob received longAmount == ", longAmount);
        assertApproxEqAbs(
            LIDO.sharesOf(address(hyperdrive)),
            hyperdriveSharesBefore + basePaid.divDown(sharePrice),
            1e4
        );

        // Get some balance information before the withdrawal.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );
        uint256 snapshotId = vm.snapshot();

        // Taking a Snapshot of the state
        // Bob closes his long with stETH as the target asset.
        uint256 baseProceeds = closeLong(
            bob,
            maturityTime,
            longAmount / 2,
            false
        );

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyStethWithdrawal(
            bob,
            baseProceeds,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
        // # Reverting to the saved state Snapshot #\n");
        vm.revertTo(snapshotId);

        // # Manipulating Lido's totalPooledEther : removing only 1e18
        bytes32 balanceBefore = vm.load(
            address(LIDO),
            bytes32(
                0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483
            )
        );
        // LIDO.CL_BALANCE_POSITION Before: ", uint(balanceBefore));
        uint(LIDO.getTotalPooledEther());
        hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            bob
        );
        vm.store(
            address(LIDO),
            bytes32(
                uint256(
                    0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483
                )
            ),
            bytes32(uint256(balanceBefore) - 1e18)
        );

        // Avoid Stack too deep
        uint256 maturityTime_ = maturityTime;
        uint256 longAmount_ = longAmount;

        vm.load(
            address(LIDO),
            bytes32(
                uint256(
                    0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483
                )
            )
        );

        // Bob closes his long with stETH as the target asset.
        hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime_),
            bob
        );

        // The fact that this doesn't revert means that it works
        closeLong(bob, maturityTime_, longAmount_ / 2, false);
    }

    function verifyDeposit(
        address trader,
        uint256 basePaid,
        bool asUnderlying,
        uint256 totalPooledEtherBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        if (asUnderlying) {
            // Ensure that the amount of pooled ether increased by the base paid.
            assertEq(
                LIDO.getTotalPooledEther(),
                totalPooledEtherBefore + basePaid
            );

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(bob.balance, traderBalancesBefore.ETHBalance - basePaid);

            // Ensure that the stETH balances were updated correctly.
            assertApproxEqAbs(
                LIDO.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.stethBalance + basePaid,
                1
            );
            assertEq(LIDO.balanceOf(trader), traderBalancesBefore.stethBalance);

            // Ensure that the stETH shares were updated correctly.
            uint256 expectedShares = basePaid.mulDivDown(
                totalSharesBefore,
                totalPooledEtherBefore
            );
            assertEq(LIDO.getTotalShares(), totalSharesBefore + expectedShares);
            assertEq(
                LIDO.sharesOf(address(hyperdrive)),
                hyperdriveBalancesBefore.stethShares + expectedShares
            );
            assertEq(LIDO.sharesOf(bob), traderBalancesBefore.stethShares);
        } else {
            // Ensure that the amount of pooled ether stays the same.
            assertEq(LIDO.getTotalPooledEther(), totalPooledEtherBefore);

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(trader.balance, traderBalancesBefore.ETHBalance);

            // Ensure that the stETH balances were updated correctly.
            assertApproxEqAbs(
                LIDO.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.stethBalance + basePaid,
                1
            );
            assertApproxEqAbs(
                LIDO.balanceOf(trader),
                traderBalancesBefore.stethBalance - basePaid,
                1
            );

            // Ensure that the stETH shares were updated correctly.
            uint256 expectedShares = basePaid.mulDivDown(
                totalSharesBefore,
                totalPooledEtherBefore
            );
            assertEq(LIDO.getTotalShares(), totalSharesBefore);
            assertEq(
                LIDO.sharesOf(address(hyperdrive)),
                hyperdriveBalancesBefore.stethShares + expectedShares
            );
            assertEq(
                LIDO.sharesOf(trader),
                traderBalancesBefore.stethShares - expectedShares
            );
        }
    }

    function verifyStethWithdrawal(
        address trader,
        uint256 baseProceeds,
        uint256 totalPooledEtherBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        // Ensure that the total pooled ether and shares stays the same.
        assertEq(LIDO.getTotalPooledEther(), totalPooledEtherBefore);
        assertApproxEqAbs(LIDO.getTotalShares(), totalSharesBefore, 1);

        // Ensure that the ETH balances were updated correctly.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(trader.balance, traderBalancesBefore.ETHBalance);

        // Ensure that the stETH balances were updated correctly.
        assertApproxEqAbs(
            LIDO.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.stethBalance - baseProceeds,
            1
        );
        assertApproxEqAbs(
            LIDO.balanceOf(trader),
            traderBalancesBefore.stethBalance + baseProceeds,
            1
        );

        // Ensure that the stETH shares were updated correctly.
        uint256 expectedShares = baseProceeds.mulDivDown(
            totalSharesBefore,
            totalPooledEtherBefore
        );
        assertApproxEqAbs(
            LIDO.sharesOf(address(hyperdrive)),
            hyperdriveBalancesBefore.stethShares - expectedShares,
            1
        );
        assertApproxEqAbs(
            LIDO.sharesOf(trader),
            traderBalancesBefore.stethShares + expectedShares,
            1
        );
    }

    /// Helpers ///

    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in Lido. Since the share price is given by
        // `getTotalPooledEther() / getTotalShares()`, we can simulate the
        // accrual of interest by multiplying the total pooled ether by the
        // variable rate plus one.
        uint256 bufferedEther = variableRate >= 0
            ? LIDO.getBufferedEther() +
                LIDO.getTotalPooledEther().mulDown(uint256(variableRate))
            : LIDO.getBufferedEther() -
                LIDO.getTotalPooledEther().mulDown(uint256(variableRate));
        vm.store(
            address(LIDO),
            BUFFERED_ETHER_POSITION,
            bytes32(bufferedEther)
        );
    }

    struct AccountBalances {
        uint256 stethShares;
        uint256 stethBalance;
        uint256 ETHBalance;
    }

    function getAccountBalances(
        address account
    ) internal view returns (AccountBalances memory) {
        return
            AccountBalances({
                stethShares: LIDO.sharesOf(account),
                stethBalance: LIDO.balanceOf(account),
                ETHBalance: account.balance
            });
    }
}
