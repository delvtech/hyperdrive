// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { StETHHyperdriveCoreDeployer } from "contracts/src/deployers/steth/StETHHyperdriveCoreDeployer.sol";
import { StETHHyperdriveDeployerCoordinator } from "contracts/src/deployers/steth/StETHHyperdriveDeployerCoordinator.sol";
import { StETHTarget0Deployer } from "contracts/src/deployers/steth/StETHTarget0Deployer.sol";
import { StETHTarget1Deployer } from "contracts/src/deployers/steth/StETHTarget1Deployer.sol";
import { StETHTarget2Deployer } from "contracts/src/deployers/steth/StETHTarget2Deployer.sol";
import { StETHTarget3Deployer } from "contracts/src/deployers/steth/StETHTarget3Deployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { ETH } from "test/utils/Constants.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract StETHHyperdriveTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    uint256 internal constant FIXED_RATE = 0.05e18;

    // The Lido storage location that tracks buffered ether reserves. We can
    // simulate the accrual of interest by updating this value.
    bytes32 internal constant BUFFERED_ETHER_POSITION =
        keccak256("lido.Lido.bufferedEther");

    ILido internal constant LIDO =
        ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    address internal STETH_WHALE = 0x1982b2F5814301d4e9a8b0201555376e62F82428;
    address internal ETH_WHALE = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    HyperdriveFactory factory;
    address deployerCoordinator;

    function setUp() public override __mainnet_fork(17_376_154) {
        super.setUp();

        // Deploy the hyperdrive factory.
        vm.startPrank(deployer);
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ForwarderFactory();
        factory = new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: celine,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
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
            new StETHHyperdriveDeployerCoordinator(
                address(new StETHHyperdriveCoreDeployer(LIDO)),
                address(new StETHTarget0Deployer(LIDO)),
                address(new StETHTarget1Deployer(LIDO)),
                address(new StETHTarget2Deployer(LIDO)),
                address(new StETHTarget3Deployer(LIDO)),
                LIDO
            )
        );
        factory.addHyperdriveDeployer(address(deployerCoordinator));

        // Alice deploys the hyperdrive instance.
        IHyperdrive.PoolDeployConfig memory config = IHyperdrive
            .PoolDeployConfig({
                baseToken: IERC20(ETH),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0),
                minimumShareReserves: 1e15,
                minimumTransactionAmount: 1e14,
                positionDuration: POSITION_DURATION,
                checkpointDuration: CHECKPOINT_DURATION,
                timeStretch: HyperdriveUtils.calculateTimeStretch(
                    0.05e18,
                    POSITION_DURATION
                ),
                governance: address(0),
                feeCollector: address(0),
                fees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                })
            });
        uint256 contribution = 10_000e18;
        hyperdrive = factory.deployAndInitialize{ value: contribution }(
            deployerCoordinator,
            config,
            new bytes(0),
            contribution,
            FIXED_RATE,
            new bytes(0)
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
            1e5
        );

        // Fund the test accounts with stETH and ETH.
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = celine;
        fundAccounts(address(hyperdrive), IERC20(LIDO), STETH_WHALE, accounts);
        vm.deal(alice, 20_000e18);
        vm.deal(bob, 20_000e18);
        vm.deal(celine, 20_000e18);

        // Start recording event logs.
        vm.recordLogs();
    }

    /// Deploy and Initialize ///

    function test__steth__deployAndInitialize() external {
        // Deploy and Initialize the stETH hyperdrive instance. Excess ether is
        // sent, and should be returned to the sender.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bobBalanceBefore = address(bob).balance;
        IHyperdrive.PoolDeployConfig memory config = IHyperdrive
            .PoolDeployConfig({
                baseToken: IERC20(ETH),
                governance: address(0),
                feeCollector: address(0),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0),
                minimumShareReserves: 1e15,
                minimumTransactionAmount: 1e14,
                positionDuration: POSITION_DURATION,
                checkpointDuration: CHECKPOINT_DURATION,
                timeStretch: HyperdriveUtils.calculateTimeStretch(
                    0.05e18,
                    POSITION_DURATION
                ),
                fees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                })
            });
        uint256 contribution = 5_000e18;
        hyperdrive = factory.deployAndInitialize{ value: contribution + 1e18 }(
            address(deployerCoordinator),
            config,
            new bytes(0),
            contribution,
            FIXED_RATE,
            new bytes(0)
        );
        assertEq(address(bob).balance, bobBalanceBefore - contribution);

        // Ensure that Bob received the correct amount of LP tokens. He should
        // receive LP shares totaling the amount of shares that he contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, bob),
            contribution.divDown(
                hyperdrive.getPoolConfig().initialVaultSharePrice
            ) - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
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

    function test__pricePerVaultShare(uint256 basePaid) external {
        // Ensure that the share price is the expected value.
        uint256 totalPooledEther = LIDO.getTotalPooledEther();
        uint256 totalShares = LIDO.getTotalShares();
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, totalPooledEther.divDown(totalShares));

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of ETH. This will
        // be an approximation since Lido uses `mulDivDown` whereas this test
        // pre-computes the share price.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        uint256 hyperdriveSharesBefore = LIDO.sharesOf(address(hyperdrive));
        openLong(bob, basePaid);
        assertApproxEqAbs(
            LIDO.sharesOf(address(hyperdrive)),
            hyperdriveSharesBefore + basePaid.divDown(vaultSharePrice),
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
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        uint256 sharesPaid = basePaid.mulDivDown(
            LIDO.getTotalShares(),
            LIDO.getTotalPooledEther()
        );
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

    function test_close_long_with_steth(
        uint256 basePaid,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION, 0.05e18);

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
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with stETH as the target asset.
        uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
        uint256 baseProceeds = shareProceeds.mulDivDown(
            LIDO.getTotalPooledEther(),
            LIDO.getTotalShares()
        );

        // Ensuse that Bob received approximately the bond amount but wasn't
        // overpaid.
        assertLe(baseProceeds, longAmount);
        assertApproxEqAbs(baseProceeds, longAmount, 10);

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

    function test_open_short_with_ETH(uint256 shortAmount) external {
        // Get some balance information before the deposit.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a short by depositing ETH.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
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
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        (, uint256 sharesPaid) = openShort(bob, shortAmount, false);
        uint256 basePaid = sharesPaid.mulDivDown(
            LIDO.getTotalPooledEther(),
            LIDO.getTotalShares()
        );

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

    function test_open_short_refunds() external {
        vm.startPrank(bob);

        // Ensure that Bob receives a refund on the excess ETH that he sent
        // when opening a long with "asBase" set to true.
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

        // Ensure that Bob receives a  refund when he opens a long with "asBase"
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
        // Bob opens a short.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
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

    function test_close_short_with_steth(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION, 0.05e18);

        // Bob opens a short.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        uint256 balanceBefore = bob.balance;
        vm.deal(bob, shortAmount);
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);
        vm.deal(bob, balanceBefore - basePaid);

        // The term passes and interest accrues.
        uint256 startingVaultSharePrice = hyperdrive
            .getPoolInfo()
            .vaultSharePrice;
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
        uint256 baseProceeds = shareProceeds.mulDivDown(
            LIDO.getTotalPooledEther(),
            LIDO.getTotalShares()
        );
        assertLe(baseProceeds, expectedBaseProceeds + 10);
        assertApproxEqAbs(baseProceeds, expectedBaseProceeds, 100);

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

    function test_attack_long_steth() external {
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
        uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
        uint256 baseProceeds = shareProceeds.mulDivDown(
            LIDO.getTotalPooledEther(),
            LIDO.getTotalShares()
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
    }

    function test__DOSStethHyperdriveCloseLong() external {
        //###########################################################################"
        //#### TEST: Denial of Service when LIDO's `TotalPooledEther` decreases. ####"
        //###########################################################################"

        // Ensure that the share price is the expected value.
        uint256 totalPooledEther = LIDO.getTotalPooledEther();
        uint256 totalShares = LIDO.getTotalShares();
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, totalPooledEther.divDown(totalShares));

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
            hyperdriveSharesBefore + basePaid.divDown(vaultSharePrice),
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
        uint256 shareProceeds = closeLong(
            bob,
            maturityTime,
            longAmount / 2,
            false
        );
        uint256 baseProceeds = shareProceeds.mulDivDown(
            LIDO.getTotalPooledEther(),
            LIDO.getTotalShares()
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
        bool asBase,
        uint256 totalPooledEtherBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        if (asBase) {
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
            assertApproxEqAbs(
                LIDO.sharesOf(address(hyperdrive)),
                hyperdriveBalancesBefore.stethShares + expectedShares,
                1
            );
            assertApproxEqAbs(
                LIDO.sharesOf(trader),
                traderBalancesBefore.stethShares - expectedShares,
                1
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
