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
import { MockRocketPool } from "contracts/test/MockRocketPool.sol";
import { Lib } from "test/utils/Lib.sol";
import { HyperdriveRegistry } from "contracts/src/factory/HyperdriveRegistry.sol";
import { IRestakeManager } from "contracts/src/interfaces/IRenzo.sol";
import { IRiverV1 } from "contracts/src/interfaces/IRiverV1.sol";
import { IRocketTokenRETH } from "contracts/src/interfaces/IRocketTokenRETH.sol";
import { FactoryDeploymentConfig } from "./FactoryDeploymentConfig.sol";

struct FactoryDeploymentSummary {
    address deployer;
    string rpcName;
    uint256 chainId;
    address linkerFactory;
    address factory;
    address registry;
    address ezeth;
    address lseth;
    address reth;
    address steth;
    address erc4626Coordinator;
    address ezethCoordinator;
    address lsethCoordinator;
    address rethCoordinator;
    address stethCoordinator;
}

contract Deployer is Script, FactoryDeploymentConfig {
    using FixedPointMath for *;
    using Lib for *;

    // Directory containing all network configuration files.
    string constant CONFIG_DIR = "./script/deploy/config";

    FactoryDeployment deployment;
    FactoryDeploymentSummary summary;

    /// @dev Read in the configuration files and deploy each network.
    function run() external {
        // Obtain the deployer private key and address from the environment.
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        summary.deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer is %s", summary.deployer);

        // Read in the config file and parse it to the FactoryDeployment struct.
        string memory filePath = string.concat(
            CONFIG_DIR,
            "/",
            vm.envString("CONFIG_FILENAME")
        );
        console.log("Loading config file at %s", filePath);
        string memory deploymentConfigRaw = vm.readFile(filePath);
        loadFromTOML(deployment, deploymentConfigRaw);

        summary.rpcName = deployment.rpcName;
        summary.chainId = deployment.chainId;
        console.log("Parsed configuration for network %s.", deployment.rpcName);

        // set the rpc url and begin broadcasting transactions
        vm.createSelectFork(vm.rpcUrl(deployment.rpcName));
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the forwarder.
        summary.linkerFactory = address(new ERC20ForwarderFactory());

        // Deploy the HyperdriveFactory.
        deployFactory(summary.linkerFactory);

        // Deploy the registry.
        summary.registry = address(new HyperdriveRegistry("registry"));

        // Deploy all HyperdriveCoordinators, their targets, and their token(s) if necessary.
        deployHyperdriveCoordinators();

        vm.stopBroadcast();

        writeSummary();
        return;
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

    function deployFactory(address linkerFactory) internal {
        summary.factory = address(
            new HyperdriveFactory(
                HyperdriveFactory.FactoryConfig({
                    governance: deployment.access.governance,
                    hyperdriveGovernance: deployment.access.governance,
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
                    minPositionDuration: deployment.bounds.minPositionDuration,
                    maxPositionDuration: deployment.bounds.maxPositionDuration,
                    minFixedAPR: deployment.bounds.minFixedAPR,
                    maxFixedAPR: deployment.bounds.maxFixedAPR,
                    minTimeStretchAPR: deployment.bounds.minTimeStretchAPR,
                    maxTimeStretchAPR: deployment.bounds.maxTimeStretchAPR,
                    minFees: deployment.bounds.minFees,
                    maxFees: deployment.bounds.maxFees,
                    linkerFactory: linkerFactory,
                    linkerCodeHash: ERC20ForwarderFactory(linkerFactory)
                        .ERC20LINK_HASH()
                }),
                "factory"
            )
        );
    }

    function deployHyperdriveCoordinators() internal {
        // Deploy the ERC4626Coordinator.
        ERC4626HyperdriveDeployerCoordinator erc4626Coordinator = new ERC4626HyperdriveDeployerCoordinator(
                address(summary.factory),
                address(new ERC4626HyperdriveCoreDeployer()),
                address(new ERC4626Target0Deployer()),
                address(new ERC4626Target1Deployer()),
                address(new ERC4626Target2Deployer()),
                address(new ERC4626Target3Deployer()),
                address(new ERC4626Target4Deployer())
            );
        summary.erc4626Coordinator = address(erc4626Coordinator);

        // Deploy a mock StETH token if an address was not provided.
        if (deployment.tokens.steth == address(0)) {
            deployment.tokens.steth = deployStETH();
            summary.steth = deployment.tokens.steth;
        }
        // Deploy the StETHCoordinator.
        StETHHyperdriveDeployerCoordinator stethCoordinator = new StETHHyperdriveDeployerCoordinator(
                address(summary.factory),
                address(new StETHHyperdriveCoreDeployer()),
                address(new StETHTarget0Deployer()),
                address(new StETHTarget1Deployer()),
                address(new StETHTarget2Deployer()),
                address(new StETHTarget3Deployer()),
                address(new StETHTarget4Deployer()),
                ILido(deployment.tokens.steth)
            );
        summary.stethCoordinator = address(stethCoordinator);

        // Deply the EzETHCoordinator if an address for EzETH was provided, otherwise skip.
        if (deployment.tokens.ezeth != address(0)) {
            summary.ezethCoordinator = address(
                new EzETHHyperdriveDeployerCoordinator(
                    address(summary.factory),
                    address(
                        new EzETHHyperdriveCoreDeployer(
                            IRestakeManager(deployment.tokens.ezeth)
                        )
                    ),
                    address(
                        new EzETHTarget0Deployer(
                            IRestakeManager(deployment.tokens.ezeth)
                        )
                    ),
                    address(
                        new EzETHTarget1Deployer(
                            IRestakeManager(deployment.tokens.ezeth)
                        )
                    ),
                    address(
                        new EzETHTarget2Deployer(
                            IRestakeManager(deployment.tokens.ezeth)
                        )
                    ),
                    address(
                        new EzETHTarget3Deployer(
                            IRestakeManager(deployment.tokens.ezeth)
                        )
                    ),
                    address(
                        new EzETHTarget4Deployer(
                            IRestakeManager(deployment.tokens.ezeth)
                        )
                    ),
                    IRestakeManager(deployment.tokens.ezeth)
                )
            );
        } else {
            console.log(
                "skipping deployment of EzETHCoordinator... no EzETH address provided."
            );
        }

        // Deply the LsETHCoordinator if an address for LsETH was provided, otherwise skip.
        if (deployment.tokens.lseth != address(0)) {
            summary.lsethCoordinator = address(
                new LsETHHyperdriveDeployerCoordinator(
                    address(summary.factory),
                    address(new LsETHHyperdriveCoreDeployer()),
                    address(new LsETHTarget0Deployer()),
                    address(new LsETHTarget1Deployer()),
                    address(new LsETHTarget2Deployer()),
                    address(new LsETHTarget3Deployer()),
                    address(new LsETHTarget4Deployer()),
                    IRiverV1(deployment.tokens.lseth)
                )
            );
        } else {
            console.log(
                "skipping deployment of LsETHCoordinator... no LsETH address provided."
            );
        }

        // Deploy a mock RETH token if an address was not provided.
        if (deployment.tokens.reth == address(0)) {
            deployment.tokens.reth = deployRETH();
            summary.reth = deployment.tokens.reth;
        }
        summary.rethCoordinator = address(
            new RETHHyperdriveDeployerCoordinator(
                address(summary.factory),
                address(new RETHHyperdriveCoreDeployer()),
                address(new RETHTarget0Deployer()),
                address(new RETHTarget1Deployer()),
                address(new RETHTarget2Deployer()),
                address(new RETHTarget3Deployer()),
                address(new RETHTarget4Deployer()),
                IRocketTokenRETH(deployment.tokens.reth)
            )
        );
    }

    function deployStETH() internal returns (address) {
        MockLido steth = new MockLido(
            0.035e18,
            deployment.access.admin,
            true,
            500e18
        );
        steth.setPublicCapability(bytes4(keccak256("mint(uint256)")), true);
        return address(steth);
    }

    function deployRETH() internal returns (address) {
        MockRocketPool reth = new MockRocketPool(
            0.035e18,
            deployment.access.admin,
            true,
            500e18
        );
        reth.setPublicCapability(bytes4(keccak256("mint(uint256)")), true);
        return address(reth);
    }

    function writeSummary() internal {
        string memory root = "root";
        vm.serializeAddress(root, "deployer", summary.deployer);
        vm.serializeString(root, "rpcName", summary.rpcName);
        vm.serializeUint(root, "chain_id", summary.chainId);
        vm.serializeAddress(root, "linker_factory", summary.linkerFactory);
        vm.serializeAddress(root, "factory", summary.factory);
        vm.serializeAddress(root, "registry", summary.registry);
        vm.serializeAddress(root, "ezeth", summary.ezeth);
        vm.serializeAddress(root, "lseth", summary.lseth);
        vm.serializeAddress(root, "reth", summary.reth);
        vm.serializeAddress(root, "steth", summary.steth);
        vm.serializeAddress(
            root,
            "erc4626Coordinator",
            summary.erc4626Coordinator
        );
        vm.serializeAddress(root, "stethCoordinator", summary.stethCoordinator);
        vm.serializeAddress(root, "ezethCoordinator", summary.ezethCoordinator);
        vm.serializeAddress(root, "lsethCoordinator", summary.lsethCoordinator);
        string memory finalJSON = vm.serializeAddress(
            root,
            "rethCoordinator",
            summary.rethCoordinator
        );

        vm.writeToml(
            finalJSON,
            string.concat(
                "./script/deploy/summaries/factory-",
                summary.rpcName,
                "-",
                vm.toString(vm.unixTime()),
                ".toml"
            )
        );
    }
}
