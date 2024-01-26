// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { Script } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { MultiRolesAuthority } from "solmate/auth/authorities/MultiRolesAuthority.sol";
import { ERC4626HyperdriveCoreDeployer } from "contracts/src/deployers/erc4626/ERC4626HyperdriveCoreDeployer.sol";
import { ERC4626HyperdriveDeployerCoordinator } from "contracts/src/deployers/erc4626/ERC4626HyperdriveDeployerCoordinator.sol";
import { ERC4626Target0Deployer } from "contracts/src/deployers/erc4626/ERC4626Target0Deployer.sol";
import { ERC4626Target1Deployer } from "contracts/src/deployers/erc4626/ERC4626Target1Deployer.sol";
import { ERC4626Target2Deployer } from "contracts/src/deployers/erc4626/ERC4626Target2Deployer.sol";
import { ERC4626Target3Deployer } from "contracts/src/deployers/erc4626/ERC4626Target3Deployer.sol";
import { StETHHyperdriveCoreDeployer } from "contracts/src/deployers/steth/StETHHyperdriveCoreDeployer.sol";
import { StETHHyperdriveDeployerCoordinator } from "contracts/src/deployers/steth/StETHHyperdriveDeployerCoordinator.sol";
import { StETHTarget0Deployer } from "contracts/src/deployers/steth/StETHTarget0Deployer.sol";
import { StETHTarget1Deployer } from "contracts/src/deployers/steth/StETHTarget1Deployer.sol";
import { StETHTarget2Deployer } from "contracts/src/deployers/steth/StETHTarget2Deployer.sol";
import { StETHTarget3Deployer } from "contracts/src/deployers/steth/StETHTarget3Deployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";
import { MockHyperdriveMath } from "contracts/test/MockHyperdriveMath.sol";
import { MockLido } from "contracts/test/MockLido.sol";
import { ETH } from "test/utils/Constants.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

