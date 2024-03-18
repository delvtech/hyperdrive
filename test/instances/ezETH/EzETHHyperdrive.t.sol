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
import { IRestakeManager } from "contracts/src/interfaces/IRenzo.sol";
import { IRenzoOracle, IDepositQueue } from "contracts/src/interfaces/IRenzo.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract EzETHHyperdriveTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    uint256 internal constant FIXED_RATE = 0.05e18;

    // The Renzo main entrypoint contract to stake ETH and receive ezETH.
    IRestakeManager internal constant RESTAKE_MANAGER =
        IRestakeManager(0x74a09653A083691711cF8215a6ab074BB4e99ef5);

    // The Renzo Oracle contract.
    IRenzoOracle internal constant RENZO_ORACLE =
        IRenzoOracle(0x5a12796f7e7EBbbc8a402667d266d2e65A814042);

    // The ezETH token contract.
    IERC20 internal constant EZETH =
        IERC20(0xbf5495Efe5DB9ce00f80364C8B423567e58d2110);

    // Renzo's DepositQueue contract called from RestakeManager.  Used to
    // simulate interest.
    IDepositQueue DEPOSIT_QUEUE =
        IDepositQueue(0xf2F305D14DCD8aaef887E0428B3c9534795D0d60);

    // Renzo's restaking protocol was launch Dec, 2023 and their use of
    // oracles makes it difficult to test on a mainnet fork without heavy
    // mocking.  To test with their deployed code we use a shorter position
    // duration.
    uint256 internal constant POSITION_DURATION_2_WEEKS = 15 days;
    address internal ETH_WHALE = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
    address internal EZETH_WHALE = 0x40C0d1fbcB0A43A62ca7A241E7A42ca58EeF96eb;
    uint256 internal constant STARTING_BLOCK = 19119544;

    HyperdriveFactory factory;
    address deployerCoordinator;

    function setUp() public override __mainnet_fork(STARTING_BLOCK) {
        super.setUp();

        // Fund the test accounts with ezETH and ETH.
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = celine;
        fundAccounts(address(hyperdrive), IERC20(EZETH), EZETH_WHALE, accounts);
        vm.deal(alice, 1_000_000e18);
        vm.deal(bob, 1_000_000e18);
        vm.deal(celine, 1_000_000e18);

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
                address(new EzETHHyperdriveCoreDeployer(RESTAKE_MANAGER)),
                address(new EzETHTarget0Deployer(RESTAKE_MANAGER)),
                address(new EzETHTarget1Deployer(RESTAKE_MANAGER)),
                address(new EzETHTarget2Deployer(RESTAKE_MANAGER)),
                address(new EzETHTarget3Deployer(RESTAKE_MANAGER)),
                address(new EzETHTarget4Deployer(RESTAKE_MANAGER)),
                RESTAKE_MANAGER
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
                positionDuration: POSITION_DURATION_2_WEEKS,
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

        // Depositing with ETH is not allowed for this pool so we need to get
        // some ezETH for alice first.
        uint256 contribution = 10_000e18;
        RESTAKE_MANAGER.depositETH{ value: 2 * contribution }();
        EZETH.approve(deployerCoordinator, contribution);

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
            1e6
        );

        // Start recording event logs.
        vm.recordLogs();
    }

    /// Deploy and Initialize ///

    function test__eth_deployAndInitialize() external {
        // Deploy and Initialize the ezETH hyperdrive instance.
        vm.stopPrank();
        vm.startPrank(bob);

        // Make sure bob has enough funds.
        uint256 contribution = 5_000e18;
        RESTAKE_MANAGER.depositETH{ value: 2 * contribution }();
        EZETH.approve(deployerCoordinator, contribution);

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
                positionDuration: POSITION_DURATION_2_WEEKS,
                checkpointDuration: CHECKPOINT_DURATION,
                timeStretch: 0,
                fees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                })
            });
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

        // Ensure that using base to deploy and initialize is not allowed.
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive = factory.deployAndInitialize{ value: contribution + 1e18 }(
            bytes32(uint256(0xbeefbabe)),
            address(deployerCoordinator),
            config,
            new bytes(0),
            contribution,
            FIXED_RATE,
            FIXED_RATE,
            IHyperdrive.Options({
                asBase: true,
                destination: bob,
                extraData: new bytes(0)
            }),
            bytes32(uint256(0xdeadfade))
        );
    }

    function test__ezeth_deployAndInitialize() external {
        // Deploy and Initialize the ezETH hyperdrive instance.
        vm.stopPrank();
        vm.startPrank(bob);

        // Make sure bob has enough funds.
        uint256 contribution = 5_000e18;
        RESTAKE_MANAGER.depositETH{ value: 2 * contribution }();
        EZETH.approve(deployerCoordinator, contribution);

        // Get balance information.
        uint256 bobBalanceBefore = address(bob).balance;
        uint256 bobEzETHBalanceBefore = EZETH.balanceOf(address(bob));

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
                positionDuration: POSITION_DURATION_2_WEEKS,
                checkpointDuration: CHECKPOINT_DURATION,
                timeStretch: 0,
                fees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                })
            });
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

        // Deploy the pool.
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

        // Ensure eth and ezEth balances are correct.
        assertEq(address(bob).balance, bobBalanceBefore);
        assertEq(
            EZETH.balanceOf(address(bob)),
            bobEzETHBalanceBefore - contribution
        );

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
        assertEq(hyperdrive.getPoolInfo().shareReserves, contribution);
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
            // NOTE: Tolerance since ezETH uses mulDivDown for share calculations.
            1e5
        );
    }

    function test__ezeth_interest_and_advance_time() external {
        // hand calculated value sanity check
        uint256 positionAdjustedInterestRate = uint256(0.05e18).mulDivDown(
            POSITION_DURATION_2_WEEKS,
            365 days
        );

        // Ensure that advancing time accrues interest like we expect.
        (uint256 sharePriceBefore, , ) = getSharePrice();
        advanceTime(POSITION_DURATION_2_WEEKS, 0.05e18);
        (uint256 sharePriceAfter, , ) = getSharePrice();
        assertEq(positionAdjustedInterestRate, 0.002054794520547945e18);
        assertEq(
            sharePriceBefore.mulDown(1e18 + positionAdjustedInterestRate),
            sharePriceAfter
        );
    }

    /// Price Per Share ///

    function test__pricePerVaultShare(uint256 basePaid) external {
        // Ensure that the share price is the expected value.

        // Price in ETH / ezETH, does not include eigenlayer points.
        (uint256 sharePrice, , ) = getSharePrice();
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, sharePrice);

        // Calculate the maximum amount of basePaid we can test.
        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEzEth = EZETH.balanceOf(address(bob));
        uint256 maxRange = maxLong > maxEzEth ? maxEzEth : maxLong;
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxRange
        );

        // Convert to shares and approve hyperdrive.
        vm.startPrank(bob);
        uint256 sharesPaid = getAndApproveShares(basePaid);

        // Collect balance information.
        uint256 hyperdriveSharesBefore = EZETH.balanceOf(address(hyperdrive));

        // Open the position.
        openLong(bob, sharesPaid, false);

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of ETH.
        assertEq(
            EZETH.balanceOf(address(hyperdrive)),
            hyperdriveSharesBefore + sharesPaid
        );
    }

    /// Long ///

    function test_open_long_with_eth(uint256 basePaid) external {
        // Bob opens a long by depositing ETH.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );

        // Ensure that we get an UnsupportedToken error.  Opening positions
        // with ETH are not allowed right now.  There is a great enough
        // precision loss when minting ezeth that warrants some investigation
        // before we can turn this on.  Until then, we can zap ezeth into the
        // pool.
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openLong{ value: basePaid }(
            basePaid,
            0, // min bond proceeds
            0, // min vault share price
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_open_long_with_ezeth(uint256 basePaid) external {
        vm.stopPrank();
        vm.startPrank(bob);

        // Get some balance information before the deposit.
        (
            ,
            uint256 totalPooledEtherBefore,
            uint256 totalSharesBefore
        ) = getSharePrice();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Calculate the maximum amount of basePaid we can test.
        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEzEth = EZETH.balanceOf(address(bob));
        uint256 maxRange = maxLong > maxEzEth ? maxEzEth : maxLong;
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxRange
        );

        // Convert to shares and approve hyperdrive.
        uint256 sharesPaid = getAndApproveShares(basePaid);

        // Open the position.
        openLong(bob, sharesPaid, false);

        // Ensure that Renzo's aggregates and the token balances were updated
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

    function test_close_long_with_eth(uint256 basePaid) external {
        vm.stopPrank();
        vm.startPrank(bob);

        // Calculate the maximum amount of basePaid we can test.
        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEzEth = EZETH.balanceOf(address(bob));
        uint256 maxRange = maxLong > maxEzEth ? maxEzEth : maxLong;
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxRange
        );

        // Convert to shares and approve hyperdrive.
        uint256 sharesPaid = getAndApproveShares(basePaid);

        // Bob opens a long.
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            sharesPaid,
            false
        );

        // Bob attempts to close his long with ETH as the target asset. This
        // fails since ETH isn't supported as a withdrawal asset.
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
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION_2_WEEKS, 0.05e18);
        vm.startPrank(bob);

        // Calculate the maximum amount of basePaid we can test.
        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEzEth = EZETH.balanceOf(address(bob));
        uint256 maxRange = maxLong > maxEzEth ? maxEzEth : maxLong;
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxRange
        );

        // Convert to shares and approve hyperdrive.
        uint256 sharesPaid = getAndApproveShares(basePaid);

        // Bob opens a long.
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            sharesPaid,
            false
        );

        // The term passes and some interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION_2_WEEKS, variableRate);

        // Get some balance information before the withdrawal.
        (
            ,
            uint256 totalPooledEtherBefore,
            uint256 totalSharesBefore
        ) = getSharePrice();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with ezETH as the target asset.
        uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
        (
            ,
            uint256 totalPooledEtherAfter,
            uint256 totalSharesAfter
        ) = getSharePrice();
        uint256 baseProceeds = shareProceeds.mulDivDown(
            totalPooledEtherAfter,
            totalSharesAfter
        );

        // Ensuse that Bob received approximately the bond amount but wasn't
        // overpaid.
        assertLe(baseProceeds, longAmount);
        assertApproxEqAbs(baseProceeds, longAmount, 1e6);

        // Ensure that Renzo's aggregates and the token balances were updated
        // correctly during the trade.
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

    function test_open_short_with_eth(uint256 shortAmount) external {
        vm.stopPrank();
        vm.startPrank(bob);

        // Bob opens a short by depositing ETH.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );

        // Ensure that we get an UnsupportedToken error.  Opening positions
        // with ETH are not allowed right now.  There is a great enough
        // precision loss when minting ezeth that warrants some investigation
        // before we can turn this on.  Until then, we can zap ezeth into the
        // pool.
        vm.expectRevert(IHyperdrive.NotPayable.selector);
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

    function test_open_short_with_ezeth(uint256 shortAmount) external {
        vm.stopPrank();
        vm.startPrank(bob);

        // Get some balance information before the deposit.
        (
            ,
            uint256 totalPooledEtherBefore,
            uint256 totalSharesBefore
        ) = getSharePrice();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Calculate the maximum amount we can short.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );

        // Bob opens a short by depositing ezETH.
        EZETH.approve(address(hyperdrive), shortAmount);
        (, uint256 sharesPaid) = openShort(bob, shortAmount, false);

        // Get the base Bob paid for the short.
        (, uint256 totalPooledEther, uint256 totalShares) = getSharePrice();
        uint256 basePaid = sharesPaid.mulDivDown(totalPooledEther, totalShares);

        // Ensure that the amount of base paid by the short is reasonable.
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            1e18
        );
        assertGt(basePaid, 0);
        assertGe(
            realizedRate,
            FIXED_RATE.mulDown(POSITION_DURATION_2_WEEKS.divDown(365 days))
        );

        // Ensure that Renzo's aggregates and the token balances were updated
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

    function test_open_short_refunds() external {
        vm.startPrank(bob);

        // Collect some balance information.
        uint256 ethBalanceBefore = address(bob).balance;

        // Ensure that the transaction fails when any asBase is true.
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openShort{ value: 2e18 }(
            1e18,
            1e18,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Ensure that the transaction fails when any eth is supplied, even if
        // asBase is false.
        ethBalanceBefore = address(bob).balance;
        EZETH.approve(address(hyperdrive), 1e18);
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openShort{ value: 1e18 }(
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

        // Calculate the maximum amount we can short.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );

        // Approve hyperdrive to use bob's ezEth.
        vm.stopPrank();
        vm.startPrank(bob);
        EZETH.approve(address(hyperdrive), shortAmount);

        // Bob opens a short.
        (uint256 maturityTime, ) = openShort(bob, shortAmount, false);

        // NOTE: The variable rate must be greater than 0 since the unsupported
        // check is only triggered if the shares amount is non-zero.
        //
        // The term passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0.01e18, 2.5e18);
        advanceTime(POSITION_DURATION_2_WEEKS, variableRate);

        // Bob attempts to close his short with ETH as the target asset. This
        // fails since ETH isn't supported as a withdrawal asset.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
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
    }

    function test_close_short_with_ezeth(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION_2_WEEKS, 0.05e18);

        // Calculate the maximum amount we can short.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );

        // Approve hyperdrive to use bob's ezEth.
        vm.stopPrank();
        vm.startPrank(bob);
        EZETH.approve(address(hyperdrive), shortAmount);

        // Bob opens a short.
        (uint256 maturityTime, ) = openShort(bob, shortAmount, false);

        // The term passes and interest accrues.
        uint256 startingVaultSharePrice = hyperdrive
            .getPoolInfo()
            .vaultSharePrice;
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION_2_WEEKS, variableRate);

        // Get some balance information before closing the short.
        (
            ,
            uint256 totalPooledEtherBefore,
            uint256 totalSharesBefore
        ) = getSharePrice();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his short with ezETH as the target asset. Bob's proceeds
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
        (, uint256 totalPooledEther, uint256 totalShares) = getSharePrice();
        uint256 baseProceeds = shareProceeds.mulDivDown(
            totalPooledEther,
            totalShares
        );
        assertLe(baseProceeds, expectedBaseProceeds + 1e4);
        assertApproxEqAbs(baseProceeds, expectedBaseProceeds, 1e5);

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyEzethWithdrawal(
            bob,
            baseProceeds,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_attack_long_ezeth() external {
        // Get some balance information before the deposit.
        EZETH.balanceOf(address(hyperdrive));

        vm.startPrank(bob);

        // Figure out the max shares
        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEzEth = EZETH.balanceOf(address(bob));
        uint256 basePaid = maxLong > maxEzEth ? maxEzEth : maxLong;
        uint256 sharesPaid = getAndApproveShares(basePaid);

        // Bob opens a long by depositing ezETH.
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            sharesPaid,
            false
        );

        // Get some balance information before the withdrawal.
        (
            ,
            uint256 totalPooledEtherBefore,
            uint256 totalSharesBefore
        ) = getSharePrice();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with ezETH as the target asset.
        uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
        (, uint256 totalPooledEther, uint256 totalShares) = getSharePrice();
        uint256 baseProceeds = shareProceeds.mulDivDown(
            totalPooledEther,
            totalShares
        );

        // Ensure that Renzo's aggregates and the token balances were updated
        // correctly during the trade.
        verifyEzethWithdrawal(
            bob,
            baseProceeds,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

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
            (, uint256 totalPooledEther, ) = getSharePrice();
            assertEq(totalPooledEther, totalPooledEtherBefore + basePaid);

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(bob.balance, traderBalancesBefore.ETHBalance - basePaid);

            // Ensure ezETH shares were updated correctly.
            assertEq(
                EZETH.balanceOf(trader),
                traderBalancesBefore.ezethBalance
            );

            // Ensure that the ezETH shares were updated correctly.
            uint256 expectedShares = RENZO_ORACLE.calculateMintAmount(
                totalPooledEtherBefore,
                basePaid,
                totalSharesBefore
            );
            assertEq(EZETH.totalSupply(), totalSharesBefore + expectedShares);
            assertEq(
                EZETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.ezethBalance + expectedShares
            );
            assertEq(EZETH.balanceOf(bob), traderBalancesBefore.ezethBalance);
        } else {
            // Ensure that the amount of pooled ether stays the same.
            (, uint256 totalPooledEther, ) = getSharePrice();
            assertEq(totalPooledEther, totalPooledEtherBefore);

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(trader.balance, traderBalancesBefore.ETHBalance);

            // Ensure that the ezETH shares were updated correctly.
            uint256 expectedShares = basePaid.mulDivDown(
                totalSharesBefore,
                totalPooledEtherBefore
            );
            assertEq(EZETH.totalSupply(), totalSharesBefore);
            assertApproxEqAbs(
                EZETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.ezethBalance + expectedShares,
                1
            );
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
        (, uint256 totalPooledEther, ) = getSharePrice();
        assertEq(totalPooledEther, totalPooledEtherBefore);
        assertApproxEqAbs(EZETH.totalSupply(), totalSharesBefore, 1);

        // Ensure that the ETH balances were updated correctly.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(trader.balance, traderBalancesBefore.ETHBalance);

        // Ensure that the ezETH shares were updated correctly.
        uint256 expectedShares = baseProceeds.mulDivDown(
            totalSharesBefore,
            totalPooledEtherBefore
        );
        assertApproxEqAbs(
            EZETH.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.ezethBalance - expectedShares,
            1
        );
        assertApproxEqAbs(
            EZETH.balanceOf(trader),
            traderBalancesBefore.ezethBalance + expectedShares,
            1
        );
    }

    /// Helpers ///

    function advanceTime(
        uint256 timeDelta, // assume a position duration jump
        int256 variableRate // annual variable rate
    ) internal override {
        // Advance the time by a position duration and accrue interest.  We
        // adjust the variable rate to the position duration and multiply the
        // TVL to get interest:
        //
        //  sharePriceBefore * adjustedVariableRate = sharePriceAfter
        //
        //  becomes:
        //
        //  (tvlBefore / ezETHSupply) * adjustedVariableRate = tvlAfter / ezETHSuuply
        //
        //  tvlBefore * adjustedVariableRate = tvlAfter
        //
        //  Since the ezETHSupply is held constant when we advanceTime.

        (, uint256 totalTVLBefore, ) = getSharePrice();
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in Renzo. Since the share price is given by
        // `RESTAKE_MANAGER.calculateTVLs() / EZETH.totalSupply()`, we can simulate the
        // accrual of interest by adding to the balance of the DepositQueue contract.
        // RestakeManager adds the balance of the DepositQueue to totalTVL in calculateTVLs()
        uint256 adjustedVariableRate = uint256(variableRate).mulDivDown(
            POSITION_DURATION_2_WEEKS,
            365 days
        );
        uint256 ethToAdd = totalTVLBefore.mulDown(adjustedVariableRate);
        if (variableRate >= 0) {
            vm.startPrank(address(RESTAKE_MANAGER));
            vm.deal(address(RESTAKE_MANAGER), ethToAdd);
            // use this method because no fees are taken
            DEPOSIT_QUEUE.depositETHFromProtocol{ value: ethToAdd }();
        } else {
            // NOTE: can't support subtracting eth when depositQueue has a zero balance.
            vm.deal(
                address(DEPOSIT_QUEUE),
                address(DEPOSIT_QUEUE).balance - ethToAdd
            );
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

    // returns share price information.
    function getSharePrice()
        internal
        view
        returns (
            uint256 sharePrice,
            uint256 totalPooledEther,
            uint256 totalShares
        )
    {
        // Get the total TVL priced in ETH from restakeManager.
        (, , uint256 totalTVL) = RESTAKE_MANAGER.calculateTVLs();

        // Get the total supply of the ezETH token.
        uint256 totalSupply = EZETH.totalSupply();

        // Calculate the share price.
        sharePrice = RENZO_ORACLE.calculateRedeemAmount(
            ONE,
            totalSupply,
            totalTVL
        );

        return (sharePrice, totalTVL, totalSupply);
    }

    function getAndApproveShares(
        uint256 basePaid
    ) internal returns (uint256 sharesPaid) {
        // Get the share amount.
        (, uint256 totalPooledEther, uint256 totalShares) = getSharePrice();
        sharesPaid = basePaid.mulDivDown(totalShares, totalPooledEther);

        // Approve hyperdrive to use the shares.
        EZETH.approve(address(hyperdrive), sharesPaid);
    }
}
