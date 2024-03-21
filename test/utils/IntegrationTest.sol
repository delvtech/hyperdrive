// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";

import { Lib } from "test/utils/Lib.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";

import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

abstract contract IntegrationTest is HyperdriveTest {
    using Lib for *;
    using FixedPointMath for uint256;

    uint256 internal constant FIXED_RATE = 0.05e18;
    address internal ETH_WHALE = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    struct IntegrationConfig {
        address[] whaleAccounts;
        IERC20 token;
        IERC20 baseToken;
        uint256 shareTolerance;
    }

    IntegrationConfig internal config;

    HyperdriveFactory factory;
    address deployerCoordinator;

    constructor(IntegrationConfig storage _config) {
        config = _config;
    }

    function setUp() public virtual override {
        super.setUp();

        // _beforeSetUp();

        // Fund Accounts
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = celine;
        for (uint256 i = 0; i < config.whaleAccounts.length; i++) {
            fundAccounts(
                address(hyperdrive),
                config.token,
                config.whaleAccounts[i],
                accounts
            );
        }
        vm.deal(alice, 20_000e18);
        vm.deal(bob, 20_000e18);
        vm.deal(celine, 20_000e18);

        // _afterSetup();

        deployFactory();
        deployerCoordinator = deployCoordinator();
        factory.addDeployerCoordinator(deployerCoordinator);

        deployTargets();

        // Start recording event logs.
        vm.recordLogs();
    }

    function deployTargets() internal {
        IHyperdrive.PoolDeployConfig memory poolConfig = IHyperdrive
            .PoolDeployConfig({
                baseToken: config.baseToken,
                linkerFactory: factory.linkerFactory(),
                linkerCodeHash: factory.linkerCodeHash(),
                minimumShareReserves: 1e15,
                minimumTransactionAmount: 1e16,
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

        deployTargets(
            factory,
            alice,
            bytes32(uint256(0xdeadbeef)),
            bytes32(uint256(0xdeadbabe)),
            10_000e18,
            poolConfig
        );
    }

    function deployTargets(
        HyperdriveFactory _factory,
        address deployer,
        bytes32 deploymentId,
        bytes32 deploymentSalt,
        uint256 contribution,
        IHyperdrive.PoolDeployConfig memory poolConfig
    ) public {
        vm.startPrank(deployer);

        _factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            0,
            deploymentSalt
        );
        _factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            1,
            deploymentSalt
        );
        _factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            2,
            deploymentSalt
        );
        _factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            3,
            deploymentSalt
        );
        _factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            4,
            deploymentSalt
        );

        config.token.approve(deployerCoordinator, contribution);
        hyperdrive = _factory.deployAndInitialize(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            contribution,
            FIXED_RATE,
            FIXED_RATE,
            IHyperdrive.Options({
                asBase: false,
                destination: deployer,
                extraData: new bytes(0)
            }),
            deploymentSalt
        );
    }

    function deployFactory() internal {
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
    }

    function getProtocolSharePrice() internal virtual returns (uint256);

    function deployCoordinator() internal virtual returns (address);

    function test__deployAndInitialize__asShares() external {
        IHyperdrive.PoolDeployConfig memory poolConfig = IHyperdrive
            .PoolDeployConfig({
                baseToken: config.baseToken,
                linkerFactory: factory.linkerFactory(),
                linkerCodeHash: factory.linkerCodeHash(),
                minimumShareReserves: 1e15,
                minimumTransactionAmount: 1e16,
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

        uint256 bobBalanceBefore = address(bob).balance;
        uint256 contribution = 5_000e18;
        uint256 contributionShares = contribution.divDown(
            getProtocolSharePrice()
        );

        deployTargets(
            factory,
            bob,
            bytes32(uint256(0xbeefbabe)),
            bytes32(uint256(0xdeadfade)),
            contributionShares,
            poolConfig
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
            contribution.divDown(
                hyperdrive.getPoolConfig().initialVaultSharePrice
            ) - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
            config.shareTolerance
        );

        // Ensure that the share reserves and LP total supply are equal and correct.
        assertEq(hyperdrive.getPoolInfo().shareReserves, contributionShares);
        assertEq(
            hyperdrive.getPoolInfo().lpTotalSupply,
            hyperdrive.getPoolInfo().shareReserves -
                poolConfig.minimumShareReserves
        );

        // Verify that the correct events were emitted.
        verifyFactoryEvents(
            deployerCoordinator,
            hyperdrive,
            bob,
            contributionShares,
            FIXED_RATE,
            false,
            poolConfig.minimumShareReserves,
            new bytes(0),
            config.shareTolerance
        );
    }
}