/// @author DELV
/// @title DevnetMigration
/// @notice This script deploys a mock ERC4626 yield source and a Hyperdrive
///         factory on top of it. For convenience, it also deploys a Hyperdrive
///         pool with a 1 week duration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract DevnetMigration is Script {
    using stdJson for string;
    using HyperdriveUtils for *;

    function setUp() external {}

    struct Config {
        // admin configuration
        address admin;
        bool isCompetitionMode;
        // base token configuration
        string baseTokenName;
        string baseTokenSymbol;
        uint8 baseTokenDecimals;
        // vault configuration
        string vaultName;
        string vaultSymbol;
        uint256 vaultStartingRate;
        // lido configuration
        uint256 lidoStartingRate;
        // factory configuration
        uint256 factoryCheckpointDurationResolution;
        uint256 factoryMinCheckpointDuration;
        uint256 factoryMaxCheckpointDuration;
        uint256 factoryMinPositionDuration;
        uint256 factoryMaxPositionDuration;
        uint256 factoryMinCurveFee;
        uint256 factoryMinFlatFee;
        uint256 factoryMinGovernanceLPFee;
        uint256 factoryMinGovernanceZombieFee;
        uint256 factoryMaxCurveFee;
        uint256 factoryMaxFlatFee;
        uint256 factoryMaxGovernanceLPFee;
        uint256 factoryMaxGovernanceZombieFee;
        // erc4626 hyperdrive configuration
        uint256 erc4626HyperdriveContribution;
        uint256 erc4626HyperdriveFixedRate;
        uint256 erc4626HyperdriveMinimumShareReserves;
        uint256 erc4626HyperdriveMinimumTransactionAmount;
        uint256 erc4626HyperdrivePositionDuration;
        uint256 erc4626HyperdriveCheckpointDuration;
        uint256 erc4626HyperdriveTimeStretchApr;
        uint256 erc4626HyperdriveCurveFee;
        uint256 erc4626HyperdriveFlatFee;
        uint256 erc4626HyperdriveGovernanceLPFee;
        uint256 erc4626HyperdriveGovernanceZombieFee;
        // steth hyperdrive configuration
        uint256 stethHyperdriveContribution;
        uint256 stethHyperdriveFixedRate;
        uint256 stethHyperdriveMinimumShareReserves;
        uint256 stethHyperdriveMinimumTransactionAmount;
        uint256 stethHyperdrivePositionDuration;
        uint256 stethHyperdriveCheckpointDuration;
        uint256 stethHyperdriveTimeStretchApr;
        uint256 stethHyperdriveCurveFee;
        uint256 stethHyperdriveFlatFee;
        uint256 stethHyperdriveGovernanceLPFee;
        uint256 stethHyperdriveGovernanceZombieFee;
    }

    function run() external {
        vm.startBroadcast();

        // Get the migration configuration from the environment and the defaults.
        uint256 baseTokenDecimals = vm.envOr(
            "BASE_TOKEN_DECIMALS",
            uint256(18)
        );
        if (baseTokenDecimals > type(uint8).max) {
            revert("BASE_TOKEN_DECIMALS exceeds uint8");
        }
        Config memory config = Config({
            // admin configuration
            admin: vm.envOr("ADMIN", msg.sender),
            isCompetitionMode: vm.envOr("IS_COMPETITION_MODE", false),
            // base token configuration
            baseTokenName: vm.envOr("BASE_TOKEN_NAME", string("Base")),
            baseTokenSymbol: vm.envOr("BASE_TOKEN_SYMBOL", string("BASE")),
            baseTokenDecimals: uint8(baseTokenDecimals),
            // vault configuration
            vaultName: vm.envOr("VAULT_NAME", string("Delvnet Yield Source")),
            vaultSymbol: vm.envOr("VAULT_SYMBOL", string("DELV")),
            vaultStartingRate: vm.envOr(
                "VAULT_STARTING_RATE",
                uint256(0.05e18)
            ),
            // lido configuration
            lidoStartingRate: vm.envOr("LIDO_STARTING_RATE", uint256(0.035e18)),
            // factory configuration
            factoryCheckpointDurationResolution: vm.envOr(
                "FACTORY_CHECKPOINT_DURATION_RESOLUTION",
                uint256(1 hours)
            ),
            factoryMinCheckpointDuration: vm.envOr(
                "FACTORY_MIN_CHECKPOINT_DURATION",
                uint256(1 hours)
            ),
            factoryMaxCheckpointDuration: vm.envOr(
                "FACTORY_MAX_CHECKPOINT_DURATION",
                uint256(1 days)
            ),
            factoryMinPositionDuration: vm.envOr(
                "FACTORY_MIN_POSITION_DURATION",
                uint256(7 days)
            ),
            factoryMaxPositionDuration: vm.envOr(
                "FACTORY_MAX_POSITION_DURATION",
                uint256(10 * 365 days)
            ),
            factoryMinCurveFee: vm.envOr(
                "FACTORY_MIN_CURVE_FEE",
                uint256(0.001e18)
            ),
            factoryMinFlatFee: vm.envOr(
                "FACTORY_MIN_FLAT_FEE",
                uint256(0.0001e18)
            ),
            factoryMinGovernanceLPFee: vm.envOr(
                "FACTORY_MIN_GOVERNANCE_LP_FEE",
                uint256(0.15e18)
            ),
            factoryMinGovernanceZombieFee: vm.envOr(
                "FACTORY_MIN_GOVERNANCE_ZOMBIE_FEE",
                uint256(0.03e18)
            ),
            factoryMaxCurveFee: vm.envOr(
                "FACTORY_MAX_CURVE_FEE",
                uint256(0.1e18)
            ),
            factoryMaxFlatFee: vm.envOr(
                "FACTORY_MAX_FLAT_FEE",
                uint256(0.001e18)
            ),
            factoryMaxGovernanceLPFee: vm.envOr(
                "FACTORY_MAX_GOVERNANCE_LP_FEE",
                uint256(0.15e18)
            ),
            factoryMaxGovernanceZombieFee: vm.envOr(
                "FACTORY_MAX_GOVERNANCE_ZOMBIE_FEE",
                uint256(0.03e18)
            ),
            // erc4626 hyperdrive configuration
            erc4626HyperdriveContribution: vm.envOr(
                "ERC4626_HYPERDRIVE_CONTRIBUTION",
                uint256(100_000_000e18)
            ),
            erc4626HyperdriveFixedRate: vm.envOr(
                "ERC4626_HYPERDRIVE_FIXED_RATE",
                uint256(0.05e18)
            ),
            erc4626HyperdriveMinimumShareReserves: vm.envOr(
                "ERC4626_HYPERDRIVE_MINIMUM_SHARE_RESERVES",
                uint256(10e18)
            ),
            erc4626HyperdriveMinimumTransactionAmount: vm.envOr(
                "ERC4626_HYPERDRIVE_MINIMUM_TRANSACTION_AMOUNT",
                uint256(0.001e18)
            ),
            erc4626HyperdrivePositionDuration: vm.envOr(
                "ERC4626_HYPERDRIVE_POSITION_DURATION",
                uint256(1 weeks)
            ),
            erc4626HyperdriveCheckpointDuration: vm.envOr(
                "ERC4626_HYPERDRIVE_CHECKPOINT_DURATION",
                uint256(1 hours)
            ),
            erc4626HyperdriveTimeStretchApr: vm.envOr(
                "ERC4626_HYPERDRIVE_TIME_STRETCH_APR",
                uint256(0.05e18)
            ),
            erc4626HyperdriveCurveFee: vm.envOr(
                "ERC4626_HYPERDRIVE_CURVE_FEE",
                uint256(0.01e18)
            ),
            erc4626HyperdriveFlatFee: vm.envOr(
                "ERC4626_HYPERDRIVE_FLAT_FEE",
                uint256(0.0005e18)
            ),
            erc4626HyperdriveGovernanceLPFee: vm.envOr(
                "ERC4626_HYPERDRIVE_GOVERNANCE_LP_FEE",
                uint256(0.15e18)
            ),
            erc4626HyperdriveGovernanceZombieFee: vm.envOr(
                "ERC4626_HYPERDRIVE_GOVERNANCE_ZOMBIE_FEE",
                uint256(0.03e18)
            ),
            // steth hyperdrive configuration
            stethHyperdriveContribution: vm.envOr(
                "STETH_HYPERDRIVE_CONTRIBUTION",
                uint256(50_000e18)
            ),
            stethHyperdriveFixedRate: vm.envOr(
                "STETH_HYPERDRIVE_FIXED_RATE",
                uint256(0.035e18)
            ),
            stethHyperdriveMinimumShareReserves: vm.envOr(
                "STETH_HYPERDRIVE_MINIMUM_SHARE_RESERVES",
                uint256(1e15)
            ),
            stethHyperdriveMinimumTransactionAmount: vm.envOr(
                "STETH_HYPERDRIVE_MINIMUM_TRANSACTION_AMOUNT",
                uint256(0.001e18)
            ),
            stethHyperdrivePositionDuration: vm.envOr(
                "STETH_HYPERDRIVE_POSITION_DURATION",
                uint256(1 weeks)
            ),
            stethHyperdriveCheckpointDuration: vm.envOr(
                "STETH_HYPERDRIVE_CHECKPOINT_DURATION",
                uint256(1 hours)
            ),
            stethHyperdriveTimeStretchApr: vm.envOr(
                "STETH_HYPERDRIVE_TIME_STRETCH_APR",
                uint256(0.035e18)
            ),
            stethHyperdriveCurveFee: vm.envOr(
                "STETH_HYPERDRIVE_CURVE_FEE",
                uint256(0.01e18)
            ),
            stethHyperdriveFlatFee: vm.envOr(
                "STETH_HYPERDRIVE_FLAT_FEE",
                uint256(0.0005e18)
            ),
            stethHyperdriveGovernanceLPFee: vm.envOr(
                "STETH_HYPERDRIVE_GOVERNANCE_LP_FEE",
                uint256(0.15e18)
            ),
            stethHyperdriveGovernanceZombieFee: vm.envOr(
                "STETH_HYPERDRIVE_GOVERNANCE_ZOMBIE_FEE",
                uint256(0.03e18)
            )
        });

        // Deploy the base token and the vault.
        ERC20Mintable baseToken = new ERC20Mintable(
            config.baseTokenName,
            config.baseTokenSymbol,
            config.baseTokenDecimals,
            msg.sender,
            config.isCompetitionMode
        );
        MockERC4626 pool = new MockERC4626(
            baseToken,
            config.vaultName,
            config.vaultSymbol,
            config.vaultStartingRate,
            msg.sender,
            config.isCompetitionMode
        );
        if (config.isCompetitionMode) {
            baseToken.setUserRole(address(pool), 1, true);
            baseToken.setRoleCapability(
                1,
                bytes4(keccak256("mint(uint256)")),
                true
            );
            baseToken.setRoleCapability(
                1,
                bytes4(keccak256("burn(uint256)")),
                true
            );
        }

        // Deploy the mock Lido system. We fund Lido with 1 eth to start to
        // avoid reverts when we initialize the pool.
        MockLido lido = new MockLido(
            config.lidoStartingRate,
            msg.sender,
            config.isCompetitionMode
        );
        vm.deal(msg.sender, 1 ether);
        lido.submit{ value: 1 ether }(address(0));

        // Deploy the Hyperdrive factory.
        HyperdriveFactory factory;
        {
            address[] memory defaultPausers = new address[](1);
            defaultPausers[0] = config.admin;
            ForwarderFactory forwarderFactory = new ForwarderFactory();
            HyperdriveFactory.FactoryConfig
                memory factoryConfig = HyperdriveFactory.FactoryConfig({
                    governance: msg.sender,
                    hyperdriveGovernance: config.admin,
                    feeCollector: config.admin,
                    defaultPausers: defaultPausers,
                    checkpointDurationResolution: config
                        .factoryCheckpointDurationResolution,
                    minCheckpointDuration: config.factoryMinCheckpointDuration,
                    maxCheckpointDuration: config.factoryMaxCheckpointDuration,
                    minPositionDuration: config.factoryMinPositionDuration,
                    maxPositionDuration: config.factoryMaxPositionDuration,
                    minFees: IHyperdrive.Fees({
                        curve: config.factoryMinCurveFee,
                        flat: config.factoryMinFlatFee,
                        governanceLP: config.factoryMinGovernanceLPFee,
                        governanceZombie: config.factoryMinGovernanceZombieFee
                    }),
                    maxFees: IHyperdrive.Fees({
                        curve: config.factoryMaxCurveFee,
                        flat: config.factoryMaxFlatFee,
                        governanceLP: config.factoryMaxGovernanceLPFee,
                        governanceZombie: config.factoryMaxGovernanceZombieFee
                    }),
                    linkerFactory: address(forwarderFactory),
                    linkerCodeHash: forwarderFactory.ERC20LINK_HASH()
                });
            factory = new HyperdriveFactory(factoryConfig);
        }

        // Deploy the ERC4626Hyperdrive deployers and add them to the factory.
        address erc4626DeployerCoordinator = address(
            new ERC4626HyperdriveDeployerCoordinator(
                address(new ERC4626HyperdriveCoreDeployer()),
                address(new ERC4626Target0Deployer()),
                address(new ERC4626Target1Deployer()),
                address(new ERC4626Target2Deployer()),
                address(new ERC4626Target3Deployer())
            )
        );
        factory.addDeployerCoordinator(erc4626DeployerCoordinator);

        // Deploy and initialize an initial ERC4626Hyperdrive instance.
        IHyperdrive erc4626Hyperdrive;
        {
            uint256 contribution = config.erc4626HyperdriveContribution;
            uint256 fixedRate = config.erc4626HyperdriveFixedRate;
            baseToken.mint(msg.sender, contribution);
            baseToken.approve(address(factory), contribution);
            IHyperdrive.PoolDeployConfig memory poolConfig = IHyperdrive
                .PoolDeployConfig({
                    baseToken: IERC20(address(baseToken)),
                    linkerFactory: address(0),
                    linkerCodeHash: bytes32(0),
                    minimumShareReserves: config
                        .erc4626HyperdriveMinimumShareReserves,
                    minimumTransactionAmount: config
                        .erc4626HyperdriveMinimumTransactionAmount,
                    positionDuration: config.erc4626HyperdrivePositionDuration,
                    checkpointDuration: config
                        .erc4626HyperdriveCheckpointDuration,
                    timeStretch: config
                        .erc4626HyperdriveTimeStretchApr
                        .calculateTimeStretch(
                            config.erc4626HyperdrivePositionDuration
                        ),
                    governance: address(0),
                    feeCollector: address(0),
                    fees: IHyperdrive.Fees({
                        curve: config.erc4626HyperdriveCurveFee,
                        flat: config.erc4626HyperdriveFlatFee,
                        governanceLP: config.erc4626HyperdriveGovernanceLPFee,
                        governanceZombie: config
                            .erc4626HyperdriveGovernanceZombieFee
                    })
                });
            factory.deployTarget(
                bytes32(uint256(0xdeadbeef)),
                erc4626DeployerCoordinator,
                poolConfig,
                abi.encode(address(pool), new address[](0)),
                0,
                bytes32(uint256(0xdeadbabe))
            );
            factory.deployTarget(
                bytes32(uint256(0xdeadbeef)),
                erc4626DeployerCoordinator,
                poolConfig,
                abi.encode(address(pool), new address[](0)),
                1,
                bytes32(uint256(0xdeadbabe))
            );
            factory.deployTarget(
                bytes32(uint256(0xdeadbeef)),
                erc4626DeployerCoordinator,
                poolConfig,
                abi.encode(address(pool), new address[](0)),
                2,
                bytes32(uint256(0xdeadbabe))
            );
            factory.deployTarget(
                bytes32(uint256(0xdeadbeef)),
                erc4626DeployerCoordinator,
                poolConfig,
                abi.encode(address(pool), new address[](0)),
                3,
                bytes32(uint256(0xdeadbabe))
            );
            erc4626Hyperdrive = factory.deployAndInitialize(
                bytes32(uint256(0xdeadbeef)),
                erc4626DeployerCoordinator,
                poolConfig,
                abi.encode(address(pool), new address[](0)),
                contribution,
                fixedRate,
                new bytes(0),
                bytes32(uint256(0xdeadbabe))
            );
        }

        // Deploy the StETHHyperdrive deployers and add them to the factory.
        address stethDeployerCoordinator = address(
            new StETHHyperdriveDeployerCoordinator(
                address(new StETHHyperdriveCoreDeployer(ILido(address(lido)))),
                address(new StETHTarget0Deployer(ILido(address(lido)))),
                address(new StETHTarget1Deployer(ILido(address(lido)))),
                address(new StETHTarget2Deployer(ILido(address(lido)))),
                address(new StETHTarget3Deployer(ILido(address(lido)))),
                ILido(address(lido))
            )
        );
        factory.addDeployerCoordinator(stethDeployerCoordinator);

        // Deploy and initialize an initial StETHHyperdrive instance.
        IHyperdrive stethHyperdrive;
        {
            uint256 contribution = config.stethHyperdriveContribution;
            uint256 fixedRate = config.stethHyperdriveFixedRate;
            vm.deal(msg.sender, contribution);
            IHyperdrive.PoolDeployConfig memory poolConfig = IHyperdrive
                .PoolDeployConfig({
                    baseToken: IERC20(address(ETH)),
                    linkerFactory: address(0),
                    linkerCodeHash: bytes32(0),
                    minimumShareReserves: config
                        .stethHyperdriveMinimumShareReserves,
                    minimumTransactionAmount: config
                        .stethHyperdriveMinimumTransactionAmount,
                    positionDuration: config.stethHyperdrivePositionDuration,
                    checkpointDuration: config
                        .stethHyperdriveCheckpointDuration,
                    timeStretch: config
                        .stethHyperdriveTimeStretchApr
                        .calculateTimeStretch(
                            config.stethHyperdrivePositionDuration
                        ),
                    governance: address(0),
                    feeCollector: address(0),
                    fees: IHyperdrive.Fees({
                        curve: config.stethHyperdriveCurveFee,
                        flat: config.stethHyperdriveFlatFee,
                        governanceLP: config.stethHyperdriveGovernanceLPFee,
                        governanceZombie: config
                            .stethHyperdriveGovernanceZombieFee
                    })
                });
            factory.deployTarget(
                bytes32(uint256(0xdeadbeef)),
                stethDeployerCoordinator,
                poolConfig,
                abi.encode(address(pool), new address[](0)),
                0,
                bytes32(uint256(0xdeadbabe))
            );
            factory.deployTarget(
                bytes32(uint256(0xdeadbeef)),
                stethDeployerCoordinator,
                poolConfig,
                abi.encode(address(pool), new address[](0)),
                1,
                bytes32(uint256(0xdeadbabe))
            );
            factory.deployTarget(
                bytes32(uint256(0xdeadbeef)),
                stethDeployerCoordinator,
                poolConfig,
                abi.encode(address(pool), new address[](0)),
                2,
                bytes32(uint256(0xdeadbabe))
            );
            factory.deployTarget(
                bytes32(uint256(0xdeadbeef)),
                stethDeployerCoordinator,
                poolConfig,
                abi.encode(address(pool), new address[](0)),
                3,
                bytes32(uint256(0xdeadbabe))
            );
            stethHyperdrive = factory.deployAndInitialize{
                value: contribution
            }(
                bytes32(uint256(0xdeadbeef)),
                stethDeployerCoordinator,
                poolConfig,
                new bytes(0),
                contribution,
                fixedRate,
                new bytes(0),
                bytes32(uint256(0xdeadbabe))
            );
        }

        // Transfer ownership of the base token, factory, vault, and lido to the
        // admin address now that we're done minting tokens and updating the
        // configuration.
        baseToken.transferOwnership(config.admin);
        factory.updateGovernance(config.admin);
        pool.transferOwnership(config.admin);
        lido.transferOwnership(config.admin);

        vm.stopBroadcast();

        // Writes the addresses to a file.
        string memory result = "result";
        vm.serializeAddress(result, "baseToken", address(baseToken));
        vm.serializeAddress(result, "hyperdriveFactory", address(factory));
        vm.serializeAddress(
            result,
            "erc4626Hyperdrive",
            address(erc4626Hyperdrive)
        );
        vm.serializeAddress(
            result,
            "stethHyperdrive",
            address(stethHyperdrive)
        );
        result.write("./artifacts/script_addresses.json");
    }
}
