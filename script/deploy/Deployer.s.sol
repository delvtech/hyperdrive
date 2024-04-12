// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { console2 as console } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { ERC4626HyperdriveDeployerCoordinator } from "contracts/src/deployers/erc4626/ERC4626HyperdriveDeployerCoordinator.sol";
import { ERC4626HyperdriveCoreDeployer } from "contracts/src/deployers/erc4626/ERC4626HyperdriveCoreDeployer.sol";
import { ERC4626Target0Deployer } from "contracts/src/deployers/erc4626/ERC4626Target0Deployer.sol";
import { ERC4626Target1Deployer } from "contracts/src/deployers/erc4626/ERC4626Target1Deployer.sol";
import { ERC4626Target2Deployer } from "contracts/src/deployers/erc4626/ERC4626Target2Deployer.sol";
import { ERC4626Target3Deployer } from "contracts/src/deployers/erc4626/ERC4626Target3Deployer.sol";
import { ERC4626Target4Deployer } from "contracts/src/deployers/erc4626/ERC4626Target4Deployer.sol";
import { StETHHyperdriveDeployerCoordinator } from "contracts/src/deployers/steth/StETHHyperdriveDeployerCoordinator.sol";
import { StETHHyperdriveCoreDeployer } from "contracts/src/deployers/steth/StETHHyperdriveCoreDeployer.sol";
import { StETHTarget0Deployer } from "contracts/src/deployers/steth/StETHTarget0Deployer.sol";
import { StETHTarget1Deployer } from "contracts/src/deployers/steth/StETHTarget1Deployer.sol";
import { StETHTarget2Deployer } from "contracts/src/deployers/steth/StETHTarget2Deployer.sol";
import { StETHTarget3Deployer } from "contracts/src/deployers/steth/StETHTarget3Deployer.sol";
import { StETHTarget4Deployer } from "contracts/src/deployers/steth/StETHTarget4Deployer.sol";
import { EzETHHyperdriveDeployerCoordinator } from "contracts/src/deployers/ezeth/EzETHHyperdriveDeployerCoordinator.sol";
import { EzETHHyperdriveCoreDeployer } from "contracts/src/deployers/ezeth/EzETHHyperdriveCoreDeployer.sol";
import { EzETHTarget0Deployer } from "contracts/src/deployers/ezeth/EzETHTarget0Deployer.sol";
import { EzETHTarget1Deployer } from "contracts/src/deployers/ezeth/EzETHTarget1Deployer.sol";
import { EzETHTarget2Deployer } from "contracts/src/deployers/ezeth/EzETHTarget2Deployer.sol";
import { EzETHTarget3Deployer } from "contracts/src/deployers/ezeth/EzETHTarget3Deployer.sol";
import { EzETHTarget4Deployer } from "contracts/src/deployers/ezeth/EzETHTarget4Deployer.sol";
import { LsETHHyperdriveDeployerCoordinator } from "contracts/src/deployers/lseth/LsETHHyperdriveDeployerCoordinator.sol";
import { LsETHHyperdriveCoreDeployer } from "contracts/src/deployers/lseth/LsETHHyperdriveCoreDeployer.sol";
import { LsETHTarget0Deployer } from "contracts/src/deployers/lseth/LsETHTarget0Deployer.sol";
import { LsETHTarget1Deployer } from "contracts/src/deployers/lseth/LsETHTarget1Deployer.sol";
import { LsETHTarget2Deployer } from "contracts/src/deployers/lseth/LsETHTarget2Deployer.sol";
import { LsETHTarget3Deployer } from "contracts/src/deployers/lseth/LsETHTarget3Deployer.sol";
import { LsETHTarget4Deployer } from "contracts/src/deployers/lseth/LsETHTarget4Deployer.sol";

import { RETHHyperdriveDeployerCoordinator } from "contracts/src/deployers/reth/RETHHyperdriveDeployerCoordinator.sol";
import { RETHHyperdriveCoreDeployer } from "contracts/src/deployers/reth/RETHHyperdriveCoreDeployer.sol";
import { RETHTarget0Deployer } from "contracts/src/deployers/reth/RETHTarget0Deployer.sol";
import { RETHTarget1Deployer } from "contracts/src/deployers/reth/RETHTarget1Deployer.sol";
import { RETHTarget2Deployer } from "contracts/src/deployers/reth/RETHTarget2Deployer.sol";
import { RETHTarget3Deployer } from "contracts/src/deployers/reth/RETHTarget3Deployer.sol";
import { RETHTarget4Deployer } from "contracts/src/deployers/reth/RETHTarget4Deployer.sol";

