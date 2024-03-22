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
import { ETH } from "contracts/src/libraries/Constants.sol";

import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import "forge-std/console.sol";

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
        uint256 minTransactionAmount;
        uint256 positionDuration;
    }

    IntegrationConfig internal config;

    HyperdriveFactory factory;
    address deployerCoordinator;

    IHyperdrive.PoolDeployConfig internal poolConfig;

    bool internal immutable isBaseETH;

    constructor(IntegrationConfig storage _config) {
        config = _config;

        isBaseETH = config.baseToken == IERC20(ETH);
    }

    function setUp() public virtual override {
        super.setUp();

        // _beforeSetUp();

        // Fund Accounts
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        // accounts[2] = celine;
        for (uint256 i = 0; i < config.whaleAccounts.length; i++) {
            fundAccounts(
                address(hyperdrive),
                config.token,
                config.whaleAccounts[i],
                accounts
            );
        }
        vm.deal(alice, 100_000e18);
        vm.deal(bob, 100_000e18);
        // vm.deal(celine, 20_000e18);
        // console.logString("here1");
        // console.logUint(config.token.balanceOf(alice));

        // _afterSetup();

        deployFactory();
        deployerCoordinator = deployCoordinator();
        factory.addDeployerCoordinator(deployerCoordinator);

        deployTargets(
            // alice,
            bytes32(uint256(0xdeadbeef)),
            bytes32(uint256(0xdeadbabe)),
            5_000e18,
            false
        );

        // Start recording event logs.
        vm.recordLogs();
    }

    // function isBaseETH() internal returns (bool) {
    //     return asBase && config.baseToken;
    // }

    function deployTargets(
        // address deployer,
        bytes32 deploymentId,
        bytes32 deploymentSalt,
        uint256 contribution,
        bool asBase
    ) internal {
        vm.startPrank(alice);

        // console.logString("here2");
        // console.logUint(config.token.balanceOf(alice));

        factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            0,
            deploymentSalt
        );
        factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            1,
            deploymentSalt
        );
        factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            2,
            deploymentSalt
        );
        factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            3,
            deploymentSalt
        );
        factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            4,
            deploymentSalt
        );

        config.token.approve(deployerCoordinator, 100_000e18);
        //  asBase && isBaseETH ? contribution : 0

        {
            hyperdrive = factory.deployAndInitialize{
                value: asBase && isBaseETH ? contribution : 0
            }(
                deploymentId,
                deployerCoordinator,
                poolConfig,
                new bytes(0),
                contribution,
                FIXED_RATE,
                FIXED_RATE,
                IHyperdrive.Options({
                    asBase: asBase,
                    destination: alice,
                    extraData: new bytes(0)
                }),
                deploymentSalt
            );
        }
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

        poolConfig = IHyperdrive.PoolDeployConfig({
            baseToken: config.baseToken,
            linkerFactory: factory.linkerFactory(),
            linkerCodeHash: factory.linkerCodeHash(),
            minimumShareReserves: 1e15,
            minimumTransactionAmount: config.minTransactionAmount,
            positionDuration: config.positionDuration,
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
    }

    function getProtocolSharePrice()
        internal
        virtual
        returns (uint256, uint256, uint256);

    function deployCoordinator() internal virtual returns (address);

    function test__deployAndInitialize__asBase() external virtual {
        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 contribution = 5_000e18;
        (uint256 totalBase, uint256 totalShare, ) = getProtocolSharePrice();
        uint256 contributionShares = contribution.mulDivDown(
            totalShare,
            totalBase
        );

        deployTargets(
            bytes32(uint256(0xbeefbabe)),
            bytes32(uint256(0xdeadfade)),
            contribution,
            true
            // poolConfig
        );
        assertEq(address(alice).balance, aliceBalanceBefore - contribution);

        // Ensure that the decimals are set correctly.
        assertEq(hyperdrive.decimals(), 18);

        // Ensure that alice received the correct amount of LP tokens. He should
        // receive LP shares totaling the amount of shares that he contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            contribution.divDown(
                hyperdrive.getPoolConfig().initialVaultSharePrice
            ) - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
            config.shareTolerance
        );

        // Ensure that the share reserves and LP total supply are equal and correct.
        assertApproxEqAbs(
            hyperdrive.getPoolInfo().shareReserves,
            contributionShares,
            1
        );
        assertEq(
            hyperdrive.getPoolInfo().lpTotalSupply,
            hyperdrive.getPoolInfo().shareReserves -
                hyperdrive.getPoolConfig().minimumShareReserves
        );

        // Verify that the correct events were emitted.
        verifyFactoryEvents(
            deployerCoordinator,
            hyperdrive,
            alice,
            contribution,
            FIXED_RATE,
            true,
            hyperdrive.getPoolConfig().minimumShareReserves,
            new bytes(0),
            // NOTE: Tolerance since stETH uses mulDivDown for share calculations.
            config.shareTolerance
        );
    }

    function test__deployAndInitialize__asShares(uint) external {
        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 contribution = 5_000e18;
        (, , uint256 sharePrice) = getProtocolSharePrice();

        uint256 contributionShares = contribution.divDown(sharePrice);

        deployTargets(
            // alice,
            bytes32(uint256(0xbeefbabe)),
            bytes32(uint256(0xdeadfade)),
            contributionShares,
            false
        );

        assertEq(address(alice).balance, aliceBalanceBefore);

        // Ensure that the decimals are set correctly.
        assertEq(hyperdrive.decimals(), 18);

        // Ensure that alice received the correct amount of LP tokens. He should
        // receive LP shares totaling the amount of shares that he contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
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
            alice,
            contributionShares,
            FIXED_RATE,
            false,
            poolConfig.minimumShareReserves,
            new bytes(0),
            config.shareTolerance
        );
    }
}
