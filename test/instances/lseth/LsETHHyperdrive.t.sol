// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IRiverV1 } from "contracts/src/interfaces/lseth/IRiverV1.sol";
import { Lib } from "test/utils/Lib.sol";
import { LsETHHyperdriveCoreDeployer } from "contracts/src/deployers/lseth/LsETHHyperdriveCoreDeployer.sol";
import { LsETHHyperdriveDeployerCoordinator } from "contracts/src/deployers/lseth/LsETHHyperdriveDeployerCoordinator.sol";
import { LsETHTarget0Deployer } from "contracts/src/deployers/lseth/LsETHTarget0Deployer.sol";
import { LsETHTarget1Deployer } from "contracts/src/deployers/lseth/LsETHTarget1Deployer.sol";
import { LsETHTarget2Deployer } from "contracts/src/deployers/lseth/LsETHTarget2Deployer.sol";
import { LsETHTarget3Deployer } from "contracts/src/deployers/lseth/LsETHTarget3Deployer.sol";
import { LsETHTarget4Deployer } from "contracts/src/deployers/lseth/LsETHTarget4Deployer.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import "forge-std/console.sol";

contract LsETHHyperdriveTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    uint256 internal constant FIXED_RATE = 0.05e18;

    bytes32
        internal constant LAST_CONSENSUS_LAYER_REPORT_VALIDATOR_BALANCE_SLOT =
        bytes32(uint256(keccak256("river.state.lastConsensusLayerReport")));

    IRiverV1 internal constant RIVER =
        IRiverV1(0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549);

    address internal LSETH_WHALE = 0xF047ab4c75cebf0eB9ed34Ae2c186f3611aEAfa6;
    address internal LSETH_WHALE_2 = 0xAe60d8180437b5C34bB956822ac2710972584473;
    address internal ETH_WHALE = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    HyperdriveFactory factory;
    address deployerCoordinator;

    function setUp() public override __mainnet_fork(19_429_100) {
        super.setUp();

        // Fund the test accounts with LsETH and ETH.
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = celine;
        fundAccounts(
            address(hyperdrive),
            IERC20(0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549),
            LSETH_WHALE,
            accounts
        );
        fundAccounts(
            address(hyperdrive),
            IERC20(0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549),
            LSETH_WHALE_2,
            accounts
        );
        vm.deal(alice, 20_000e18);
        vm.deal(bob, 20_000e18);
        vm.deal(celine, 20_000e18);

        // Deploy the hyperdrive factory.
        vm.startPrank(deployer);
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ERC20ForwarderFactory();
        factory = new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: celine,
                sweepCollector: sweepCollector,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimeStretchAPR: 0.005e18,
                maxTimeStretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                }),
                maxFees: IHyperdrive.Fees({
                    curve: ONE,
                    flat: ONE,
                    governanceLP: ONE,
                    governanceZombie: ONE
                }),
                linkerFactory: address(forwarderFactory),
                linkerCodeHash: forwarderFactory.ERC20LINK_HASH()
            })
        );

        // Deploy the hyperdrive deployers and register the deployer coordinator
        // in the factory.
        vm.stopPrank();
        vm.startPrank(alice);
        deployerCoordinator = address(
            new LsETHHyperdriveDeployerCoordinator(
                address(new LsETHHyperdriveCoreDeployer(RIVER)),
                address(new LsETHTarget0Deployer(RIVER)),
                address(new LsETHTarget1Deployer(RIVER)),
                address(new LsETHTarget2Deployer(RIVER)),
                address(new LsETHTarget3Deployer(RIVER)),
                address(new LsETHTarget4Deployer(RIVER)),
                RIVER
            )
        );
        factory.addDeployerCoordinator(address(deployerCoordinator));

        // Alice deploys the hyperdrive instance.
        IHyperdrive.PoolDeployConfig memory config = IHyperdrive
            .PoolDeployConfig({
                baseToken: IERC20(ETH),
                linkerFactory: factory.linkerFactory(),
                linkerCodeHash: factory.linkerCodeHash(),
                minimumShareReserves: 1e15,
                minimumTransactionAmount: 1e15,
                positionDuration: POSITION_DURATION,
                checkpointDuration: CHECKPOINT_DURATION,
                timeStretch: 0,
                governance: factory.hyperdriveGovernance(),
                feeCollector: factory.feeCollector(),
                sweepCollector: factory.sweepCollector(),
                fees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                })
            });
        uint256 contribution = 5_000e18;
        factory.deployTarget(
            bytes32(uint256(0xdeadbeef)),
            deployerCoordinator,
            config,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            0,
            bytes32(uint256(0xdeadbabe))
        );
        factory.deployTarget(
            bytes32(uint256(0xdeadbeef)),
            deployerCoordinator,
            config,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            1,
            bytes32(uint256(0xdeadbabe))
        );
        factory.deployTarget(
            bytes32(uint256(0xdeadbeef)),
            deployerCoordinator,
            config,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            2,
            bytes32(uint256(0xdeadbabe))
        );
        factory.deployTarget(
            bytes32(uint256(0xdeadbeef)),
            deployerCoordinator,
            config,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            3,
            bytes32(uint256(0xdeadbabe))
        );
        factory.deployTarget(
            bytes32(uint256(0xdeadbeef)),
            deployerCoordinator,
            config,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            4,
            bytes32(uint256(0xdeadbabe))
        );
        RIVER.approve(deployerCoordinator, contribution);
        hyperdrive = factory.deployAndInitialize(
            bytes32(uint256(0xdeadbeef)),
            deployerCoordinator,
            config,
            new bytes(0),
            contribution,
            FIXED_RATE,
            FIXED_RATE,
            IHyperdrive.Options({
                asBase: false,
                destination: alice,
                extraData: new bytes(0)
            }),
            bytes32(uint256(0xdeadbabe))
        );

        // Ensure that Alice received the correct amount of LP tokens. She should
        // receive LP shares totaling the amount of shares that she contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            contribution - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
            1e5
        );

        // Start recording event logs.
        vm.recordLogs();
    }

    /// Deploy and Initialize ///

    function test__reth__deployAndInitialize() external {
        // Deploy and Initialize the rETH hyperdrive instance. Excess ether is
        // sent, and should be returned to the sender.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bobBalanceBefore = address(bob).balance;
        IHyperdrive.PoolDeployConfig memory config = IHyperdrive
            .PoolDeployConfig({
                baseToken: IERC20(ETH),
                governance: factory.hyperdriveGovernance(),
                feeCollector: factory.feeCollector(),
                sweepCollector: factory.sweepCollector(),
                linkerFactory: factory.linkerFactory(),
                linkerCodeHash: factory.linkerCodeHash(),
                minimumShareReserves: 1e15,
                minimumTransactionAmount: 1e15,
                positionDuration: POSITION_DURATION,
                checkpointDuration: CHECKPOINT_DURATION,
                timeStretch: 0,
                fees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                })
            });
        uint256 contribution = 5_000e18;
        factory.deployTarget(
            bytes32(uint256(0xbeefbabe)),
            deployerCoordinator,
            config,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            0,
            bytes32(uint256(0xdeadfade))
        );
        factory.deployTarget(
            bytes32(uint256(0xbeefbabe)),
            deployerCoordinator,
            config,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            1,
            bytes32(uint256(0xdeadfade))
        );
        factory.deployTarget(
            bytes32(uint256(0xbeefbabe)),
            deployerCoordinator,
            config,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            2,
            bytes32(uint256(0xdeadfade))
        );
        factory.deployTarget(
            bytes32(uint256(0xbeefbabe)),
            deployerCoordinator,
            config,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            3,
            bytes32(uint256(0xdeadfade))
        );
        factory.deployTarget(
            bytes32(uint256(0xbeefbabe)),
            deployerCoordinator,
            config,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            4,
            bytes32(uint256(0xdeadfade))
        );
        RIVER.approve(deployerCoordinator, contribution);
        hyperdrive = factory.deployAndInitialize(
            bytes32(uint256(0xbeefbabe)),
            address(deployerCoordinator),
            config,
            new bytes(0),
            contribution,
            FIXED_RATE,
            FIXED_RATE,
            IHyperdrive.Options({
                asBase: false,
                destination: bob,
                extraData: new bytes(0)
            }),
            bytes32(uint256(0xdeadfade))
        );
        assertEq(address(bob).balance, bobBalanceBefore);

        // Ensure that the decimals are set correctly.
        assertEq(hyperdrive.decimals(), 18);

        // Ensure that Bob received the correct amount of LP tokens. He should
        // receive LP shares totaling the amount of shares that he contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, bob),
            contribution - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
            1e5
        );

        // Ensure that the share reserves and LP total supply are equal and correct.
        assertApproxEqAbs(
            hyperdrive.getPoolInfo().shareReserves,
            contribution,
            1
        );
        assertEq(
            hyperdrive.getPoolInfo().lpTotalSupply,
            hyperdrive.getPoolInfo().shareReserves - config.minimumShareReserves
        );

        // Verify that the correct events were emitted.
        verifyFactoryEvents(
            deployerCoordinator,
            hyperdrive,
            bob,
            contribution,
            FIXED_RATE,
            false,
            config.minimumShareReserves,
            new bytes(0),
            // NOTE: Tolerance since rETH uses mulDivDown for share calculations.
            1e5
        );
    }

    /// Price Per Share ///

    function test_pricePerVaultShare(uint256 basePaid) external {
        // Ensure the share prices are equal upon market inception.
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, RIVER.underlyingBalanceFromShares(1e18));

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of lsETH.
        vm.startPrank(bob);
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        uint256 hyperdriveSharesBefore = RIVER.balanceOf(address(hyperdrive));
        uint256 sharesPaid = RIVER.sharesFromUnderlyingBalance(basePaid);
        RIVER.approve(address(hyperdrive), sharesPaid);
        openLong(bob, sharesPaid, false);
        assertEq(
            RIVER.balanceOf(address(hyperdrive)),
            hyperdriveSharesBefore + sharesPaid
        );
    }

    // /// Long ///

    function test_open_long_with_eth(uint256 basePaid) external {
        // Bob opens a long by depositing ETH. This is not allowed and
        // should throw an unsupported token exception.
        vm.startPrank(bob);
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        hyperdrive.openLong{ value: basePaid }(
            basePaid,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_open_long_with_lseth(uint256 basePaid) external {
        // Get some balance information before the deposit.
        uint256 totalSharesBefore = RIVER.totalSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Calculate the maximum amount of basePaid we can test. The limit is
        // either the max long that Hyperdrive can open or the amount of lsETH
        // tokens the trader has.
        uint256 maxLongAmount = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEthAmount = RIVER.underlyingBalanceFromShares(
            RIVER.balanceOf(bob)
        );

        // Bob opens a long by depositing lsETH.
        vm.startPrank(bob);
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxLongAmount > maxEthAmount ? maxEthAmount : maxLongAmount
        );
        uint256 sharesPaid = RIVER.sharesFromUnderlyingBalance(basePaid);
        RIVER.approve(address(hyperdrive), sharesPaid);
        openLong(bob, sharesPaid, false);

        // Ensure that River aggregates and the token balances were updated
        // correctly during the trade.
        verifyDeposit(
            bob,
            sharesPaid,
            false,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_open_long_refunds() external {
        vm.startPrank(bob);

        // Ensure that the refund fails when Bob sends excess ETH
        // when opening a long with "asBase" set to true.
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        hyperdrive.openLong{ value: 2e18 }(
            1e18,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Ensure that Bob receives a refund when he opens a long with "asBase"
        // set to false and sends ETH to the contract.
        uint256 sharesPaid = 1e18;
        uint256 ethBalanceBefore = address(bob).balance;
        RIVER.approve(address(hyperdrive), sharesPaid);
        hyperdrive.openLong{ value: 0.5e18 }(
            sharesPaid,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: false,
                extraData: new bytes(0)
            })
        );
        assertEq(address(bob).balance, ethBalanceBefore);
    }

    function test_close_long_with_eth(
        uint256 basePaid,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION, 0.05e18);
        vm.startPrank(bob);

        // Calculate the maximum amount of basePaid we can test. The limit is
        // either the max long that Hyperdrive can open or the amount of lsETH
        // tokens the trader has.
        uint256 maxLongAmount = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEthAmount = RIVER.underlyingBalanceFromShares(
            RIVER.balanceOf(bob)
        );

        // Bob opens a long, paying with lsETH.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxLongAmount > maxEthAmount ? maxEthAmount : maxLongAmount
        );
        uint256 sharesPaid = RIVER.sharesFromUnderlyingBalance(basePaid);
        RIVER.approve(address(hyperdrive), sharesPaid);
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            sharesPaid,
            false
        );

        // The term passes and some interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        hyperdrive.closeLong(
            maturityTime,
            longAmount,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_close_long_with_lseth(
        uint256 basePaid,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION, 0.05e18);
        vm.startPrank(bob);

        // Calculate the maximum amount of basePaid we can test. The limit is
        // either the max long that Hyperdrive can open or the amount of RETH
        // tokens the trader has.
        uint256 maxLongAmount = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEthAmount = RIVER.underlyingBalanceFromShares(
            RIVER.balanceOf(bob)
        );

        // Bob opens a long by depositing lsETH.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxLongAmount > maxEthAmount ? maxEthAmount : maxLongAmount
        );
        uint256 sharesPaid = RIVER.sharesFromUnderlyingBalance(basePaid);
        RIVER.approve(address(hyperdrive), sharesPaid);
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            sharesPaid,
            false
        );

        // The term passes and some interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Get some balance information before the withdrawal.
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );
        uint256 totalLsethSupplyBefore = RIVER.totalSupply();

        // Bob closes his long with lsETH as the target asset.
        uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
        uint256 baseProceeds = RIVER.underlyingBalanceFromShares(shareProceeds);

        // Ensure Bob is credited the correct amount of bonds.
        assertLe(baseProceeds, longAmount);
        assertApproxEqAbs(baseProceeds, longAmount, 10);

        // Ensure that River aggregates and the token balances were updated
        // correctly during the trade.
        verifyLsethWithdrawal(
            bob,
            shareProceeds,
            false,
            totalLsethSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// Short ///

    function test_open_short_with_eth(uint256 shortAmount) external {
        // Bob opens a short by depositing ETH. This is not allowed and
        // should throw an unsupported token exception.
        shortAmount = shortAmount.normalizeToRange(
            100 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        vm.deal(bob, shortAmount);
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        hyperdrive.openShort{ value: shortAmount }(
            shortAmount,
            shortAmount,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_open_short_with_lseth(uint256 shortAmount) external {
        // Get some balance information before the deposit.
        uint256 totalLsethSupplyBefore = RIVER.totalSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a short by depositing lsETH.
        vm.startPrank(bob);
        shortAmount = shortAmount.normalizeToRange(
            100 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        RIVER.approve(address(hyperdrive), shortAmount);
        (, uint256 sharesPaid) = openShort(bob, shortAmount, false);
        uint256 basePaid = RIVER.underlyingBalanceFromShares(sharesPaid);

        // Ensure that the amount of base paid by the short is reasonable.
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            1e18
        );
        assertGt(basePaid, 0);
        assertGe(realizedRate, FIXED_RATE);

        // Ensure that River aggregates and the token balances were updated
        // correctly during the trade.
        verifyDeposit(
            bob,
            sharesPaid,
            false,
            totalLsethSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_open_short_refunds() external {
        vm.startPrank(bob);

        // Ensure that the refund fails when Bob sends excess ETH
        // when opening a short with "asBase" set to true.
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        (, uint256 basePaid) = hyperdrive.openShort{ value: 2e18 }(
            1e18,
            1e18,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Ensure that Bob receives a refund when he opens a short with "asBase"
        // set to false and sends ETH to the contract.
        uint256 sharesPaid = 1e18;
        uint256 ethBalanceBefore = address(bob).balance;
        RIVER.approve(address(hyperdrive), sharesPaid);
        hyperdrive.openShort(
            sharesPaid,
            sharesPaid,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: false,
                extraData: new bytes(0)
            })
        );
        assertEq(address(bob).balance, ethBalanceBefore);
    }

    function testFail_close_short_with_eth(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION, 0.05e18);

        // Bob opens a short by depositing lsETH.
        vm.startPrank(bob);
        shortAmount = shortAmount.normalizeToRange(
            100 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        RIVER.approve(address(hyperdrive), shortAmount);
        (uint256 maturityTime, uint256 sharesPaid) = openShort(
            bob,
            shortAmount,
            false
        );

        // The term passes and interest accrues.
        uint256 startingVaultSharePrice = hyperdrive
            .getPoolInfo()
            .vaultSharePrice;
        // todo ask alex if this value is 0 test case does not
        // fail bc we are withdrawing 0 shares so no error
        // but this works when we are closing short as shares
        // even if no interset accrual
        variableRate = variableRate.normalizeToRange(1e18, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Get some balance information before closing the short.
        // uint256 totalLsetSupplyBefore = RIVER.totalSupply();
        // AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        // AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
        //     address(hyperdrive)
        // );

        // Bob closes his short with rETH as the target asset. Bob's proceeds
        // should be the variable interest that accrued on the shorted bonds.
        // uint256 expectedBaseProceeds = shortAmount.mulDivDown(
        //     hyperdrive.getPoolInfo().vaultSharePrice - startingVaultSharePrice,
        //     startingVaultSharePrice
        // );

        // vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        hyperdrive.closeShort(
            maturityTime,
            shortAmount,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // assertLe(baseProceeds, expectedBaseProceeds);
        // assertApproxEqAbs(baseProceeds, expectedBaseProceeds, 100);

        // verifyLsethWithdrawal(
        //     bob,
        //     baseProceeds,
        //     true,
        //     totalRethSupplyBefore,
        //     bobBalancesBefore,
        //     hyperdriveBalancesBefore
        // );
    }

    function test_close_short_with_lseth(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION, 0.05e18);

        // Bob opens a short by depositing lsETH.
        vm.startPrank(bob);
        shortAmount = shortAmount.normalizeToRange(
            100 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        RIVER.approve(address(hyperdrive), shortAmount);
        (uint256 maturityTime, uint256 sharesPaid) = openShort(
            bob,
            shortAmount,
            false
        );

        // The term passes and interest accrues.
        uint256 startingVaultSharePrice = hyperdrive
            .getPoolInfo()
            .vaultSharePrice;
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Get some balance information before closing the short.
        uint256 totalLsethSupplyBefore = RIVER.totalSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his short with lsETH as the target asset. Bob's proceeds
        // should be the variable interest that accrued on the shorted bonds.
        uint256 expectedBaseProceeds = shortAmount.mulDivDown(
            hyperdrive.getPoolInfo().vaultSharePrice - startingVaultSharePrice,
            startingVaultSharePrice
        );
        uint256 shareProceeds = closeShort(
            bob,
            maturityTime,
            shortAmount,
            false
        );
        uint256 baseProceeds = RIVER.underlyingBalanceFromShares(shareProceeds);
        assertLe(baseProceeds, expectedBaseProceeds + 10);
        assertApproxEqAbs(baseProceeds, expectedBaseProceeds, 100);

        // Ensure that Rocket Pool's aggregates and the token balances were updated
        // correctly during the trade.
        verifyLsethWithdrawal(
            bob,
            shareProceeds,
            false,
            totalLsethSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function verifyDeposit(
        address trader,
        uint256 amount,
        bool asBase,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        if (asBase) {
            revert IHyperdrive.UnsupportedToken();
        }
        // Ensure that the ether balances were updated correctly.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(trader.balance, traderBalancesBefore.ETHBalance);

        // Ensure that the lsETH balances were updated correctly.
        assertApproxEqAbs(
            RIVER.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.lsethBalance + amount,
            1
        );
        assertApproxEqAbs(
            RIVER.balanceOf(trader),
            traderBalancesBefore.lsethBalance - amount,
            1
        );

        // Ensure the total supply was updated correctly.
        assertEq(RIVER.totalSupply(), totalSharesBefore);
    }

    function verifyLsethWithdrawal(
        address trader,
        uint256 amount,
        bool asBase,
        uint256 totalLsethSupplyBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        if (asBase) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Ensure the total amount of rETH stays the same.
        assertEq(RIVER.totalSupply(), totalLsethSupplyBefore);

        // Ensure that the ETH balances were updated correctly.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(trader.balance, traderBalancesBefore.ETHBalance);

        // Ensure the rETH balances were updated correctly.
        assertApproxEqAbs(
            RIVER.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.lsethBalance - amount,
            1
        );
        assertApproxEqAbs(
            RIVER.balanceOf(address(trader)),
            traderBalancesBefore.lsethBalance + amount,
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

        // Load the validator balance from the last consensus
        // layer report slot.
        uint256 validatorBalance = uint256(
            vm.load(
                address(RIVER),
                LAST_CONSENSUS_LAYER_REPORT_VALIDATOR_BALANCE_SLOT
            )
        );

        // Increase the balance by the variable rate.
        uint256 newValidatorBalance = variableRate >= 0
            ? validatorBalance.mulDown(uint256(variableRate + 1e18))
            : validatorBalance.mulDown(uint256(1e18 - variableRate));
        vm.store(
            address(RIVER),
            LAST_CONSENSUS_LAYER_REPORT_VALIDATOR_BALANCE_SLOT,
            bytes32(newValidatorBalance)
        );
    }

    function test_advanced_time() external {
        vm.stopPrank();

        // Store the old lsETH exchange rate.
        uint256 oldRate = RIVER.underlyingBalanceFromShares(1e18);

        // Advance time and accrue interest.
        advanceTime(POSITION_DURATION, 0.05e18);

        // Ensure the new rate is higher than the old rate.
        assertGt(RIVER.underlyingBalanceFromShares(1e18), oldRate);
    }

    struct AccountBalances {
        uint256 lsethBalance;
        uint256 ETHBalance;
    }

    function getAccountBalances(
        address account
    ) internal view returns (AccountBalances memory) {
        return
            AccountBalances({
                lsethBalance: RIVER.balanceOf(account),
                ETHBalance: account.balance
            });
    }
}
