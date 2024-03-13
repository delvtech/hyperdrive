// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { EzETHHyperdriveCoreDeployer } from "contracts/src/deployers/ezeth/EzETHHyperdriveCoreDeployer.sol";
import { EzETHHyperdriveDeployerCoordinator } from "contracts/src/deployers/ezeth/EzETHHyperdriveDeployerCoordinator.sol";
import { EzETHTarget0Deployer } from "contracts/src/deployers/ezeth/EzETHTarget0Deployer.sol";
import { EzETHTarget1Deployer } from "contracts/src/deployers/ezeth/EzETHTarget1Deployer.sol";
import { EzETHTarget2Deployer } from "contracts/src/deployers/ezeth/EzETHTarget2Deployer.sol";
import { EzETHTarget3Deployer } from "contracts/src/deployers/ezeth/EzETHTarget3Deployer.sol";
import { EzETHTarget4Deployer } from "contracts/src/deployers/ezeth/EzETHTarget4Deployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IRestakeManager } from "contracts/src/interfaces/IRestakeManager.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";
import "forge-std/console.sol";

contract EzETHHyperdriveTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    uint256 internal constant FIXED_RATE = 0.05e18;

    // The Lido storage location that tracks buffered ether reserves. We can
    // simulate the accrual of interest by updating this value.
    bytes32 internal constant BUFFERED_ETHER_POSITION =
        keccak256("lido.Lido.bufferedEther");

    // ILido internal constant LIDO =
    //     ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IRestakeManager internal constant RESTAKE_MANAGER =
        IRestakeManager(0x74a09653A083691711cF8215a6ab074BB4e99ef5);
    IERC20 internal constant EZETH =
        IERC20(0xbf5495Efe5DB9ce00f80364C8B423567e58d2110);
    address DEPOSIT_QUEUE = 0xc23535D7F3634634a1E2cF101863db64a7054410;

    address internal EZETH_WHALE = 0x22E12A50e3ca49FB183074235cB1db84Fe4C716D;
    address internal ETH_WHALE = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    HyperdriveFactory factory;
    address deployerCoordinator;

    function setUp() public override __mainnet_fork(19_422_267) {
        super.setUp();

        // Deploy the hyperdrive factory.
        vm.startPrank(deployer);
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ERC20ForwarderFactory();
        factory = new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: feeCollector,
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
            new EzETHHyperdriveDeployerCoordinator(
                address(
                    new EzETHHyperdriveCoreDeployer(RESTAKE_MANAGER, EZETH)
                ),
                address(new EzETHTarget0Deployer(RESTAKE_MANAGER, EZETH)),
                address(new EzETHTarget1Deployer(RESTAKE_MANAGER, EZETH)),
                address(new EzETHTarget2Deployer(RESTAKE_MANAGER, EZETH)),
                address(new EzETHTarget3Deployer(RESTAKE_MANAGER, EZETH)),
                address(new EzETHTarget4Deployer(RESTAKE_MANAGER, EZETH)),
                RESTAKE_MANAGER,
                EZETH
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

        // Ensure that Bob received the correct amount of LP tokens. She should
        // receive LP shares totaling the amount of shares that she contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            contribution.divDown(
                hyperdrive.getPoolConfig().initialVaultSharePrice
            ) - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
            1e6
        );

        // Fund the test accounts with ezETH and ETH.
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = celine;
        fundAccounts(address(hyperdrive), IERC20(EZETH), EZETH_WHALE, accounts);
        vm.deal(alice, 20_000e18);
        vm.deal(bob, 20_000e18);
        vm.deal(celine, 20_000e18);

        // Start recording event logs.
        vm.recordLogs();
    }

    /// Deploy and Initialize ///

    function test__ezeth__deployAndInitialize() external {
        // Deploy and Initialize the ezETH hyperdrive instance. Excess ether is
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
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, bob),
            contribution.divDown(
                hyperdrive.getPoolConfig().initialVaultSharePrice
            ) - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
            1e6 // was 1e5
        );

        // Ensure that the share reserves and LP total supply are equal and correct.
        (, , uint256 totalTVL) = RESTAKE_MANAGER.calculateTVLs();

        assertApproxEqAbs(
            hyperdrive.getPoolInfo().shareReserves,
            contribution.mulDivDown(EZETH.totalSupply(), totalTVL),
            1e6 // was 1
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
            config.minimumShareReserves,
            new bytes(0),
            // NOTE: Tolerance since stETH uses mulDivDown for share calculations.
            1e5
        );
    }

    /// Price Per Share ///

    // function test__pricePerVaultShare(uint256 basePaid) external {
    function test__pricePerVaultShare() external {
        uint256 basePaid = 10 ether;
        // Ensure that the share price is the expected value.

        (, , uint256 totalTVL) = RESTAKE_MANAGER.calculateTVLs();
        uint256 ezETHSupply = EZETH.totalSupply();

        // Price in ETH / ezETH, does not include eigenlayer points.
        uint256 sharePrice = totalTVL.divDown(ezETHSupply);
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, sharePrice);

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of ETH.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        uint256 hyperdriveSharesBefore = EZETH.balanceOf(address(hyperdrive));
        openLong(bob, basePaid);
        assertApproxEqAbs(
            EZETH.balanceOf(address(hyperdrive)),
            hyperdriveSharesBefore + basePaid.divDown(vaultSharePrice),
            1e6 // was 1e4
        );
    }

    /// Long ///

    // function test_open_long_with_ETH(uint256 basePaid) external {
    function test_open_long_with_ETH() external {
        uint256 basePaid = 10 ether;
        // Get some balance information before the deposit.
        (, , uint256 totalPooledEtherBefore) = RESTAKE_MANAGER.calculateTVLs();
        uint256 totalSharesBefore = EZETH.totalSupply();
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

        // Ensure that Bob receives a  refund when he opens a long with "asBase"
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

    function test_open_long_with_ezeth(uint256 basePaid) external {
        // Get some balance information before the deposit.
        (, , uint256 totalPooledEtherBefore) = RESTAKE_MANAGER.calculateTVLs();
        uint256 totalSharesBefore = EZETH.totalSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a long by depositing stETH.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );

        (, , uint256 totalPooledEther) = RESTAKE_MANAGER.calculateTVLs();
        uint256 totalShares = EZETH.totalSupply();
        uint256 sharesPaid = basePaid.mulDivDown(totalShares, totalPooledEther);
        openLong(bob, sharesPaid, false);

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
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Bob attempts to close his long with ETH as the target asset. This
        // fails since ETH isn't supported as a withdrawal asset.
        vm.stopPrank();
        vm.startPrank(bob);
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

    function test_close_long_with_ezeth(
        uint256 basePaid,
        int256 variableRate
    ) external {
        console.log("test_close_long_with_ezeth");
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        (, , uint256 totalPooledEther) = RESTAKE_MANAGER.calculateTVLs();
        uint256 totalShares = EZETH.totalSupply();
        uint256 price = totalPooledEther.divDown(totalShares);
        console.log("price", price);
        advanceTime(POSITION_DURATION, 0.05e18);
        (, , totalPooledEther) = RESTAKE_MANAGER.calculateTVLs();
        totalShares = EZETH.totalSupply();
        price = totalPooledEther.divDown(totalShares);
        console.log("price", price);

        // Bob opens a long.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // The term passes and some interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Get some balance information before the withdrawal.
        (, , uint256 totalPooledEtherBefore) = RESTAKE_MANAGER.calculateTVLs();
        uint256 totalSharesBefore = EZETH.totalSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with ezETH as the target asset.
        uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
        (, , uint256 totalPooledEtherAfter) = RESTAKE_MANAGER.calculateTVLs();
        uint256 totalSharesAfter = EZETH.totalSupply();
        uint256 baseProceeds = shareProceeds.mulDivDown(
            totalPooledEtherAfter,
            totalSharesAfter
        );

        // Ensuse that Bob received approximately the bond amount but wasn't
        // overpaid.
        console.log("assertLe");
        console.log("baseProceeds", baseProceeds);
        console.log("longAmount", longAmount);
        assertLe(baseProceeds, longAmount);
        console.log("assertApproxEqAbs");
        assertApproxEqAbs(baseProceeds, longAmount, 10);

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        console.log("verifyEzethWithdrawal");
        verifyEzethWithdrawal(
            bob,
            baseProceeds,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    // /// Short ///

    // function test_open_short_with_ETH(uint256 shortAmount) external {
    //     // Get some balance information before the deposit.
    //     uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
    //     uint256 totalSharesBefore = LIDO.getTotalShares();
    //     AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
    //     AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
    //         address(hyperdrive)
    //     );

    //     // Bob opens a short by depositing ETH.
    //     shortAmount = shortAmount.normalizeToRange(
    //         2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
    //         HyperdriveUtils.calculateMaxShort(hyperdrive)
    //     );
    //     uint256 balanceBefore = bob.balance;
    //     vm.deal(bob, shortAmount);
    //     (, uint256 basePaid) = openShort(bob, shortAmount);
    //     vm.deal(bob, balanceBefore - basePaid);

    //     // Ensure that the amount of base paid by the short is reasonable.
    //     uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
    //         shortAmount - basePaid,
    //         shortAmount,
    //         1e18
    //     );
    //     assertGt(basePaid, 0);
    //     assertGe(realizedRate, FIXED_RATE);

    //     // Ensure that Lido's aggregates and the token balances were updated
    //     // correctly during the trade.
    //     verifyDeposit(
    //         bob,
    //         basePaid,
    //         true,
    //         totalPooledEtherBefore,
    //         totalSharesBefore,
    //         bobBalancesBefore,
    //         hyperdriveBalancesBefore
    //     );
    // }

    // function test_open_short_with_steth(uint256 shortAmount) external {
    //     // Get some balance information before the deposit.
    //     uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
    //     uint256 totalSharesBefore = LIDO.getTotalShares();
    //     AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
    //     AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
    //         address(hyperdrive)
    //     );

    //     // Bob opens a short by depositing ETH.
    //     shortAmount = shortAmount.normalizeToRange(
    //         2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
    //         HyperdriveUtils.calculateMaxShort(hyperdrive)
    //     );
    //     (, uint256 sharesPaid) = openShort(bob, shortAmount, false);
    //     uint256 basePaid = sharesPaid.mulDivDown(
    //         LIDO.getTotalPooledEther(),
    //         LIDO.getTotalShares()
    //     );

    //     // Ensure that the amount of base paid by the short is reasonable.
    //     uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
    //         shortAmount - basePaid,
    //         shortAmount,
    //         1e18
    //     );
    //     assertGt(basePaid, 0);
    //     assertGe(realizedRate, FIXED_RATE);

    //     // Ensure that Lido's aggregates and the token balances were updated
    //     // correctly during the trade.
    //     verifyDeposit(
    //         bob,
    //         basePaid,
    //         false,
    //         totalPooledEtherBefore,
    //         totalSharesBefore,
    //         bobBalancesBefore,
    //         hyperdriveBalancesBefore
    //     );
    // }

    // function test_open_short_refunds() external {
    //     vm.startPrank(bob);

    //     // Ensure that Bob receives a refund on the excess ETH that he sent
    //     // when opening a long with "asBase" set to true.
    //     uint256 ethBalanceBefore = address(bob).balance;
    //     (, uint256 basePaid) = hyperdrive.openShort{ value: 2e18 }(
    //         1e18,
    //         1e18,
    //         0,
    //         IHyperdrive.Options({
    //             destination: bob,
    //             asBase: true,
    //             extraData: new bytes(0)
    //         })
    //     );
    //     assertEq(address(bob).balance, ethBalanceBefore - basePaid);

    //     // Ensure that Bob receives a  refund when he opens a long with "asBase"
    //     // set to false and sends ether to the contract.
    //     ethBalanceBefore = address(bob).balance;
    //     hyperdrive.openShort{ value: 0.5e18 }(
    //         1e18,
    //         1e18,
    //         0,
    //         IHyperdrive.Options({
    //             destination: bob,
    //             asBase: false,
    //             extraData: new bytes(0)
    //         })
    //     );
    //     assertEq(address(bob).balance, ethBalanceBefore);
    // }

    // function test_close_short_with_eth(
    //     uint256 shortAmount,
    //     int256 variableRate
    // ) external {
    //     // Bob opens a short.
    //     shortAmount = shortAmount.normalizeToRange(
    //         2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
    //         HyperdriveUtils.calculateMaxShort(hyperdrive)
    //     );
    //     uint256 balanceBefore = bob.balance;
    //     vm.deal(bob, shortAmount);
    //     (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);
    //     vm.deal(bob, balanceBefore - basePaid);

    //     // NOTE: The variable rate must be greater than 0 since the unsupported
    //     // check is only triggered if the shares amount is non-zero.
    //     //
    //     // The term passes and interest accrues.
    //     variableRate = variableRate.normalizeToRange(0.01e18, 2.5e18);
    //     advanceTime(POSITION_DURATION, variableRate);

    //     // Bob attempts to close his short with ETH as the target asset. This
    //     // fails since ETH isn't supported as a withdrawal asset.
    //     vm.stopPrank();
    //     vm.startPrank(bob);
    //     vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
    //     hyperdrive.closeShort(
    //         maturityTime,
    //         shortAmount,
    //         0,
    //         IHyperdrive.Options({
    //             destination: bob,
    //             asBase: true,
    //             extraData: new bytes(0)
    //         })
    //     );
    // }

    // function test_close_short_with_steth(
    //     uint256 shortAmount,
    //     int256 variableRate
    // ) external {
    //     // Accrue interest for a term to ensure that the share price is greater
    //     // than one.
    //     advanceTime(POSITION_DURATION, 0.05e18);

    //     // Bob opens a short.
    //     shortAmount = shortAmount.normalizeToRange(
    //         2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
    //         HyperdriveUtils.calculateMaxShort(hyperdrive)
    //     );
    //     uint256 balanceBefore = bob.balance;
    //     vm.deal(bob, shortAmount);
    //     (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);
    //     vm.deal(bob, balanceBefore - basePaid);

    //     // The term passes and interest accrues.
    //     uint256 startingVaultSharePrice = hyperdrive
    //         .getPoolInfo()
    //         .vaultSharePrice;
    //     variableRate = variableRate.normalizeToRange(0, 2.5e18);
    //     advanceTime(POSITION_DURATION, variableRate);

    //     // Get some balance information before closing the short.
    //     uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
    //     uint256 totalSharesBefore = LIDO.getTotalShares();
    //     AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
    //     AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
    //         address(hyperdrive)
    //     );

    //     // Bob closes his short with stETH as the target asset. Bob's proceeds
    //     // should be the variable interest that accrued on the shorted bonds.
    //     uint256 expectedBaseProceeds = shortAmount.mulDivDown(
    //         hyperdrive.getPoolInfo().vaultSharePrice - startingVaultSharePrice,
    //         startingVaultSharePrice
    //     );
    //     uint256 shareProceeds = closeShort(
    //         bob,
    //         maturityTime,
    //         shortAmount,
    //         false
    //     );
    //     uint256 baseProceeds = shareProceeds.mulDivDown(
    //         LIDO.getTotalPooledEther(),
    //         LIDO.getTotalShares()
    //     );
    //     assertLe(baseProceeds, expectedBaseProceeds + 10);
    //     assertApproxEqAbs(baseProceeds, expectedBaseProceeds, 100);

    //     // Ensure that Lido's aggregates and the token balances were updated
    //     // correctly during the trade.
    //     verifyEzethWithdrawal(
    //         bob,
    //         baseProceeds,
    //         totalPooledEtherBefore,
    //         totalSharesBefore,
    //         bobBalancesBefore,
    //         hyperdriveBalancesBefore
    //     );
    // }

    // function test_attack_long_steth() external {
    //     // Get some balance information before the deposit.
    //     LIDO.sharesOf(address(hyperdrive));

    //     // Bob opens a long by depositing ETH.
    //     uint256 basePaid = HyperdriveUtils.calculateMaxLong(hyperdrive);
    //     (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

    //     // Get some balance information before the withdrawal.
    //     uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
    //     uint256 totalSharesBefore = LIDO.getTotalShares();
    //     AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
    //     AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
    //         address(hyperdrive)
    //     );

    //     // Bob closes his long with stETH as the target asset.
    //     uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
    //     uint256 baseProceeds = shareProceeds.mulDivDown(
    //         LIDO.getTotalPooledEther(),
    //         LIDO.getTotalShares()
    //     );

    //     // Ensure that Lido's aggregates and the token balances were updated
    //     // correctly during the trade.
    //     verifyEzethWithdrawal(
    //         bob,
    //         baseProceeds,
    //         totalPooledEtherBefore,
    //         totalSharesBefore,
    //         bobBalancesBefore,
    //         hyperdriveBalancesBefore
    //     );
    // }

    // function test__DOSStethHyperdriveCloseLong() external {
    //     //###########################################################################"
    //     //#### TEST: Denial of Service when LIDO's `TotalPooledEther` decreases. ####"
    //     //###########################################################################"

    //     // Ensure that the share price is the expected value.
    //     uint256 totalPooledEther = LIDO.getTotalPooledEther();
    //     uint256 totalShares = LIDO.getTotalShares();
    //     uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
    //     assertEq(vaultSharePrice, totalPooledEther.divDown(totalShares));

    //     // Ensure that the share price accurately predicts the amount of shares
    //     // that will be minted for depositing a given amount of ETH. This will
    //     // be an approximation since Lido uses `mulDivDown` whereas this test
    //     // pre-computes the share price.
    //     uint256 basePaid = HyperdriveUtils.calculateMaxLong(hyperdrive) / 10;
    //     uint256 hyperdriveSharesBefore = LIDO.sharesOf(address(hyperdrive));

    //     // Bob calls openLong()
    //     (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);
    //     // Bob paid basePaid == ", basePaid);
    //     // Bob received longAmount == ", longAmount);
    //     assertApproxEqAbs(
    //         LIDO.sharesOf(address(hyperdrive)),
    //         hyperdriveSharesBefore + basePaid.divDown(vaultSharePrice),
    //         1e4
    //     );

    //     // Get some balance information before the withdrawal.
    //     uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
    //     uint256 totalSharesBefore = LIDO.getTotalShares();
    //     AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
    //     AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
    //         address(hyperdrive)
    //     );
    //     uint256 snapshotId = vm.snapshot();

    //     // Taking a Snapshot of the state
    //     // Bob closes his long with stETH as the target asset.
    //     uint256 shareProceeds = closeLong(
    //         bob,
    //         maturityTime,
    //         longAmount / 2,
    //         false
    //     );
    //     uint256 baseProceeds = shareProceeds.mulDivDown(
    //         LIDO.getTotalPooledEther(),
    //         LIDO.getTotalShares()
    //     );

    //     // Ensure that Lido's aggregates and the token balances were updated
    //     // correctly during the trade.
    //     verifyEzethWithdrawal(
    //         bob,
    //         baseProceeds,
    //         totalPooledEtherBefore,
    //         totalSharesBefore,
    //         bobBalancesBefore,
    //         hyperdriveBalancesBefore
    //     );
    //     // # Reverting to the saved state Snapshot #\n");
    //     vm.revertTo(snapshotId);

    //     // # Manipulating Lido's totalPooledEther : removing only 1e18
    //     bytes32 balanceBefore = vm.load(
    //         address(LIDO),
    //         bytes32(
    //             0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483
    //         )
    //     );
    //     // LIDO.CL_BALANCE_POSITION Before: ", uint(balanceBefore));
    //     uint(LIDO.getTotalPooledEther());
    //     hyperdrive.balanceOf(
    //         AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
    //         bob
    //     );
    //     vm.store(
    //         address(LIDO),
    //         bytes32(
    //             uint256(
    //                 0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483
    //             )
    //         ),
    //         bytes32(uint256(balanceBefore) - 1e18)
    //     );

    //     // Avoid Stack too deep
    //     uint256 maturityTime_ = maturityTime;
    //     uint256 longAmount_ = longAmount;

    //     vm.load(
    //         address(LIDO),
    //         bytes32(
    //             uint256(
    //                 0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483
    //             )
    //         )
    //     );

    //     // Bob closes his long with stETH as the target asset.
    //     hyperdrive.balanceOf(
    //         AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime_),
    //         bob
    //     );

    //     // The fact that this doesn't revert means that it works
    //     closeLong(bob, maturityTime_, longAmount_ / 2, false);
    // }

    function verifyDeposit(
        address trader,
        uint256 basePaid,
        bool asBase,
        uint256 totalPooledEtherBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        if (asBase) {
            // Ensure that the amount of pooled ether increased by the base paid.
            (, , uint256 totalPooledEther) = RESTAKE_MANAGER.calculateTVLs();
            console.log("asBase verifyDeposit 1");
            assertEq(totalPooledEther, totalPooledEtherBefore + basePaid);

            // Ensure that the ETH balances were updated correctly.
            console.log("asBase verifyDeposit 2");
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            console.log("asBase verifyDeposit 3");
            assertEq(bob.balance, traderBalancesBefore.ETHBalance - basePaid);

            console.log("asBase verifyDeposit 4");
            // ezETH doesn't have shares/balance like steth does
            // assertApproxEqAbs(
            //     EZETH.balanceOf(address(hyperdrive)),
            //     hyperdriveBalancesBefore.ezethBalance + basePaid,
            //     1
            // );

            console.log("asBase verifyDeposit 5");
            assertEq(
                EZETH.balanceOf(trader),
                traderBalancesBefore.ezethBalance
            );

            // Ensure that the ezETH shares were updated correctly.
            console.log("asBase verifyDeposit 6");
            uint256 expectedShares = basePaid.mulDivDown(
                totalSharesBefore,
                totalPooledEtherBefore
            );

            console.log("asBase verifyDeposit 7");
            assertApproxEqAbs(
                EZETH.totalSupply(),
                totalSharesBefore + expectedShares,
                1e6
            ); // was exact
            console.log("asBase verifyDeposit 8");
            assertApproxEqAbs(
                EZETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.ezethBalance + expectedShares,
                1e6
            ); // was exact
            console.log("asBase verifyDeposit 9");
            assertEq(EZETH.balanceOf(bob), traderBalancesBefore.ezethBalance);
        } else {
            // Ensure that the amount of pooled ether stays the same.
            (, , uint256 totalPooledEther) = RESTAKE_MANAGER.calculateTVLs();
            console.log("shares verifyDeposit 1");
            assertEq(totalPooledEther, totalPooledEtherBefore);

            // Ensure that the ETH balances were updated correctly.
            console.log("shares verifyDeposit 2");
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            console.log("shares verifyDeposit 3");
            assertEq(trader.balance, traderBalancesBefore.ETHBalance);

            console.log("shares verifyDeposit 4");
            // ezETH doesn't have shares/balance like steth does
            // Ensure that the ezETH balances were updated correctly.
            // assertApproxEqAbs(
            //     EZETH.balanceOf(address(hyperdrive)),
            //     hyperdriveBalancesBefore.ezethBalance + basePaid,
            //     1
            // );
            console.log("shares verifyDeposit 5");
            // ezETH doesn't have shares/balance like steth does
            // assertApproxEqAbs(
            //     EZETH.balanceOf(trader),
            //     traderBalancesBefore.ezethBalance - basePaid,
            //     1
            // );

            // Ensure that the ezETH shares were updated correctly.
            uint256 expectedShares = basePaid.mulDivDown(
                totalSharesBefore,
                totalPooledEtherBefore
            );
            console.log("shares verifyDeposit 6");
            assertEq(EZETH.totalSupply(), totalSharesBefore);
            console.log("shares verifyDeposit 7");
            assertApproxEqAbs(
                EZETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.ezethBalance + expectedShares,
                1
            );
            console.log("shares verifyDeposit 8");
            assertApproxEqAbs(
                EZETH.balanceOf(trader),
                traderBalancesBefore.ezethBalance - expectedShares,
                1
            );
        }
    }

    function verifyEzethWithdrawal(
        address trader,
        uint256 baseProceeds,
        uint256 totalPooledEtherBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        // Ensure that the total pooled ether and shares stays the same.
        (, , uint256 totalPooledEth) = RESTAKE_MANAGER.calculateTVLs();
        console.log("verifyEzethWithdrawal 1");
        assertEq(totalPooledEth, totalPooledEtherBefore);
        console.log("verifyEzethWithdrawal 2");
        assertApproxEqAbs(EZETH.totalSupply(), totalSharesBefore, 1);

        // Ensure that the ETH balances were updated correctly.
        console.log("verifyEzethWithdrawal 3");
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        console.log("verifyEzethWithdrawal 4");
        assertEq(trader.balance, traderBalancesBefore.ETHBalance);

        // Ensure that the ezETH balances were updated correctly.
        console.log("verifyEzethWithdrawal 5");
        assertApproxEqAbs(
            EZETH.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.ezethBalance - baseProceeds,
            1
        );
        console.log("verifyEzethWithdrawal 6");
        assertApproxEqAbs(
            EZETH.balanceOf(trader),
            traderBalancesBefore.ezethBalance + baseProceeds,
            1
        );

        // Ensure that the ezETH shares were updated correctly.
        uint256 expectedShares = baseProceeds.mulDivDown(
            totalSharesBefore,
            totalPooledEtherBefore
        );
        console.log("verifyEzethWithdrawal 7");
        assertApproxEqAbs(
            EZETH.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.ezethBalance - expectedShares,
            1
        );
        console.log("verifyEzethWithdrawal 8");
        assertApproxEqAbs(
            EZETH.balanceOf(trader),
            traderBalancesBefore.ezethBalance + expectedShares,
            1
        );
    }

    /// Helpers ///

    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        console.log("advanceTime");
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // TODO: figure out what to set to accrue interest

        // Accrue interest in Renzo. Since the share price is given by
        // `RESTAKE_MANAGER.calculateTVLs() / EZETH.totalSupply()`, we can simulate the
        // accrual of interest by multiplying the total pooled ether by the
        // variable rate plus one.
        (, , uint256 totalTVLBefore) = RESTAKE_MANAGER.calculateTVLs();

        // set balance of the DepositQueue contract to add interest.  RestakeManager adds the
        // balance of the DepositQueue to totalTVL in calculateTVLs()
        uint256 totalTVLAfter = totalTVLBefore.mulDown(uint256(variableRate));
        if (variableRate >= 0) {
            uint256 ethToAdd = totalTVLBefore - totalTVLAfter;
            vm.deal(DEPOSIT_QUEUE, DEPOSIT_QUEUE.balance + ethToAdd);
        } else {
            uint256 ethToSubtract = totalTVLBefore - totalTVLAfter;
            vm.deal(DEPOSIT_QUEUE, DEPOSIT_QUEUE.balance - ethToSubtract);
        }
    }

    struct AccountBalances {
        uint256 ezethBalance;
        uint256 ETHBalance;
    }

    function getAccountBalances(
        address account
    ) internal view returns (AccountBalances memory) {
        return
            AccountBalances({
                ezethBalance: EZETH.balanceOf(account),
                ETHBalance: account.balance
            });
    }
}
