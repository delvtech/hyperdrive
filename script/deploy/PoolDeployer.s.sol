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
import { MockRocketPool } from "contracts/test/MockRocketPool.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";
import { MockLido } from "contracts/test/MockLido.sol";
import { Lib } from "test/utils/Lib.sol";
import { HyperdriveRegistry } from "contracts/src/factory/HyperdriveRegistry.sol";
import { IRestakeManager } from "contracts/src/interfaces/IRenzo.sol";
import { IRiverV1 } from "contracts/src/interfaces/IRiverV1.sol";
import { IRocketTokenRETH } from "contracts/src/interfaces/IRocketTokenRETH.sol";
import { PoolDeploymentConfig } from "script/deploy/PoolDeploymentConfig.sol";
import { IHyperdriveDeployerCoordinator } from "contracts/src/interfaces/IHyperdriveDeployerCoordinator.sol";

struct InstanceSummary {
    address hyperdrive;
    address target0;
    address target1;
    address target2;
    address target3;
    address target4;
    bytes targetConstructorArgs;
    bytes hyperdriveConstructorArgs;
}

struct DeploymentSummary {
    address deployer;
    string rpcName;
    uint256 chainId;
    string name;
    address factory;
    address coordinator;
    string coordinatorName;
    address registry;
    bool registryUpdated;
    address baseToken;
    address sharesToken;
    InstanceSummary instanceSummary;
}

