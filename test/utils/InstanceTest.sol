// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

/// @author DELV
/// @title InstanceTest
/// @notice The base contract for the instance testing suite.
/// @dev A testing suite that provides a foundation to setup, deploy, and
/// test common cases for Hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract InstanceTest is HyperdriveTest {
    using Lib for *;
    using FixedPointMath for uint256;

    // Fixed rate used to configure market.
    uint256 internal constant FIXED_RATE = 0.05e18;

    // ETH whale account.
    address internal ETH_WHALE = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    /// @dev Configuration for the Instance testing suite.
    struct InstanceTestConfig {
        address[] whaleAccounts;
        IERC20 token;
        IERC20 baseToken;
        uint256 shareTolerance;
        uint256 minTransactionAmount;
        uint256 positionDuration;
        bool enableBaseDeposits;
    }

    InstanceTestConfig internal config;
    IHyperdrive.PoolDeployConfig internal poolConfig;
    HyperdriveFactory factory;
    address deployerCoordinator;
    bool internal immutable isBaseETH;

    /// @dev Constructor for the Instance testing suite.
    /// @param _config The Instance configuration.
    constructor(InstanceTestConfig storage _config) {
        config = _config;
        isBaseETH = config.baseToken == IERC20(ETH);
    }

    /// @notice Forge setup function.
    /// @dev Inherits from HyperdriveTest and deploys the
    ///      Hyperdrive factory, deployer coordinator, and targets.
    function setUp() public virtual override {
        super.setUp();

        // Fund accounts with ETH and token from whales.
        vm.deal(alice, 100_000e18);
        vm.deal(bob, 100_000e18);
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        for (uint256 i = 0; i < config.whaleAccounts.length; i++) {
            fundAccounts(
                address(hyperdrive),
                config.token,
                config.whaleAccounts[i],
                accounts
            );
        }

        // Deploy the Hyperdrive Factory contract.
        deployFactory();

        // Set the deployer coordinator address and add to the factory.
        deployerCoordinator = deployCoordinator();
        factory.addDeployerCoordinator(deployerCoordinator);

        // Deploy all Hyperdrive targets using  deployer coordinator contract.
        deployTargets(
            bytes32(uint256(0xdeadbeef)), // Deployment Id
            bytes32(uint256(0xdeadbabe)), // Deployment Salt
            5_000e18, // Contribution
            false // asBase
        );

        // Start recording event logs.
        vm.recordLogs();
    }

    /// @dev Deploys all Hyperdrive contracts using the
    ///      deployer coordinator contract.
    /// @param deploymentId The deployment id.
    /// @param deploymentSalt The deployment salt for create2.
    /// @param contribution The amount to initialize the market.
    /// @param asBase Initialize the market with base token.
    function deployTargets(
        bytes32 deploymentId,
        bytes32 deploymentSalt,
        uint256 contribution,
        bool asBase
    ) internal {
        // Alice is the default deployer.
        vm.startPrank(alice);

        // Deploy Hyperdrive target contracts.
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

        // Alice gives approval to the deployer coordinator to fund the market.
        config.token.approve(deployerCoordinator, 100_000e18);

        // We expect the deployAndInitialize to fail with an
        // UnSupported token error if depositing as base is not supported.
        // If the base token is ETH we expect a NotPayable error.
        if (!config.enableBaseDeposits && asBase) {
            vm.expectRevert(
                isBaseETH
                    ? IHyperdrive.NotPayable.selector
                    : IHyperdrive.UnsupportedToken.selector
            );
        }

        // Deploy and initialize the market. If the base token is ETH we pass the
        // contribution through the call.
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

    /// @dev Deploys the Hyperdrive Factory contract and
    ///      sets the default pool configuration.
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

    /// @dev A virtual function that exposes important state
    ///      about the underlying protocol and token. Not all values
    ///      will be used depending on the instance.
    /// @param baseSupply Amount of base tokens in circulation.
    /// @param shareSupply Amount of share tokens in circulation.
    /// @param sharePrice Price of of one share in terms of base.
    function getProtocolSharePrice()
        internal
        virtual
        returns (uint256 baseSupply, uint256 shareSupply, uint256 sharePrice);

    /// @dev A virtual function that defines the deployer coordinator
    ///      contract that will be used to deploy all the instance targets.
    function deployCoordinator() internal virtual returns (address);

    /// @dev Test to verify a market can be deployed and initialized funded by the
    ///      base token. Is expected to revert when base deposits are not supported.
    function test__deployAndInitialize__asBase() external virtual {
        uint256 aliceBalanceBefore = address(alice).balance;

        // Contribution in terms of base.
        uint256 contribution = 5_000e18;

        // Get protocol state information used for calculating correct LP shares.
        (uint256 totalBase, uint256 totalShare, ) = getProtocolSharePrice();

        // Contribution in terms of shares.
        uint256 contributionShares = contribution.mulDivDown(
            totalShare,
            totalBase
        );

        // Deploy all Hyperdrive targets using deployer coordinator contract.
        // This function reverts if base deposits are disabled.
        deployTargets(
            bytes32(uint256(0xbeefbabe)), // Deployment Id
            bytes32(uint256(0xdeadfade)), // Deployment Salt
            contribution, // Contribution
            true // asBase
        );

        // If base deposits are enabled we verify some assertions.
        if (config.enableBaseDeposits && isBaseETH) {
            // If the base token is ETH we assert the ETH balance is correct.
            if (isBaseETH) {
                assertEq(
                    address(alice).balance,
                    aliceBalanceBefore - contribution
                );
            }

            // Ensure that the decimals are set correctly.
            assertEq(hyperdrive.decimals(), 18);

            // Ensure that Alice received the correct amount of LP tokens. She should
            // receive LP shares totaling the amount of shares that he contributed
            // minus the shares set aside for the minimum share reserves and the
            // zero address's initial LP contribution.
            assertApproxEqAbs(
                hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
                contribution.divDown(
                    hyperdrive.getPoolConfig().initialVaultSharePrice
                ) - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
                config.shareTolerance // Custom share tolerance per instance.
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
                config.shareTolerance
            );
        }
    }

    /// @dev Test to verify a market can be deployed and initialized funded
    ///      by the share token.
    function test__deployAndInitialize__asShares() external {
        uint256 aliceBalanceBefore = address(alice).balance;

        // Contribution in terms of base.
        uint256 contribution = 5_000e18;

        // Get protocol state information used for calculating correct LP shares.
        (, , uint256 sharePrice) = getProtocolSharePrice();

        // Contribution in terms of shares.
        uint256 contributionShares = contribution.divDown(sharePrice);

        // Deploy all Hyperdrive targets using deployer coordinator contract.
        deployTargets(
            bytes32(uint256(0xbeefbabe)), // Deployment Id
            bytes32(uint256(0xdeadfade)), // Deployment Salt
            contributionShares, // Contribution
            false // asBase
        );

        // Ensure Alice's ETH balance remains the same.
        assertEq(address(alice).balance, aliceBalanceBefore);

        // Ensure that the decimals are set correctly.
        assertEq(hyperdrive.decimals(), 18);

        // Ensure that Alice received the correct amount of LP tokens. She should
        // receive LP shares totaling the amount of shares that he contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            contribution.divDown(
                hyperdrive.getPoolConfig().initialVaultSharePrice
            ) - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
            config.shareTolerance // Custom share tolerance per instance.
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
