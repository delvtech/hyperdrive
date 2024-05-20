// To extend one of Hardhat's types, you need to import the module where it has been defined, and redeclare it.
import {
    ContractName,
    GetContractReturnType,
} from "@nomicfoundation/hardhat-viem/types";
import { extendEnvironment, types } from "hardhat/config";
import { ArtifactsMap } from "hardhat/types";
import "hardhat/types/config";
import "hardhat/types/runtime";
import { ConfigurableTaskDefinition } from "hardhat/types/runtime";
import { Address, ContractConstructorArgs, isHex } from "viem";
import { Deployments } from "./deployments";
import { evaluateValueOrHREFn } from "./utils";

/**
 * Options accepted by all Hyperdrive deploy tasks
 */
export type HyperdriveDeployRuntimeOptions = {
    // Options to pass to `viem.deployContract`
    viemConfig?: {
        gas?: bigint;
        gasPrice?: bigint;
        maxFeePerGas?: bigint;
        maxPriorityFeePerGas?: bigint;
    };
};

/**
 * Represents the parameters used by all Hyperdrive deploy tasks
 */
export type HyperdriveDeployBaseTaskParams = HyperdriveDeployRuntimeOptions;

/**
 * Represents the parameters for a Hyperdrive deploy task requiring a name
 */
export type HyperdriveDeployNamedTaskParams = HyperdriveDeployRuntimeOptions & {
    // Name of the primary contract to deploy
    //  - supporting contract names will be derived from it if applicable
    name: string;
};

/**
 * Base Hyperdrive deploy task, left as a stub to easily add params across all deploy tasks.
 */
export const HyperdriveDeployBaseTask = (task: ConfigurableTaskDefinition) =>
    task;

/**
 * Named Hyperdrive deploy task with all base params already added.
 */
export const HyperdriveDeployNamedTask = (task: ConfigurableTaskDefinition) =>
    HyperdriveDeployBaseTask(task).addParam(
        "name",
        "name of the primary contract to deploy (supporting contract names will be derived from it)",
        undefined,
        types.string,
    );

declare module "hardhat/types/runtime" {
    interface HardhatRuntimeEnvironment {
        hyperdriveDeploy: {
            deployments: Deployments;
            ensureDeployed: <
                T extends ArtifactsMap[keyof ArtifactsMap]["contractName"],
            >(
                name: string,
                contract: T,
                args: ContractConstructorArgs<ArtifactsMap[T]["abi"]>,
                options?: HyperdriveDeployRuntimeOptions,
            ) => Promise<GetContractReturnType<ArtifactsMap[T]["abi"]>>;
            deployFactory: (
                name: string,
                options?: HyperdriveDeployRuntimeOptions,
            ) => Promise<
                GetContractReturnType<ArtifactsMap["HyperdriveFactory"]["abi"]>
            >;
            deployCoordinator: <
                T extends ArtifactsMap[keyof ArtifactsMap &
                    `${string}HyperdriveDeployerCoordinator`]["contractName"],
            >(
                name: string,
                options?: HyperdriveDeployRuntimeOptions,
            ) => Promise<GetContractReturnType<ArtifactsMap[T]["abi"]>>;
            deployInstance: <
                T extends ArtifactsMap[keyof ArtifactsMap]["contractName"],
            >(
                name: string,
                options?: HyperdriveDeployRuntimeOptions,
            ) => Promise<GetContractReturnType<ArtifactsMap[T]["abi"]>>;
        };
    }
}

export interface Link {
    sourceName: string;
    libraryName: string;
    address: string;
}