import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";
import { MockLido } from "contracts/test/MockLido.sol";
import { Lib } from "test/utils/Lib.sol";
import { HyperdriveRegistry } from "contracts/src/factory/HyperdriveRegistry.sol";
import { IRestakeManager } from "contracts/src/interfaces/IRenzo.sol";
import { IRiverV1 } from "contracts/src/interfaces/IRiverV1.sol";
import { IRocketTokenRETH } from "contracts/src/interfaces/IRocketTokenRETH.sol";
import { DeploymentConfig } from "./DeploymentConfig.sol";

struct PoolConstructorData {
    IHyperdrive.PoolConfig poolConfig;
    address target0;
    address target1;
    address target2;
    address target3;
    address target4;
}

struct HyperdriveInstanceSummary {
    string name;
    string poolType;
    bytes constructorArgs;
    address hyperdrive;
    address target0;
    address target1;
    address target2;
    address target3;
    address target4;
}

struct deploymentummary {
    address deployer;
    string name;
    uint256 chainId;
    address linkerFactory;
    address factory;
    address registry;
    mapping(string => address) poolTypeToCoordinator;
    HyperdriveInstanceSummary[] instances;
}

contract Deployer is Script, DeploymentConfig {
    using FixedPointMath for *;
    using Lib for *;

    // Directory containing all network configuration files.
    string constant CONFIG_DIR = "./script/deploy/config";
    string constant SUMMARY_DIR = "./script/deploy/summaries";

    // TODO: Replace these with a mapping of (network => token address)
    address constant LIDO = address(0);
    address constant RENZO = address(0);
    address constant RIVERV1 = address(0);
    address constant RETH = address(0);

    address deployer;

    /// @dev Read in the configuration files and deploy each network.
    function run() external {
        // Obtain the deployer private key and address from the environment.
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer is %s", deployer);

        // Read raw content of all deployment configs into memory.
        string[] memory rawDeploymentConfigs = readConfigFiles(
            "./script/deploy/config"
        );
        uint256 deploymentCount = rawDeploymentConfigs.length;

        // Iterate through the deployment configurations and execute each one.
        for (uint i = 0; i < deploymentCount; i++) {
            console.log("Beginning Deployment %s.", i);
            // Parse the deployment configuration.
            string memory name = loadFromTOML(
                rawDeploymentConfigs[i],
                deployer
            );
            NetworkDeployment storage deployment = deployments[name];

            console.log("Parsed configuration for network %s.", name);

            // set the rpc url and begin broadcasting transactions
            vm.createSelectFork(vm.rpcUrl(deployment.network.rpc_name));
            vm.startBroadcast(deployerPrivateKey);

            // Deploy the linker and store the address in the summary struct.
            address linkerFactory = address(new ERC20ForwarderFactory());

            // Deploy the factory and store the address in the summary struct.
            address factory = address(
                new HyperdriveFactory(
                    HyperdriveFactory.FactoryConfig({
                        governance: deployer,
                        hyperdriveGovernance: deployer,
                        defaultPausers: deployment.access.defaultPausers,
                        feeCollector: deployment.access.feeCollector,
                        sweepCollector: deployment.access.sweepCollector,
                        checkpointDurationResolution: deployment
                            .bounds
                            .checkpointDurationResolution,
                        minCheckpointDuration: deployment
                            .bounds
                            .minCheckpointDuration,
                        maxCheckpointDuration: deployment
                            .bounds
                            .maxCheckpointDuration,
                        minPositionDuration: deployment
                            .bounds
                            .minPositionDuration,
                        maxPositionDuration: deployment
                            .bounds
                            .maxPositionDuration,
                        minFixedAPR: deployment.bounds.minFixedAPR,
                        maxFixedAPR: deployment.bounds.maxFixedAPR,
                        minTimeStretchAPR: deployment.bounds.minTimeStretchAPR,
                        maxTimeStretchAPR: deployment.bounds.maxTimeStretchAPR,
                        minFees: deployment.bounds.minFees,
                        maxFees: deployment.bounds.maxFees,
                        linkerFactory: linkerFactory,
                        linkerCodeHash: ERC20ForwarderFactory(linkerFactory)
                            .ERC20LINK_HASH()
                    })
                )
            );
            console.log(factory);

            // Deploy the registry and store the address in the summary struct.
            address registry = address(new HyperdriveRegistry());

            // Deploy each pool in the network configuration.
            for (uint j = 0; j < deployment.pools.length; j++) {
                // The current pool struct.
                DeploymentConfig.PoolDeployment memory p = deployment.pools[j];

                // Deploy the hyperdrive coordinator for the pooltype if it hasn't been already.
                address coordinator = deployHyperdriveCoordinator(
                    factory,
                    p.init.poolType
                );
                HyperdriveFactory(payable(factory)).addDeployerCoordinator(
                    coordinator
                );
                console.log("coordinator");

                // Deploy the pool.
                IHyperdrive.PoolDeployConfig memory config = IHyperdrive
                    .PoolDeployConfig({
                        baseToken: IERC20(p.tokens.base),
                        vaultSharesToken: IERC20(p.tokens.shares),
                        linkerFactory: linkerFactory,
                        linkerCodeHash: ERC20ForwarderFactory(linkerFactory)
                            .ERC20LINK_HASH(),
                        minimumShareReserves: p.bounds.minimumShareReserves,
                        minimumTransactionAmount: p.bounds.minimumShareReserves,
                        positionDuration: p.bounds.positionDuration,
                        checkpointDuration: p.bounds.checkpointDuration,
                        timeStretch: p.bounds.timeStretch,
                        governance: deployer,
                        feeCollector: p.access.feeCollector,
                        sweepCollector: p.access.sweepCollector,
                        fees: p.fees
                    });

                console.log("config");

                // // Mint the contribution tokens.
                // ERC20Mintable(p.tokens.base).mint(p.init.contribution);

                // // Approve the deployer coordinator.
                // ERC20Mintable(p.tokens.base).approve(
                //     address(coordinator),
                //     p.init.contribution
                // );

                console.log("mint");

                HyperdriveFactory(payable(factory)).deployTarget(
                    p.init.deploymentId,
                    address(coordinator),
                    config,
                    new bytes(0),
                    p.init.fixedAPR,
                    p.init.timeStretchAPR,
                    0,
                    p.init.salt
                );
                HyperdriveFactory(payable(factory)).deployTarget(
                    p.init.deploymentId,
                    address(coordinator),
                    config,
                    new bytes(0),
                    p.init.fixedAPR,
                    p.init.timeStretchAPR,
                    1,
                    p.init.salt
                );
                HyperdriveFactory(payable(factory)).deployTarget(
                    p.init.deploymentId,
                    address(coordinator),
                    config,
                    new bytes(0),
                    p.init.fixedAPR,
                    p.init.timeStretchAPR,
                    2,
                    p.init.salt
                );
                HyperdriveFactory(payable(factory)).deployTarget(
                    p.init.deploymentId,
                    address(coordinator),
                    config,
                    new bytes(0),
                    p.init.fixedAPR,
                    p.init.timeStretchAPR,
                    3,
                    p.init.salt
                );
                HyperdriveFactory(payable(factory)).deployTarget(
                    p.init.deploymentId,
                    address(coordinator),
                    config,
                    new bytes(0),
                    p.init.fixedAPR,
                    p.init.timeStretchAPR,
                    4,
                    p.init.salt
                );
                // Deploy a pool.
                address instance = address(
                    HyperdriveFactory(payable(factory)).deployAndInitialize(
                        p.init.deploymentId,
                        address(coordinator),
                        config,
                        new bytes(0),
                        p.init.contribution,
                        p.init.fixedAPR,
                        p.init.fixedAPR,
                        IHyperdrive.Options({
                            destination: deployer,
                            asBase: true,
                            extraData: new bytes(0)
                        }),
                        p.init.salt
                    )
                );

                // update the summary with the freshly deployed instance
                // summaries.instances[j] = HyperdriveInstanceSummary({
                //     name: p.init.name,
                //     poolType: p.init.poolType,
                //     constructorArgs: abi.encode(
                //         IHyperdrive(instance).getPoolConfig(),
                //         targets[0],
                //         targets[1],
                //         targets[2],
                //         targets[3],
                //         targets[4]
                //     ),
                //     hyperdrive: instance,
                //     target0: targets[0],
                //     target1: targets[1],
                //     target2: targets[2],
                //     target3: targets[3],
                //     target4: targets[4]
                // });
            }
            // stop broadcasting so we can fork to a different network next iteration
            vm.stopBroadcast();
        }
    }

    /// @dev Read the contents of the configuration directory, nested directories are not supported.
    function readConfigFiles(
        string memory dir
    ) internal view returns (string[] memory) {
        VmSafe.DirEntry[] memory files = vm.readDir(dir);
        string[] memory contents = new string[](files.length);
        for (uint i = 0; i < files.length; i++) {
            if (files[i].isDir) revert("nested files are not supported");

            console.log("Loading configuration at %s", files[i].path);

            contents[i] = vm.readFile(files[i].path);
        }
        return contents;
    }

    function deployHyperdriveCoordinator(
        address factory,
        string memory poolType
    ) internal returns (address) {
        if (DeploymentConfig.strEquals(poolType, "ERC4626")) {
            return
                address(
                    new ERC4626HyperdriveDeployerCoordinator(
                        address(factory),
                        address(new ERC4626HyperdriveCoreDeployer()),
                        address(new ERC4626Target0Deployer()),
                        address(new ERC4626Target1Deployer()),
                        address(new ERC4626Target2Deployer()),
                        address(new ERC4626Target3Deployer()),
                        address(new ERC4626Target4Deployer())
                    )
                );
        } else if (DeploymentConfig.strEquals(poolType, "StETH")) {
            return
                address(
                    new StETHHyperdriveDeployerCoordinator(
                        address(factory),
                        address(new StETHHyperdriveCoreDeployer()),
                        address(new StETHTarget0Deployer()),
                        address(new StETHTarget1Deployer()),
                        address(new StETHTarget2Deployer()),
                        address(new StETHTarget3Deployer()),
                        address(new StETHTarget4Deployer()),
                        ILido(address(LIDO))
                    )
                );
        } else if (DeploymentConfig.strEquals(poolType, "EzETH")) {
            return
                address(
                    new EzETHHyperdriveDeployerCoordinator(
                        address(factory),
                        address(
                            new EzETHHyperdriveCoreDeployer(
                                IRestakeManager(RENZO)
                            )
                        ),
                        address(
                            new EzETHTarget0Deployer(IRestakeManager(RENZO))
                        ),
                        address(
                            new EzETHTarget1Deployer(IRestakeManager(RENZO))
                        ),
                        address(
                            new EzETHTarget2Deployer(IRestakeManager(RENZO))
                        ),
                        address(
                            new EzETHTarget3Deployer(IRestakeManager(RENZO))
                        ),
                        address(
                            new EzETHTarget4Deployer(IRestakeManager(RENZO))
                        ),
                        IRestakeManager(RENZO)
                    )
                );
        } else if (DeploymentConfig.strEquals(poolType, "LsETH")) {
            return
                address(
                    new LsETHHyperdriveDeployerCoordinator(
                        address(factory),
                        address(new LsETHHyperdriveCoreDeployer()),
                        address(new LsETHTarget0Deployer()),
                        address(new LsETHTarget1Deployer()),
                        address(new LsETHTarget2Deployer()),
                        address(new LsETHTarget3Deployer()),
                        address(new LsETHTarget4Deployer()),
                        IRiverV1(RIVERV1)
                    )
                );
        } else if (DeploymentConfig.strEquals(poolType, "RETH")) {
            return
                address(
                    new RETHHyperdriveDeployerCoordinator(
                        address(factory),
                        address(new RETHHyperdriveCoreDeployer()),
                        address(new RETHTarget0Deployer()),
                        address(new RETHTarget1Deployer()),
                        address(new RETHTarget2Deployer()),
                        address(new RETHTarget3Deployer()),
                        address(new RETHTarget4Deployer()),
                        IRocketTokenRETH(RETH)
                    )
                );
        }
        revert("poolType not found");
    }
}