contract Deployer is Script, PoolDeploymentConfig {
    using FixedPointMath for *;
    using Lib for *;

    // Directory containing all network configuration files.
    string constant CONFIG_DIR = "./script/deploy/config";

    PoolDeployment deployment;
    DeploymentSummary summary;

    /// @dev Read in the configuration files and deploy each network.
    function run() external {
        // Obtain the deployer private key and address from the environment.
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        summary.deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer is %s", summary.deployer);

        // Read in the config file and parse it to the PoolDeployment struct.
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
        summary.name = deployment.init.name;
        console.log("Parsed configuration for network %s.", summary.name);

        // set the rpc url and begin broadcasting transactions
        vm.createSelectFork(vm.rpcUrl(deployment.rpcName));
        vm.startBroadcast(deployerPrivateKey);

        // Retrieve the name of the coordinator and use it to identify which type of pool is being deployed.
        summary.coordinatorName = IHyperdriveDeployerCoordinator(
            deployment.init.coordinator
        ).name();

        // If the pool is an ERC4626 make some instance-specific preparations.
        if (
            strEquals(
                summary.coordinatorName,
                "ERC4626HyperdriveDeployerCoordinator"
            )
        ) {
            // If no token was specified, deploy them (helpful for testnet).
            if (
                deployment.tokens.base == address(0) &&
                deployment.tokens.shares == address(0)
            ) {
                console.log(
                    "Deploying tokens for hyperdrive instance since none were specified."
                );
                ERC20Mintable dai = new ERC20Mintable(
                    "DAI",
                    "DAI",
                    18,
                    deployment.access.admin,
                    true,
                    10000e18
                );
                deployment.tokens.base = address(dai);
                MockERC4626 sdai = new MockERC4626(
                    dai,
                    "Savings DAI",
                    "SDAI",
                    0.13e18,
                    deployment.access.admin,
                    true,
                    10000e18
                );
                deployment.tokens.shares = address(sdai);
            }
            // If the deployer doesn't have enough base token for the contribution, attempt to mint them some.
            if (
                ERC20Mintable(deployment.tokens.base).balanceOf(
                    summary.deployer
                ) < deployment.init.contribution
            ) {
                console.log("Minting base tokens for deployer.");
                ERC20Mintable(deployment.tokens.base).mint(
                    deployment.init.contribution
                );
            }
            // Ensure the deployer has approved the deployer coordinator.
            ERC20Mintable(deployment.tokens.base).approve(
                deployment.init.coordinator,
                deployment.init.contribution
            );
        }

        // If the pool is RETH make some instance-specific preparations.
        if (
            strEquals(
                summary.coordinatorName,
                "RETHHyperdriveDeployerCoordinator"
            )
        ) {
            // Obtain sufficient shares for the contribution.
            MockRocketPool(deployment.tokens.shares).submit{
                value: deployment.init.contribution
            }(summary.deployer);
            // Approve the coordinator for the contribution.
            MockRocketPool(deployment.tokens.shares).approve(
                deployment.init.coordinator,
                deployment.init.contribution
            );
        }

        // Save pool parameters to summary.
        summary.factory = deployment.init.factory;
        summary.coordinator = deployment.init.coordinator;
        summary.baseToken = deployment.tokens.base;
        summary.sharesToken = deployment.tokens.shares;

        // Build the PoolDeployConfig for deploying the hyperdrive instance.
        IHyperdrive.PoolDeployConfig memory config = IHyperdrive
            .PoolDeployConfig({
                baseToken: IERC20(deployment.tokens.base),
                vaultSharesToken: IERC20(deployment.tokens.shares),
                linkerFactory: HyperdriveFactory(
                    payable(deployment.init.factory)
                ).linkerFactory(),
                linkerCodeHash: HyperdriveFactory(
                    payable(deployment.init.factory)
                ).linkerCodeHash(),
                minimumShareReserves: deployment.bounds.minimumShareReserves,
                minimumTransactionAmount: deployment
                    .bounds
                    .minimumShareReserves,
                positionDuration: deployment.bounds.positionDuration,
                checkpointDuration: deployment.bounds.checkpointDuration,
                timeStretch: deployment.bounds.timeStretch,
                governance: deployment.access.governance,
                feeCollector: deployment.access.feeCollector,
                sweepCollector: deployment.access.sweepCollector,
                fees: deployment.fees
            });

        // Deploy the targets and the hyperdrive instance.
        summary.instanceSummary.target0 = HyperdriveFactory(
            payable(deployment.init.factory)
        ).deployTarget(
                deployment.init.deploymentId,
                deployment.init.coordinator,
                config,
                new bytes(0),
                deployment.init.fixedAPR,
                deployment.init.timeStretchAPR,
                0,
                deployment.init.salt
            );
        summary.instanceSummary.target1 = HyperdriveFactory(
            payable(deployment.init.factory)
        ).deployTarget(
                deployment.init.deploymentId,
                deployment.init.coordinator,
                config,
                new bytes(0),
                deployment.init.fixedAPR,
                deployment.init.timeStretchAPR,
                1,
                deployment.init.salt
            );
        summary.instanceSummary.target2 = HyperdriveFactory(
            payable(deployment.init.factory)
        ).deployTarget(
                deployment.init.deploymentId,
                deployment.init.coordinator,
                config,
                new bytes(0),
                deployment.init.fixedAPR,
                deployment.init.timeStretchAPR,
                2,
                deployment.init.salt
            );
        summary.instanceSummary.target3 = HyperdriveFactory(
            payable(deployment.init.factory)
        ).deployTarget(
                deployment.init.deploymentId,
                deployment.init.coordinator,
                config,
                new bytes(0),
                deployment.init.fixedAPR,
                deployment.init.timeStretchAPR,
                3,
                deployment.init.salt
            );
        summary.instanceSummary.target4 = HyperdriveFactory(
            payable(deployment.init.factory)
        ).deployTarget(
                deployment.init.deploymentId,
                deployment.init.coordinator,
                config,
                new bytes(0),
                deployment.init.fixedAPR,
                deployment.init.timeStretchAPR,
                4,
                deployment.init.salt
            );
        IHyperdrive hyperdrive = HyperdriveFactory(
            payable(deployment.init.factory)
        ).deployAndInitialize(
                deployment.init.deploymentId,
                deployment.init.coordinator,
                config,
                new bytes(0),
                deployment.init.contribution,
                deployment.init.fixedAPR,
                deployment.init.timeStretchAPR,
                deployment.options,
                deployment.init.salt
            );
        summary.instanceSummary.hyperdrive = address(hyperdrive);

        // Update the registry with the freshly deployed pool if possible.
        if (
            HyperdriveRegistry(deployment.init.registry).governance() ==
            summary.deployer
        ) {
            HyperdriveRegistry(deployment.init.registry).setHyperdriveInfo(
                address(hyperdrive),
                1
            );
            summary.registryUpdated = true;
            console.log("Updated registry with the new hyperdrive instance.");
        } else {
            console.log(
                "Unable to update registry with new hyperdrive instance."
            );
        }

        // Compute the constructor args for the targets and the hyperdrive instance so they can be verified after deployment.
        summary.instanceSummary.targetConstructorArgs = abi.encode(
            hyperdrive.getPoolConfig()
        );
        summary.instanceSummary.hyperdriveConstructorArgs = abi.encode(
            hyperdrive.getPoolConfig(),
            summary.instanceSummary.target0,
            summary.instanceSummary.target1,
            summary.instanceSummary.target2,
            summary.instanceSummary.target3,
            summary.instanceSummary.target4
        );

        // Write out the summary
        writeSummary();

        vm.stopBroadcast();
    }

    function writeSummary() internal {
        string memory root = "root";
        vm.serializeAddress(root, "deployer", summary.deployer);
        vm.serializeString(root, "rpcName", summary.rpcName);
        vm.serializeUint(root, "chain_id", summary.chainId);
        vm.serializeString(root, "name", summary.name);
        vm.serializeAddress(root, "factory", summary.factory);
        vm.serializeAddress(root, "coordinator", summary.coordinator);
        vm.serializeString(root, "coordinatorName", summary.coordinatorName);
        vm.serializeAddress(root, "registry", summary.registry);
        vm.serializeBool(root, "registryUpdated", summary.registryUpdated);
        vm.serializeAddress(root, "baseToken", summary.baseToken);
        vm.serializeAddress(root, "sharesToken", summary.sharesToken);

        string memory instanceSummaryKey = "instanceSummary";
        vm.serializeAddress(
            instanceSummaryKey,
            "hyperdrive",
            summary.instanceSummary.hyperdrive
        );
        vm.serializeAddress(
            instanceSummaryKey,
            "target0",
            summary.instanceSummary.target0
        );
        vm.serializeAddress(
            instanceSummaryKey,
            "target1",
            summary.instanceSummary.target1
        );
        vm.serializeAddress(
            instanceSummaryKey,
            "target2",
            summary.instanceSummary.target2
        );
        vm.serializeAddress(
            instanceSummaryKey,
            "target3",
            summary.instanceSummary.target3
        );
        vm.serializeAddress(
            instanceSummaryKey,
            "target4",
            summary.instanceSummary.target4
        );
        vm.serializeBytes(
            instanceSummaryKey,
            "targetConstructorArgs",
            summary.instanceSummary.targetConstructorArgs
        );
        string memory instanceSummaryObj = vm.serializeBytes(
            instanceSummaryKey,
            "hyperdriveConstructorArgs",
            summary.instanceSummary.hyperdriveConstructorArgs
        );
        string memory finalJSON = vm.serializeString(
            root,
            "instanceSummary",
            instanceSummaryObj
        );

        vm.writeToml(
            finalJSON,
            string.concat(
                "./script/deploy/summaries/pool-",
                summary.rpcName,
                "-",
                summary.name,
                "-",
                vm.toString(vm.unixTime()),
                ".toml"
            )
        );
    }
}
