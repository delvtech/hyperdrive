// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC4626HyperdriveCoreDeployer } from "../../../contracts/src/deployers/erc4626/ERC4626HyperdriveCoreDeployer.sol";
import { ERC4626HyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/erc4626/ERC4626HyperdriveDeployerCoordinator.sol";
import { ERC4626Target0Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target0Deployer.sol";
import { ERC4626Target1Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target1Deployer.sol";
import { ERC4626Target2Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target2Deployer.sol";
import { ERC4626Target3Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target3Deployer.sol";
import { ERC4626Target4Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target4Deployer.sol";
import { HyperdriveFactory } from "../../../contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../../contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../../../contracts/src/interfaces/IHyperdriveDeployerCoordinator.sol";
import { IHyperdriveFactory } from "../../../contracts/src/interfaces/IHyperdriveFactory.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { ERC20ForwarderFactory } from "../../../contracts/src/token/ERC20ForwarderFactory.sol";
import { MockERC4626Hyperdrive } from "../../../contracts/test/MockERC4626Hyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

abstract contract ERC4626ValidationTest is HyperdriveTest {
    using FixedPointMath for *;
    using Lib for *;

    string internal constant HYPERDRIVE_NAME = "Hyperdrive";
    string internal constant COORDINATOR_NAME = "HyperdriveDeployerCoordinator";

    address internal deployerCoordinator;
    address internal coreDeployer;
    address internal target0Deployer;
    address internal target1Deployer;
    address internal target2Deployer;
    address internal target3Deployer;
    address internal target4Deployer;

    IERC20 internal underlyingToken;
    IERC4626 internal token;
    MockERC4626Hyperdrive internal hyperdriveInstance;
    IHyperdriveFactory internal factory;

    uint8 internal decimals = 18;
    uint256 internal constant FIXED_RATE = 0.05e18;

    function _setUp() internal {
        super.setUp();

        vm.startPrank(deployer);

        // Deploy the ERC4626Hyperdrive factory and deployer.
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ERC20ForwarderFactory("ForwarderFactory");
        factory = new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                deployerCoordinatorManager: celine,
                hyperdriveGovernance: bob,
                feeCollector: feeCollector,
                sweepCollector: sweepCollector,
                checkpointRewarder: address(checkpointRewarder),
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minCircuitBreakerDelta: 0.15e18,
                // NOTE: This is a high max circuit breaker delta to ensure that
                // trading during tests isn't impeded by the circuit breaker.
                maxCircuitBreakerDelta: 2e18,
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
            }),
            "HyperdriveFactory"
        );
        coreDeployer = address(new ERC4626HyperdriveCoreDeployer());
        target0Deployer = address(new ERC4626Target0Deployer());
        target1Deployer = address(new ERC4626Target1Deployer());
        target2Deployer = address(new ERC4626Target2Deployer());
        target3Deployer = address(new ERC4626Target3Deployer());
        target4Deployer = address(new ERC4626Target4Deployer());
        deployerCoordinator = address(
            new ERC4626HyperdriveDeployerCoordinator(
                COORDINATOR_NAME,
                address(factory),
                coreDeployer,
                target0Deployer,
                target1Deployer,
                target2Deployer,
                target3Deployer,
                target4Deployer
            )
        );

        // Config changes required to support ERC4626 with the correct initial Share Price
        IHyperdrive.PoolDeployConfig memory config = testDeployConfig(
            FIXED_RATE,
            POSITION_DURATION
        );
        config.baseToken = underlyingToken;
        config.vaultSharesToken = token;
        config.governance = factory.hyperdriveGovernance();
        config.feeCollector = factory.feeCollector();
        config.linkerFactory = factory.linkerFactory();
        config.linkerCodeHash = factory.linkerCodeHash();
        config.timeStretch = 0;
        uint256 contribution = 7_500e18;
        vm.stopPrank();
        vm.startPrank(alice);

        factory.addDeployerCoordinator(deployerCoordinator);

        // Set approval to allow initial contribution to factory
        underlyingToken.approve(
            address(deployerCoordinator),
            type(uint256).max
        );

        // Deploy and set hyperdrive instance
        for (
            uint256 i = 0;
            i <
            IHyperdriveDeployerCoordinator(deployerCoordinator)
                .getNumberOfTargets();
            i++
        ) {
            factory.deployTarget(
                bytes32(uint256(0xdeadbeef)),
                deployerCoordinator,
                config,
                new bytes(0),
                FIXED_RATE,
                FIXED_RATE,
                i,
                bytes32(uint256(0xdeadbabe))
            );
        }
        hyperdrive = factory.deployAndInitialize(
            bytes32(uint256(0xdeadbeef)),
            deployerCoordinator,
            HYPERDRIVE_NAME,
            config,
            new bytes(0),
            contribution,
            FIXED_RATE,
            FIXED_RATE,
            IHyperdrive.Options({
                asBase: true,
                destination: alice,
                extraData: new bytes(0)
            }),
            bytes32(uint256(0xdeadbabe))
        );

        // Setup maximum approvals so transfers don't require further approval
        underlyingToken.approve(address(hyperdrive), type(uint256).max);
        underlyingToken.approve(address(token), type(uint256).max);
        token.approve(address(hyperdrive), type(uint256).max);
        vm.stopPrank();

        // Start recording events.
        vm.recordLogs();
    }

    function advanceTimeWithYield(
        uint256 timeDelta,
        int256 variableRate
    ) public virtual;

    function test_deployAndInitialize_asBase() external {
        vm.startPrank(alice);

        IHyperdrive.PoolDeployConfig memory config = testDeployConfig(
            FIXED_RATE,
            POSITION_DURATION
        );
        config.governance = factory.hyperdriveGovernance();
        config.feeCollector = factory.feeCollector();
        config.linkerFactory = factory.linkerFactory();
        config.linkerCodeHash = factory.linkerCodeHash();
        config.timeStretch = 0;
        config.baseToken = underlyingToken;
        config.vaultSharesToken = token;
        // Designed to ensure compatibility ../../contracts/src/instances/ERC4626Hyperdrive.sol#L122C1-L122C1
        config.minimumTransactionAmount = hyperdrive
            .getPoolConfig()
            .minimumTransactionAmount;
        config.minimumShareReserves = hyperdrive
            .getPoolConfig()
            .minimumShareReserves;
        uint256 contribution = 10_000 * 10 ** decimals;
        underlyingToken.approve(
            address(deployerCoordinator),
            type(uint256).max
        );

        // Deploy a new hyperdrive instance
        for (
            uint256 i = 0;
            i <
            IHyperdriveDeployerCoordinator(deployerCoordinator)
                .getNumberOfTargets();
            i++
        ) {
            factory.deployTarget(
                bytes32(uint256(0xbeef)),
                deployerCoordinator,
                config,
                new bytes(0),
                FIXED_RATE,
                FIXED_RATE,
                i,
                bytes32(uint256(0xfade))
            );
        }
        hyperdrive = factory.deployAndInitialize(
            bytes32(uint256(0xbeef)),
            deployerCoordinator,
            HYPERDRIVE_NAME,
            config,
            new bytes(0),
            contribution,
            FIXED_RATE,
            FIXED_RATE,
            IHyperdrive.Options({
                asBase: true,
                destination: alice,
                extraData: new bytes(0)
            }),
            bytes32(uint256(0xfade))
        );

        // Ensure that the decimals are set correctly.
        assertEq(hyperdrive.decimals(), decimals);

        // Ensure that the minimum share reserves was successfully capitalized
        // and that the LP total supply was updated to the correct value.
        assertEq(
            hyperdrive.getPoolInfo().lpTotalSupply,
            hyperdrive.getPoolInfo().shareReserves - config.minimumShareReserves
        );

        // Verify that the correct events were emitted during creation
        verifyFactoryEvents(
            deployerCoordinator,
            hyperdrive,
            alice,
            contribution,
            FIXED_RATE,
            true,
            config.minimumShareReserves,
            new bytes(0),
            1e5
        );
    }

    function test_OpenLongWithUnderlying_failure() external {
        vm.startPrank(alice);
        uint256 baseAmount = 10e18;
        underlyingToken.approve(address(hyperdrive), baseAmount);
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openLong{ value: baseAmount }(
            baseAmount,
            0,
            0,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_OpenLongWithUnderlying(uint256 basePaid) external {
        // Establish baseline variables
        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        vm.startPrank(alice);

        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        basePaid = basePaid.normalizeToRange(
            hyperdrive.getPoolConfig().minimumTransactionAmount * 2,
            maxLong.min(underlyingToken.balanceOf(alice))
        );

        // Open a long with underlying tokens
        openLongERC4626(alice, basePaid, true);

        // Verify balances correctly updated
        verifyDepositUnderlying(
            alice,
            basePaid,
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_OpenLongWithShares(uint256 basePaid) external {
        vm.startPrank(alice);
        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        basePaid = basePaid.normalizeToRange(
            token.convertToAssets(
                hyperdrive.getPoolConfig().minimumTransactionAmount
            ),
            maxLong.min(underlyingToken.balanceOf(alice))
        );
        underlyingToken.approve(address(token), type(uint256).max);

        // Deposit into the ERC4626 so underlying doesn't need to be used
        uint256 shares = token.deposit(basePaid, alice);

        // Establish baseline, important underlying balance must be taken AFTER
        // deposit into ERC4626 token
        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Open the long
        openLongERC4626(alice, shares, false);

        // Ensure balances correctly updated
        verifyDepositShares(
            alice,
            basePaid,
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_CloseLongWithUnderlying(
        uint256 basePaid,
        int256 variableRate
    ) external {
        // Advance time with positive interest for a term to ensure that the
        // share price isn't equal to one.
        advanceTimeWithYield(POSITION_DURATION, 0.05e18);

        // Alice opens a long.
        vm.startPrank(alice);
        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        basePaid = basePaid.normalizeToRange(
            hyperdrive.getPoolConfig().minimumTransactionAmount * 2,
            maxLong.min(underlyingToken.balanceOf(alice))
        );

        // Open a long.
        (uint256 maturityTime, uint256 longAmount) = openLongERC4626(
            alice,
            basePaid,
            true
        );

        // The term passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTimeWithYield(POSITION_DURATION, variableRate);

        // Establish a baseline of balances before closing long.
        uint256 totalPooledAssetsBefore = token.totalAssets();
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Close long with underlying assets.
        uint256 baseProceeds = hyperdrive.closeLong(
            maturityTime,
            longAmount,
            0,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Ensure that the long received the correct amount of base and wasn't
        // overcompensated.
        uint256 expectedBaseProceeds = longAmount;
        assertLe(baseProceeds, expectedBaseProceeds);
        assertApproxEqAbs(baseProceeds, expectedBaseProceeds, 100);

        // Ensure that the ERC4626 aggregates and the token balances were updated
        // correctly during the trade.
        verifyWithdrawalShares(
            alice,
            baseProceeds,
            totalPooledAssetsBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_CloseLongWithShares(uint256 basePaid) external {
        vm.startPrank(alice);

        // Alice opens a long.
        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        basePaid = basePaid.normalizeToRange(
            token.convertToAssets(
                hyperdrive.getPoolConfig().minimumTransactionAmount
            ),
            maxLong.min(underlyingToken.balanceOf(alice))
        );

        // Open a long
        (uint256 maturityTime, uint256 longAmount) = openLongERC4626(
            alice,
            basePaid,
            true
        );

        // Establish a baseline of balances before closing long
        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Close the long
        uint256 shareProceeds = hyperdrive.closeLong(
            maturityTime,
            longAmount,
            0,
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: new bytes(0)
            })
        );

        // Ensure balances updated correctly
        verifyWithdrawalToken(
            alice,
            shareProceeds,
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_OpenShortWithUnderlying() external {
        vm.startPrank(alice);

        uint256 maxShort = HyperdriveUtils.calculateMaxShort(hyperdrive);
        uint256 shortAmount = 0.001e18;
        shortAmount = shortAmount.normalizeToRange(
            hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxShort.min(underlyingToken.balanceOf(alice))
        );

        // Take a baseline
        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Open a short
        (, uint256 basePaid) = openShortERC4626(alice, shortAmount, true);

        // Ensure that the amount of base paid by the short is reasonable.
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            1e18
        );

        // Ensure some base was paid
        assertGt(basePaid, 0);
        assertGe(realizedRate, FIXED_RATE);

        // Ensure the balances updated correctly
        verifyDepositUnderlying(
            alice,
            basePaid,
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_OpenShortWithShares(uint256 shortAmount) external {
        vm.startPrank(alice);
        uint256 maxShort = HyperdriveUtils.calculateMaxShort(hyperdrive);
        shortAmount = shortAmount.normalizeToRange(
            hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxShort.min(underlyingToken.balanceOf(alice))
        );
        underlyingToken.approve(address(token), type(uint256).max);
        // Deposit into the actual ERC4626 token
        token.deposit(shortAmount, alice);

        // Establish a baseline before we open the short
        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Open the short
        (, uint256 sharesPaid) = openShortERC4626(alice, shortAmount, false);

        // Ensure we did actually paid a non-Zero amount of base
        assertGt(sharesPaid, 0);
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - token.convertToAssets(sharesPaid),
            shortAmount,
            1e18
        );
        assertGe(realizedRate, FIXED_RATE);

        // Ensure balances were correctly updated
        verifyDepositShares(
            alice,
            token.convertToAssets(sharesPaid),
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_CloseShortWithUnderlying(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        _test_CloseShortWithUnderlying(shortAmount, variableRate);
    }

    function test_CloseShortWithUnderlying_EdgeCases() external {
        // Test zero proceeds case
        // Note: This only results in zero proceeds for stethERC4626 and UsdcERC4626
        {
            uint256 shortAmount = 0;
            int256 variableRate = 0;
            _test_CloseShortWithUnderlying(shortAmount, variableRate);
        }
    }

    function _test_CloseShortWithUnderlying(
        uint256 shortAmount,
        int256 variableRate
    ) internal {
        // Advance time with positive interest for a term to ensure that the
        // share price isn't equal to one.
        advanceTimeWithYield(POSITION_DURATION, 0.05e18);

        // Open a short.
        vm.startPrank(alice);
        uint256 maxShort = HyperdriveUtils.calculateMaxShort(hyperdrive);
        shortAmount = shortAmount.normalizeToRange(
            hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxShort.min(underlyingToken.balanceOf(alice)).mulDown(0.95e18)
        );
        (uint256 maturityTime, ) = openShortERC4626(alice, shortAmount, true);

        // The term passes and interest accrues.
        uint256 startingVaultSharePrice = hyperdrive
            .getPoolInfo()
            .vaultSharePrice;
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTimeWithYield(POSITION_DURATION, variableRate);

        // Establish a baseline before closing the short
        uint256 totalPooledAssetsBefore = token.totalAssets();
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Close the short.
        uint256 baseProceeds = hyperdrive.closeShort(
            maturityTime,
            shortAmount,
            0,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Ensure that the short received the correct amount of base and wasn't
        // overcompensated.
        uint256 expectedBaseProceeds = shortAmount.mulDivDown(
            hyperdrive.getPoolInfo().vaultSharePrice - startingVaultSharePrice,
            startingVaultSharePrice
        );
        assertLe(baseProceeds, expectedBaseProceeds + 10);
        assertApproxEqAbs(baseProceeds, expectedBaseProceeds, 1e5);

        // Ensure that the ERC4626 aggregates and the token balances were updated
        // correctly during the trade.
        verifyWithdrawalShares(
            alice,
            baseProceeds,
            totalPooledAssetsBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_CloseShortWithShares(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        _test_CloseShortWithShares(shortAmount, variableRate);
    }

    function test_CloseShortWithShares_EdgeCases() external {
        {
            uint256 shortAmount = 8300396556459030614636;
            int256 variableRate = 7399321782946468277;
            _test_CloseShortWithShares(shortAmount, variableRate);
        }

        // Test zero proceeds case
        // Note: This only results in zero proceeds for stethERC4626 and UsdcERC4626
        {
            uint256 shortAmount = 0;
            int256 variableRate = 0;
            _test_CloseShortWithShares(shortAmount, variableRate);
        }
    }

    function _test_CloseShortWithShares(
        uint256 shortAmount,
        int256 variableRate
    ) internal {
        vm.startPrank(alice);
        uint256 maxShort = HyperdriveUtils.calculateMaxShort(hyperdrive);
        shortAmount = shortAmount.normalizeToRange(
            hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxShort.min(underlyingToken.balanceOf(alice)).mulDown(0.95e18)
        );

        // Deposit into the actual ERC4626
        underlyingToken.approve(address(token), type(uint256).max);
        token.deposit(shortAmount, alice);

        // Open the short
        (uint256 maturityTime, ) = openShortERC4626(alice, shortAmount, false);

        // The term passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);

        // Advance time and accumulate the yield
        advanceTimeWithYield(POSITION_DURATION, variableRate);

        // Establish a baseline before closing the short
        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Close the short
        uint256 proceeds = hyperdrive.closeShort(
            maturityTime,
            shortAmount,
            0,
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: new bytes(0)
            })
        );

        // Ensure that the ERC4626 aggregates and the token balances were updated
        // correctly during the trade.
        verifyWithdrawalToken(
            alice,
            proceeds,
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function openLongERC4626(
        address trader,
        uint256 baseAmount,
        bool asBase
    ) internal returns (uint256 maturityTime, uint256 bondAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the long.
        if (asBase) {
            underlyingToken.approve(address(hyperdrive), baseAmount);
            (maturityTime, bondAmount) = hyperdrive.openLong(
                baseAmount,
                0,
                0,
                IHyperdrive.Options({
                    destination: trader,
                    asBase: asBase,
                    extraData: new bytes(0)
                })
            );
        } else {
            token.approve(address(hyperdrive), baseAmount);
            (maturityTime, bondAmount) = hyperdrive.openLong(
                baseAmount,
                0,
                0,
                IHyperdrive.Options({
                    destination: trader,
                    asBase: asBase,
                    extraData: new bytes(0)
                })
            );
        }

        return (maturityTime, bondAmount);
    }

    function openShortERC4626(
        address trader,
        uint256 bondAmount,
        bool asBase
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);
        // Open the short
        if (asBase) {
            underlyingToken.approve(address(hyperdrive), bondAmount);
            (maturityTime, baseAmount) = hyperdrive.openShort(
                bondAmount,
                type(uint256).max,
                0,
                IHyperdrive.Options({
                    destination: trader,
                    asBase: asBase,
                    extraData: new bytes(0)
                })
            );
        } else {
            token.approve(address(hyperdrive), bondAmount);
            (maturityTime, baseAmount) = hyperdrive.openShort(
                bondAmount,
                type(uint256).max,
                0,
                IHyperdrive.Options({
                    destination: trader,
                    asBase: asBase,
                    extraData: new bytes(0)
                })
            );
        }
        return (maturityTime, baseAmount);
    }

    function verifyDepositUnderlying(
        address trader,
        uint256 basePaid,
        uint256 totalPooledAssetsBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view {
        // Ensure that the amount of assets increased by the base paid.
        assertApproxEqAbs(
            token.totalAssets(),
            totalPooledAssetsBefore + basePaid,
            2
        );

        // Ensure that the underlyingToken balances were updated correctly.
        assertApproxEqAbs(
            underlyingToken.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.underlyingBalance,
            2
        );
        assertApproxEqAbs(
            underlyingToken.balanceOf(trader),
            traderBalancesBefore.underlyingBalance - basePaid,
            2
        );

        // Ensure that the token balances were updated correctly.
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.shareBalance +
                token.convertToShares(basePaid),
            1
        );
        assertApproxEqAbs(
            token.balanceOf(trader),
            traderBalancesBefore.shareBalance,
            2
        );
        // Ensure that the token shares were updated correctly.
        uint256 expectedShares = basePaid.mulDivDown(
            totalSharesBefore,
            totalPooledAssetsBefore
        );
        assertApproxEqAbs(
            token.convertToShares(token.totalAssets()),
            totalSharesBefore + expectedShares,
            2
        );
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.shareBalance + expectedShares,
            2
        );
        assertApproxEqAbs(
            token.balanceOf(trader),
            traderBalancesBefore.shareBalance,
            2
        );
    }

    function verifyDepositShares(
        address trader,
        uint256 basePaid,
        uint256 totalPooledAssetsBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view {
        // Ensure that the totalAssets of the token stays the same.
        assertEq(token.totalAssets(), totalPooledAssetsBefore);

        // Ensure that the underlying token balances were updated correctly.
        assertEq(
            underlyingToken.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.underlyingBalance
        );
        assertEq(
            underlyingToken.balanceOf(trader),
            traderBalancesBefore.underlyingBalance
        );

        // Ensure that the token balances were updated correctly.
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.shareBalance +
                token.convertToShares(basePaid),
            2
        );
        assertApproxEqAbs(
            token.balanceOf(trader),
            traderBalancesBefore.shareBalance - token.convertToShares(basePaid),
            2
        );

        // Ensure that the token shares were updated correctly.
        uint256 expectedShares = basePaid.mulDivDown(
            totalSharesBefore,
            totalPooledAssetsBefore
        );
        assertApproxEqAbs(
            token.convertToShares(token.totalAssets()),
            totalSharesBefore,
            2
        );
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.shareBalance + expectedShares,
            2
        );
        assertApproxEqAbs(
            token.balanceOf(trader),
            traderBalancesBefore.shareBalance - expectedShares,
            2
        );
    }

    function verifyWithdrawalToken(
        address trader,
        uint256 shareProceeds,
        uint256 totalPooledAssetsBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view {
        // Ensure that the total pooled assets and shares stays the same.
        assertEq(token.totalAssets(), totalPooledAssetsBefore);
        assertApproxEqAbs(
            token.convertToShares(token.totalAssets()),
            totalSharesBefore,
            1
        );

        // Ensure that the underlying balances were updated correctly.
        assertEq(
            underlyingToken.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.underlyingBalance
        );
        assertEq(
            underlyingToken.balanceOf(trader),
            traderBalancesBefore.underlyingBalance
        );

        // Ensure that the token balances were updated correctly.
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.shareBalance - shareProceeds,
            1
        );
        assertApproxEqAbs(
            token.balanceOf(trader),
            traderBalancesBefore.shareBalance + shareProceeds,
            1
        );
    }

    function verifyWithdrawalShares(
        address trader,
        uint256 baseProceeds,
        uint256 totalPooledAssetsBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view {
        // Allowances are set to 3 due to the expected number of conversions which can occur.
        // Ensure that the total pooled assets decreased by the amount paid out
        assertApproxEqAbs(
            token.totalAssets() + baseProceeds,
            totalPooledAssetsBefore,
            10
        );

        // Ensure that the underlying balances were updated correctly.
        // Token should be converted to underlyingToken and set to the trader
        assertApproxEqAbs(
            underlyingToken.balanceOf(trader),
            traderBalancesBefore.underlyingBalance + baseProceeds,
            10
        );
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.shareBalance -
                token.convertToShares(baseProceeds),
            10
        );
    }

    struct AccountBalances {
        uint256 shareBalance;
        uint256 underlyingBalance;
    }

    function getAccountBalances(
        address account
    ) internal view returns (AccountBalances memory) {
        return
            AccountBalances({
                shareBalance: token.balanceOf(account),
                underlyingBalance: underlyingToken.balanceOf(account)
            });
    }
}
