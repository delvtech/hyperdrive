// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { RETHHyperdriveCoreDeployer } from "contracts/src/deployers/reth/RETHHyperdriveCoreDeployer.sol";
import { RETHHyperdriveDeployerCoordinator } from "contracts/src/deployers/reth/RETHHyperdriveDeployerCoordinator.sol";
import { RETHTarget0Deployer } from "contracts/src/deployers/reth/RETHTarget0Deployer.sol";
import { RETHTarget1Deployer } from "contracts/src/deployers/reth/RETHTarget1Deployer.sol";
import { RETHTarget2Deployer } from "contracts/src/deployers/reth/RETHTarget2Deployer.sol";
import { RETHTarget3Deployer } from "contracts/src/deployers/reth/RETHTarget3Deployer.sol";
import { RETHTarget4Deployer } from "contracts/src/deployers/reth/RETHTarget4Deployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IRocketStorage } from "contracts/src/interfaces/IRocketStorage.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";
import { IRocketNetworkBalances } from "contracts/src/interfaces/IRocketNetworkBalances.sol";
import { IRocketDepositPool } from "contracts/src/interfaces/IRocketDepositPool.sol";
import { IRocketTokenRETH } from "contracts/src/interfaces/IRocketTokenRETH.sol";

contract RETHHyperdriveTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    uint256 internal constant FIXED_RATE = 0.05e18;
    IRocketStorage internal constant ROCKET_STORAGE =
        IRocketStorage(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);

    IRocketTokenRETH rocketTokenRETH;
    IRocketNetworkBalances rocketNetworkBalances;
    IRocketDepositPool rocketDepositPool;

    address internal RETH_WHALE = 0xCc9EE9483f662091a1de4795249E24aC0aC2630f;
    address internal ETH_WHALE = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    HyperdriveFactory factory;
    address deployerCoordinator;

    function setUp() public override __mainnet_fork(17_376_154) {
        super.setUp();

        // Fetching the RETH token contract address from storage.
        address rocketTokenRETHAddress = ROCKET_STORAGE.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
        );
        rocketTokenRETH = IRocketTokenRETH(rocketTokenRETHAddress);

        // Fetching the Rocket Network Balances contract address from storage.
        address rocketNetworkBalancesAddress = ROCKET_STORAGE.getAddress(
            keccak256(
                abi.encodePacked("contract.address", "rocketNetworkBalances")
            )
        );
        rocketNetworkBalances = IRocketNetworkBalances(
            rocketNetworkBalancesAddress
        );

        // Fetching the Rocket Deposit Pool contract address from storage.
        address rocketDepositPoolAddress = ROCKET_STORAGE.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketDepositPool"))
        );
        rocketDepositPool = IRocketDepositPool(rocketDepositPoolAddress);

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
            new RETHHyperdriveDeployerCoordinator(
                address(new RETHHyperdriveCoreDeployer(ROCKET_STORAGE)),
                address(new RETHTarget0Deployer(ROCKET_STORAGE)),
                address(new RETHTarget1Deployer(ROCKET_STORAGE)),
                address(new RETHTarget2Deployer(ROCKET_STORAGE)),
                address(new RETHTarget3Deployer(ROCKET_STORAGE)),
                address(new RETHTarget4Deployer(ROCKET_STORAGE)),
                ROCKET_STORAGE
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
                minimumTransactionAmount: 0.01 ether,
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
        uint256 contribution = 10_000e18;
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
        hyperdrive = factory.deployAndInitialize{ value: contribution }(
            bytes32(uint256(0xdeadbeef)),
            deployerCoordinator,
            config,
            new bytes(0),
            contribution,
            FIXED_RATE,
            FIXED_RATE,
            new bytes(0),
            bytes32(uint256(0xdeadbabe))
        );

        // Ensure that Alice received the correct amount of LP tokens. She should
        // receive LP shares totaling the amount of shares that she contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        uint256 adjustedContribution = basePaidAfterFee(contribution);
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            adjustedContribution.divDown(
                hyperdrive.getPoolConfig().initialVaultSharePrice
            ) - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
            1e5
        );

        // Fund the test accounts with RETH and ETH.
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = celine;
        fundAccounts(
            address(hyperdrive),
            IERC20(rocketTokenRETH),
            RETH_WHALE,
            accounts
        );
        vm.deal(alice, 20_000e18);
        vm.deal(bob, 20_000e18);
        vm.deal(celine, 20_000e18);
        // Deal ether to the rocket token address to increase liquidity for
        // withdrawals.
        vm.deal(rocketTokenRETHAddress, 50_000e18);

        // Start recording event logs.
        vm.recordLogs();
    }

    /// Deploy and Initialize ///

    function test__reth__deployAndInitialize() external {
        // Deploy and Initialize the RETH hyperdrive instance. Excess ether is
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
                minimumTransactionAmount: 0.01 ether,
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
        hyperdrive = factory.deployAndInitialize{ value: contribution + 1e18 }(
            bytes32(uint256(0xbeefbabe)),
            address(deployerCoordinator),
            config,
            new bytes(0),
            contribution,
            FIXED_RATE,
            FIXED_RATE,
            new bytes(0),
            bytes32(uint256(0xdeadfade))
        );
        assertEq(address(bob).balance, bobBalanceBefore - contribution);

        // Ensure that the decimals are set correctly.
        assertEq(hyperdrive.decimals(), 18);

        // Ensure that Bob received the correct amount of LP tokens. He should
        // receive LP shares totaling the amount of shares that he contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        uint256 adjustedContribution = basePaidAfterFee(contribution);
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, bob),
            adjustedContribution.divDown(
                hyperdrive.getPoolConfig().initialVaultSharePrice
            ) - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
            1e5
        );

        // Ensure that the share reserves and LP total supply are equal and correct.
        assertApproxEqAbs(
            hyperdrive.getPoolInfo().shareReserves,
            rocketTokenRETH.getRethValue(adjustedContribution),
            1
        );
        assertEq(
            hyperdrive.getPoolInfo().lpTotalSupply,
            hyperdrive.getPoolInfo().shareReserves - config.minimumShareReserves
        );

        // Verify that the correct events were emitted.
        // verifyFactoryEvents(
        //     deployerCoordinator,
        //     hyperdrive,
        //     bob,
        //     contribution,
        //     FIXED_RATE,
        //     config.minimumShareReserves,
        //     new bytes(0),
        //     // NOTE: Tolerance since stETH uses mulDivDown for share calculations.
        //     1e5
        // );
    }

    /// Price Per Share ///

    function test_pricePerVaultShare(uint256 basePaid) external {
        // Ensure the share prices are equal upon market inception.
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, rocketTokenRETH.getExchangeRate());

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of ETH. This will
        // be an approximation since Rocket Pool uses `mulDivDown` whereas this test
        // pre-computes the share price.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        uint256 hyperdriveSharesBefore = rocketTokenRETH.balanceOf(
            address(hyperdrive)
        );
        openLong(bob, basePaid);
        assertApproxEqAbs(
            rocketTokenRETH.balanceOf(address(hyperdrive)),
            hyperdriveSharesBefore +
                basePaidAfterFee(basePaid).divDown(vaultSharePrice),
            1e4
        );
    }

    /// Long ///

    function test_open_long_with_eth(uint256 basePaid) external {
        // Get some balance information before the deposit.
        uint256 totalRethSharesBefore = rocketTokenRETH.totalSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a long by depositing ETH.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        openLong(bob, basePaid);

        // Ensure that Rocket Pool's aggregates and the token balances were updated
        // correctly during the trade.
        verifyDeposit(
            bob,
            basePaid,
            true,
            totalRethSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_open_long_with_reth(uint256 basePaid) external {
        // Get some balance information before the deposit.
        uint256 totalSharesBefore = rocketTokenRETH.totalSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Calculate the maximum amount of basePaid we can test. The limit is
        // either the max long that Hyperdrive can open or the amount of RETH
        // tokens the trader has.
        uint256 maxLongAmount = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEthAmount = rocketTokenRETH.getEthValue(
            rocketTokenRETH.balanceOf(bob)
        );

        // Bob opens a long by depositing RETH.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxLongAmount > maxEthAmount ? maxEthAmount : maxLongAmount
        );
        uint256 sharesPaid = rocketTokenRETH.getRethValue(basePaid);
        openLong(bob, sharesPaid, false);

        // Ensure that Rocket Pool's aggregates and the token balances were updated
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

        // Ensure that Bob receives a refund on the excess ETH that he sent
        // when opening a long with "asBase" set to true.
        uint256 ethBalanceBefore = address(bob).balance;
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
        assertEq(address(bob).balance, ethBalanceBefore - 1e18);

        // Ensure that Bob receives a refund when he opens a long with "asBase"
        // set to false and sends ether to the contract.
        ethBalanceBefore = address(bob).balance;
        hyperdrive.openLong{ value: 0.5e18 }(
            1e18,
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

        // Bob opens a long, paying with ETH.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            basePaid,
            true
        );

        // The term passes and some interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Get some balance information before the withdrawal.
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );
        uint256 totalRethSupplyBefore = rocketTokenRETH.totalSupply();

        // Bob closes his long with ETH as the target asset.
        uint256 baseProceeds = closeLong(bob, maturityTime, longAmount, true);

        // Ensure Bob is credited the correct amount of bonds.
        assertLe(baseProceeds, longAmount);
        assertApproxEqAbs(baseProceeds, longAmount, 10);

        // Ensure that Rocket Pool's aggregates and the token balances were updated
        // correctly during the trade.
        verifyRethWithdrawal(
            bob,
            baseProceeds,
            true,
            totalRethSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );

        vm.stopPrank();
    }

    function test_close_long_with_reth(
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
        uint256 maxEthAmount = rocketTokenRETH.getEthValue(
            rocketTokenRETH.balanceOf(bob)
        );

        // Bob opens a long by depositing ETH.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxLongAmount > maxEthAmount ? maxEthAmount : maxLongAmount
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            basePaid,
            true
        );

        // The term passes and some interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Get some balance information before the withdrawal.
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );
        uint256 totalRethSupplyBefore = rocketTokenRETH.totalSupply();

        // Bob closes his long with RETH as the target asset.
        uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
        uint256 baseProceeds = rocketTokenRETH.getEthValue(shareProceeds);

        // Ensure Bob is credited the correct amount of bonds.
        assertLe(baseProceeds, longAmount);
        assertApproxEqAbs(baseProceeds, longAmount, 10);

        // Ensure that Rocket Pool's aggregates and the token balances were updated
        // correctly during the trade.
        verifyRethWithdrawal(
            bob,
            shareProceeds,
            false,
            totalRethSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );

        vm.stopPrank();
    }

    /// Short ///

    function test_open_short_with_eth(uint256 shortAmount) external {
        // Get some balance information before the deposit.
        uint256 totalRethSupplyBefore = rocketTokenRETH.totalSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a short by depositing ETH.
        shortAmount = shortAmount.normalizeToRange(
            100 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        uint256 balanceBefore = bob.balance;
        vm.deal(bob, shortAmount);
        (, uint256 basePaid) = openShort(bob, shortAmount, true);
        vm.deal(bob, balanceBefore - basePaid);

        // Ensure that the amount of base paid by the short is reasonable.
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            1e18
        );
        assertGt(basePaid, 0);
        assertGe(realizedRate, FIXED_RATE);

        // Ensure that Rocket Pool's aggregates and the token balances were updated
        // correctly during the trade.
        verifyDeposit(
            bob,
            basePaid,
            true,
            totalRethSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_open_short_with_reth(uint256 shortAmount) external {
        // Get some balance information before the deposit.
        uint256 totalRethSupplyBefore = rocketTokenRETH.totalSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a short by depositing RETH.
        shortAmount = shortAmount.normalizeToRange(
            100 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        (, uint256 sharesPaid) = openShort(bob, shortAmount, false);
        uint256 basePaid = rocketTokenRETH.getEthValue(sharesPaid);

        // Ensure that the amount of base paid by the short is reasonable.
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            1e18
        );
        assertGt(basePaid, 0);
        assertGe(realizedRate, FIXED_RATE);

        // Ensure that Rocket Pool's aggregates and the token balances were updated
        // correctly during the trade.
        verifyDeposit(
            bob,
            sharesPaid,
            false,
            totalRethSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_open_short_refunds() external {
        vm.startPrank(bob);

        // Ensure that Bob receives a refund on the excess ETH that he sent
        // when opening a short with "asBase" set to true.
        uint256 ethBalanceBefore = address(bob).balance;
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
        assertEq(address(bob).balance, ethBalanceBefore - basePaid);

        // Ensure that Bob receives a  refund when he opens a short with "asBase"
        // set to false and sends ether to the contract.
        ethBalanceBefore = address(bob).balance;
        hyperdrive.openShort{ value: 0.5e18 }(
            1e18,
            1e18,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: false,
                extraData: new bytes(0)
            })
        );
        assertEq(address(bob).balance, ethBalanceBefore);
    }

    function test_close_short_with_eth(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION, 0.05e18);

        // Bob opens a short.
        shortAmount = shortAmount.normalizeToRange(
            100 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        uint256 balanceBefore = bob.balance;
        vm.deal(bob, shortAmount);
        (uint256 maturityTime, uint256 basePaid) = openShort(
            bob,
            shortAmount,
            true
        );
        vm.deal(bob, balanceBefore - basePaid);

        // The term passes and interest accrues.
        uint256 startingVaultSharePrice = hyperdrive
            .getPoolInfo()
            .vaultSharePrice;
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Get some balance information before closing the short.
        uint256 totalRethSupplyBefore = rocketTokenRETH.totalSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his short with RETH as the target asset. Bob's proceeds
        // should be the variable interest that accrued on the shorted bonds.
        uint256 expectedBaseProceeds = shortAmount.mulDivDown(
            hyperdrive.getPoolInfo().vaultSharePrice - startingVaultSharePrice,
            startingVaultSharePrice
        );

        uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount, true);

        assertLe(baseProceeds, expectedBaseProceeds);
        assertApproxEqAbs(baseProceeds, expectedBaseProceeds, 100);

        verifyRethWithdrawal(
            bob,
            baseProceeds,
            true,
            totalRethSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_close_short_with_reth(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION, 0.05e18);

        // Bob opens a short.
        shortAmount = shortAmount.normalizeToRange(
            100 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        uint256 balanceBefore = bob.balance;
        vm.deal(bob, shortAmount);
        (uint256 maturityTime, uint256 basePaid) = openShort(
            bob,
            shortAmount,
            true
        );
        vm.deal(bob, balanceBefore - basePaid);

        // The term passes and interest accrues.
        uint256 startingVaultSharePrice = hyperdrive
            .getPoolInfo()
            .vaultSharePrice;
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Get some balance information before closing the short.
        uint256 totalRethSupplyBefore = rocketTokenRETH.totalSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his short with stETH as the target asset. Bob's proceeds
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
        uint256 baseProceeds = rocketTokenRETH.getEthValue(shareProceeds);

        assertLe(baseProceeds, expectedBaseProceeds + 10);
        assertApproxEqAbs(baseProceeds, expectedBaseProceeds, 100);

        // Ensure that Rocket Pool's aggregates and the token balances were updated
        // correctly during the trade.
        verifyRethWithdrawal(
            bob,
            shareProceeds,
            false,
            totalRethSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function basePaidAfterFee(
        uint256 basePaid
    ) internal pure returns (uint256) {
        return basePaid.mulDown(0.9995 ether);
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
            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(bob.balance, traderBalancesBefore.ETHBalance - amount);

            uint256 sharesMinted = rocketTokenRETH.getRethValue(
                basePaidAfterFee(amount)
            );

            // Ensure that the RETH balances were updated correctly.
            assertApproxEqAbs(
                rocketTokenRETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.rethBalance + sharesMinted,
                1
            );
            assertEq(
                rocketTokenRETH.balanceOf(trader),
                traderBalancesBefore.rethBalance
            );

            // Ensure the total supply was updated correctly.
            assertApproxEqAbs(
                rocketTokenRETH.totalSupply(),
                totalSharesBefore + sharesMinted,
                1
            );
        } else {
            // Ensure that the ether balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(trader.balance, traderBalancesBefore.ETHBalance);

            // Ensure that the RETH balances were updated correctly.
            assertApproxEqAbs(
                rocketTokenRETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.rethBalance + amount,
                1
            );
            assertApproxEqAbs(
                rocketTokenRETH.balanceOf(trader),
                traderBalancesBefore.rethBalance - amount,
                1
            );

            // Ensure the total supply was updated correctly.
            assertEq(rocketTokenRETH.totalSupply(), totalSharesBefore);
        }
    }

    function verifyRethWithdrawal(
        address trader,
        uint256 amount,
        bool asBase,
        uint256 totalRethSupplyBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        if (asBase) {
            uint256 amountAsShares = rocketTokenRETH.getRethValue(amount);

            // Ensure the total amount of RETH were updated correctly.
            assertApproxEqAbs(
                rocketTokenRETH.totalSupply(),
                totalRethSupplyBefore - amountAsShares,
                1
            );

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(trader.balance, traderBalancesBefore.ETHBalance + amount);

            // Ensure the RETH balances were updated correctly.
            assertApproxEqAbs(
                rocketTokenRETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.rethBalance - amountAsShares,
                1
            );
            assertEq(
                rocketTokenRETH.balanceOf(address(trader)),
                traderBalancesBefore.rethBalance
            );
        } else {
            // Ensure the total amount of RETH stays the same.
            assertEq(rocketTokenRETH.totalSupply(), totalRethSupplyBefore);

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(trader.balance, traderBalancesBefore.ETHBalance);

            // Ensure the RETH balances were updated correctly.
            assertApproxEqAbs(
                rocketTokenRETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.rethBalance - amount,
                1
            );
            assertApproxEqAbs(
                rocketTokenRETH.balanceOf(address(trader)),
                traderBalancesBefore.rethBalance + amount,
                1
            );
        }
    }

    /// Helpers ///

    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Advance the time.
        vm.startPrank(address(rocketNetworkBalances));
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in RocketPool. Since the share price is given by
        // `getTotalETHBalance() / getTotalRETHBalance()`, we can simulate the
        // accrual of interest by multiplying the total pooled ether by the
        // variable rate plus one.
        uint256 bufferedEther = variableRate >= 0
            ? rocketNetworkBalances.getTotalETHBalance().mulDown(
                uint256(variableRate + 1e18)
            )
            : rocketNetworkBalances.getTotalETHBalance().mulDown(
                uint256(1e18 - variableRate)
            );
        ROCKET_STORAGE.setUint(
            keccak256("network.balance.total"),
            bufferedEther
        );
        vm.stopPrank();
    }

    function test_advanced_time() external {
        vm.stopPrank();

        // Store the old RETH exchange rate.
        uint256 oldRate = rocketTokenRETH.getExchangeRate();

        // Advance time and accrue interest.
        advanceTime(POSITION_DURATION, 0.05e18);

        // Ensure the new rate is higher than the old rate.
        assertGt(rocketTokenRETH.getExchangeRate(), oldRate);
    }

    struct AccountBalances {
        uint256 rethBalance;
        uint256 ETHBalance;
    }

    function getAccountBalances(
        address account
    ) internal view returns (AccountBalances memory) {
        return
            AccountBalances({
                rethBalance: rocketTokenRETH.balanceOf(account),
                ETHBalance: account.balance
            });
    }
}