extendEnvironment((hre) => {
    let deployments = new Deployments(hre);
    let config = hre.config.networks[hre.network.name].hyperdriveDeploy;
    let ensureDeployed: typeof hre.hyperdriveDeploy.ensureDeployed = async (
        name,
        contract,
        args,
        { viemConfig } = {},
    ) => {
        if (!!deployments.byNameSafe(name)) {
            console.log(`skipping ${name}, found existing deployment`);
            return (await hre.viem.getContractAt(
                contract as ContractName<typeof contract>,
                deployments.byNameSafe(name)!.address,
            )) as unknown as GetContractReturnType<
                ArtifactsMap[typeof contract]["abi"]
            >;
        }
        console.log(`deploying ${name}...`);

        const instance = await hre.viem.deployContract(
            contract as ContractName<typeof contract>,
            args as any,
            { ...viemConfig, gas: 5_000_000n },
        );

        console.log(` - saving ${name}...`);
        deployments.add(name, contract, instance.address);

        return hre.viem.getContractAt(
            contract as ContractName<typeof contract>,
            instance.address,
        ) as unknown as GetContractReturnType<
            ArtifactsMap[typeof contract]["abi"]
        >;
    };

    let deployFactory: typeof hre.hyperdriveDeploy.deployFactory = async (
        name,
        options,
    ) => {
        let factoryConfig = config?.factories?.find((f) => f.name === name);
        if (!factoryConfig) {
            throw new Error(
                `no factory deploy configuration found for ${name}`,
            );
        }

        // run prepare function if present
        if (!deployments.byNameSafe(name) && factoryConfig.prepare) {
            console.log(`running prepare for ${name} ...`);
            await factoryConfig.prepare(hre, options ?? {});
        }

        // deploy the factory
        let instance = await ensureDeployed(
            name,
            "HyperdriveFactory",
            await evaluateValueOrHREFn(
                factoryConfig.constructorArguments,
                hre,
                options,
            ),
            options,
        );

        // run the setup function if present
        if (factoryConfig.setup) {
            console.log(` - running setup function for ${name}`);
            await factoryConfig.setup(hre, options ?? {});
        }
        return instance;
    };

    let deployCoordinator = async (
        name: string,
        options?: HyperdriveDeployRuntimeOptions,
    ) => {
        // Retrieve configuration for the coordinator by finding one with the same name/network
        // in the configuration file
        let coordinatorConfig = config?.coordinators?.find(
            (f) => f.name === name,
        );
        if (!coordinatorConfig) {
            throw new Error(
                `no coordinator deploy configuration found for ${name}`,
            );
        }

        // run prepare function if present
        if (!deployments.byNameSafe(name) && coordinatorConfig.prepare) {
            console.log(`running prepare for ${name} ...`);
            await coordinatorConfig.prepare(hre, options ?? {});
        }

        // Deploy the LPMath contract if needed
        let { address: lpMathAddress } = await ensureDeployed(
            `LPMath`,
            "LPMath",
            [],
            options,
        );
        let lpMathArtifact = await hre.artifacts.readArtifact("LPMath");
        let libraries: Link[] = [
            {
                address: lpMathAddress,
                sourceName: lpMathArtifact.sourceName,
                libraryName: "LPMath",
            },
        ];

        // Parse out the prefix to name various components
        let { prefix } = coordinatorConfig;

        // Resolve the token (deploying it if defined)
        let token = coordinatorConfig.token
            ? await evaluateValueOrHREFn(coordinatorConfig.token, hre, options)
            : undefined;

        // Deploy the HyperdriveCoreDeployer
        let coreDeployerContractName = `${prefix}HyperdriveCoreDeployer`;
        let extraArgs = await evaluateValueOrHREFn(
            coordinatorConfig.extraConstructorArgs,
            hre,
            options,
        );
        let coreDeployer = await ensureDeployed(
            `${name}_${coreDeployerContractName}`,
            coreDeployerContractName as ArtifactsMap[keyof ArtifactsMap]["contractName"],
            extraArgs ?? [],
            options,
        );

        // Obtain the associated HyperdriveFactory instance
        let factoryAddress = await evaluateValueOrHREFn(
            coordinatorConfig.factoryAddress,
            hre,
            options,
        );
        let factory = await hre.viem.getContractAt(
            "HyperdriveFactory",
            factoryAddress,
        );

        // Deploy all of the target deployers and push them to the constructor arguments array
        // for the coordinator
        let deployer = (await hre.getNamedAccounts())[
            "deployer"
        ]! as `0x${string}`;
        let wc = await hre.viem.getWalletClient(deployer);
        let pc = await hre.viem.getPublicClient();
        let targets: Address[] = [];
        let targetCount = await evaluateValueOrHREFn(
            coordinatorConfig.targetCount,
            hre,
            options,
        );
        for (let i = 0; i < targetCount; i++) {
            let targetContractName = `${prefix}Target${i}Deployer`;

            // retrieve from deployments and continue if it already exists
            let targetDeployment = deployments.byNameSafe(
                `${name}_${targetContractName}`,
            );
            if (!!targetDeployment) {
                targets.push(targetDeployment.address);
                continue;
            }

            // link the LPMath library with the target (won't happen unless needed)
            let targetArtifact =
                await hre.artifacts.readArtifact(targetContractName);
            let targetBytecode = targetArtifact.bytecode;
            for (const { sourceName, libraryName, address } of libraries) {
                const linkReferences =
                    targetArtifact.linkReferences[sourceName][libraryName];
                for (const { start, length } of linkReferences) {
                    targetBytecode =
                        targetBytecode.substring(0, 2 + start * 2) +
                        address.substring(2) +
                        targetBytecode.substring(2 + (start + length) * 2);
                }
            }
            targetBytecode = isHex(targetBytecode)
                ? targetBytecode
                : `0x${targetBytecode}`;

            // deploy the contract using the bytecode
            console.log(`deploying ${name}_${targetContractName}`);

            let tx = await wc.deployContract({
                abi: targetArtifact.abi,
                bytecode: targetBytecode as `0x${string}`,
                args: extraArgs ?? [],
                gas: 5_000_000n,
            });
            let receipt = await pc.waitForTransactionReceipt({ hash: tx });
            let address = receipt.contractAddress!;
            targets.push(address);

            // handle options
            console.log(` - saving ${name}_${targetContractName}...`);
            deployments.add(
                `${name}_${targetContractName}`,
                targetContractName,
                address,
            );
        }

        // Deploy the coordinator
        let args = [
            factoryAddress,
            coreDeployer.address,
            ...targets,
            ...(token ? [token] : []),
        ];
        let coordinator = await ensureDeployed(
            name,
            `${prefix}HyperdriveDeployerCoordinator`,
            args as any,
            options,
        );
        if (coordinatorConfig.setup) {
            console.log(` - running setup function for ${name}`);
            await coordinatorConfig.setup(hre, options ?? {});
        }

        // Optionally register the coordinator with the factory if deployer has correct permissions.
        let deployerCoordinatorManager =
            await factory.read.deployerCoordinatorManager();
        if (
            deployer === deployerCoordinatorManager &&
            !(await factory.read.isDeployerCoordinator([coordinator.address]))
        ) {
            console.log(
                `adding ${name}_${prefix}HyperdriveDeployerCoordinator to factory`,
            );
            let tx = await factory.write.addDeployerCoordinator([
                coordinator.address,
            ]);
            await pc.waitForTransactionReceipt({ hash: tx });
        }

        return coordinator as unknown as GetContractReturnType<
            ArtifactsMap[`${typeof prefix}HyperdriveDeployerCoordinator`]["abi"]
        >;
    };

    let deployInstance = async (
        name: string,
        options: HyperdriveDeployRuntimeOptions,
    ) => {
        // Retrieve configuration for the coordinator by finding one with the same name/network
        // in the configuration file
        let instanceConfig = config?.instances?.find((f) => f.name === name);
        if (!instanceConfig) {
            throw new Error(
                `no instance deploy configuration found for ${name}`,
            );
        }

        // run prepare function if present
        if (!deployments.byNameSafe(name) && instanceConfig.prepare) {
            console.log(`running prepare for ${name} ...`);
            await instanceConfig.prepare(hre, options ?? {});
        }

        // Parse out the prefix so it can be used to name the various
        // components
        let { prefix } = instanceConfig;

        // Retrieve the HyperdriveDeployerCoordinator from the configuration and ensure it is
        // approved with its factory before continuing
        let coordinator = await hre.viem.getContractAt(
            `HyperdriveDeployerCoordinator`,
            await evaluateValueOrHREFn(
                instanceConfig.coordinatorAddress,
                hre,
                options,
            ),
        );
        let factory = await hre.viem.getContractAt(
            "HyperdriveFactory",
            await coordinator.read.factory(),
        );
        let factoryHasCoordinator = factory.read.isDeployerCoordinator([
            coordinator.address,
        ]);
        if (!factoryHasCoordinator)
            throw new Error(
                `skipping ${name}, factory does not have coordinator for instance with name '${name}`,
            );

        // Obtain the factory deployment and artifacts to use for simulation and calling the
        // `deployTarget` function.
        let pc = await hre.viem.getPublicClient();
        let targets: `0x${string}`[] = [];
        let { deploymentId, extraData, fixedAPR, timestretchAPR, salt } =
            instanceConfig;
        let poolDeployConfig = await evaluateValueOrHREFn(
            instanceConfig.poolDeployConfig,
            hre,
            options ?? {},
        );
        let coordinatorAddress = await evaluateValueOrHREFn(
            instanceConfig.coordinatorAddress,
            hre,
            options,
        );
        let targetCount = await coordinator.read.getNumberOfTargets();
        for (let i = 0; i < Number(targetCount); i++) {
            let contractName = `${prefix}Target${i}`;
            // skip if the target is already deployed
            let existingDeployment = deployments.byNameSafe(
                `${name}_${contractName}`,
            );
            if (!!existingDeployment) {
                // record the address for the hyperdrive instance constructor args
                targets.push(existingDeployment.address);
                continue;
            }

            // deploy the target
            console.log(`deploying ${name}_${contractName}...`);
            let args = [
                deploymentId,
                coordinatorAddress,
                poolDeployConfig,
                extraData,
                fixedAPR,
                timestretchAPR,
                BigInt(i).valueOf(),
                salt,
            ];
            let { result: address } = await factory.simulate.deployTarget(
                args as any,
                {
                    gas: 5_000_000n,
                    ...options.viemConfig,
                },
            );
            let tx = await factory.write.deployTarget(args as any, {
                gas: 5_000_000n,
                ...(options.viemConfig as any),
            });
            await pc.waitForTransactionReceipt({
                hash: tx,
            });

            // record the address for the hyperdrive instance constructor args
            targets.push(address);

            // Save
            console.log(` - saving ${name}_${contractName}`);
            deployments.add(`${name}_${contractName}`, contractName, address!);
        }

        // skip deploying the instance if it already exists
        if (!!deployments.byNameSafe(name)) {
            return hre.viem.getContractAt(
                `${prefix}Hyperdrive` as string,
                deployments.byName(name).address,
            );
        }

        // prepare arguments
        let args = [
            deploymentId,
            coordinatorAddress,
            poolDeployConfig,
            extraData,
            instanceConfig.contribution,
            fixedAPR,
            timestretchAPR,
            await evaluateValueOrHREFn(instanceConfig.options, hre, options),
            salt,
        ];

        // Simulate and deploy
        console.log(`deploying ${name}_${prefix}Hyperdrive`);
        let { result: address } = await factory.simulate.deployAndInitialize(
            args as any,
            {
                gas: 5_000_000n,
            },
        );
        let tx = await factory.write.deployAndInitialize(args as any, {
            gas: 5_000_000n,
        });
        await pc.waitForTransactionReceipt({ hash: tx });

        // Save
        console.log(` - Saving ${name}_${prefix}Hyperdrive`);
        deployments.add(name, `${prefix}Hyperdrive`, address);

        return hre.viem.getContractAt(`${prefix}Hyperdrive` as string, address);
    };
    hre.hyperdriveDeploy = {
        deployments,
        ensureDeployed,
        deployFactory,
        deployCoordinator: deployCoordinator as any,
        deployInstance: deployInstance as any,
    };
});
