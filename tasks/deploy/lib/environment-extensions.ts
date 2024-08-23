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
import { Address, ContractConstructorArgs } from "viem";
import { ETH_ADDRESS } from "./constants";
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
            deployCheckpointRewarder: (
                name: string,
                options?: HyperdriveDeployRuntimeOptions,
            ) => Promise<
                GetContractReturnType<
                    ArtifactsMap["HyperdriveCheckpointRewarder"]["abi"]
                >
            >;
            deployCheckpointSubrewarder: (
                name: string,
                options?: HyperdriveDeployRuntimeOptions,
            ) => Promise<
                GetContractReturnType<
                    ArtifactsMap["HyperdriveCheckpointSubrewarder"]["abi"]
                >
            >;
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

        // Deploy libraries if necessary and link them to the target bytecode.
        let artifact = await hre.artifacts.readArtifact(contract);
        let libraries: Record<string, `0x${string}`> = {};
        for (let libraryFilename in artifact.linkReferences) {
            for (let libraryName in artifact.linkReferences[
                libraryFilename as keyof typeof artifact.linkReferences
            ] as any) {
                let libraryAddress = (
                    await ensureDeployed(libraryName, libraryName as any, [], {
                        viemConfig,
                    })
                ).address;
                libraries[libraryName] = libraryAddress;
            }
        }

        const instance = await hre.viem.deployContract(
            contract as ContractName<typeof contract>,
            args as any,
            { ...viemConfig, libraries, gas: 6_750_000n },
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

    let deployCheckpointRewarder: typeof hre.hyperdriveDeploy.deployCheckpointRewarder =
        async (name, options) => {
            let checkpointRewarderConfig = config?.checkpointRewarders?.find(
                (r) => r.name === name,
            );
            if (!checkpointRewarderConfig) {
                throw new Error(
                    `no checkpoint rewarder deploy configuration found for ${name}`,
                );
            }

            // run prepare function if present
            if (
                !deployments.byNameSafe(name) &&
                checkpointRewarderConfig.prepare
            ) {
                console.log(`running prepare for ${name} ...`);
                await checkpointRewarderConfig.prepare(hre, options ?? {});
            }

            // deploy the checkpoint rewarder
            let checkpointRewarder = await ensureDeployed(
                name,
                "HyperdriveCheckpointRewarder",
                await evaluateValueOrHREFn(
                    checkpointRewarderConfig.constructorArguments,
                    hre,
                    options,
                ),
                options,
            );

            // run the setup function if present
            if (checkpointRewarderConfig.setup) {
                console.log(` - running setup function for ${name}`);
                await checkpointRewarderConfig.setup(hre, options ?? {});
            }
            return checkpointRewarder;
        };

    let deployCheckpointSubrewarder: typeof hre.hyperdriveDeploy.deployCheckpointSubrewarder =
        async (name, options) => {
            let checkpointSubrewarderConfig =
                config?.checkpointSubrewarders?.find((r) => r.name === name);
            if (!checkpointSubrewarderConfig) {
                throw new Error(
                    `no checkpoint subrewarder deploy configuration found for ${name}`,
                );
            }

            // run prepare function if present
            if (
                !deployments.byNameSafe(name) &&
                checkpointSubrewarderConfig.prepare
            ) {
                console.log(`running prepare for ${name} ...`);
                await checkpointSubrewarderConfig.prepare(hre, options ?? {});
            }

            // deploy the checkpoint subrewarder
            let checkpointSubrewarder = await ensureDeployed(
                name,
                "HyperdriveCheckpointSubrewarder",
                await evaluateValueOrHREFn(
                    checkpointSubrewarderConfig.constructorArguments,
                    hre,
                    options,
                ),
                options,
            );

            // run the setup function if present
            if (checkpointSubrewarderConfig.setup) {
                console.log(` - running setup function for ${name}`);
                await checkpointSubrewarderConfig.setup(hre, options ?? {});
            }
            return checkpointSubrewarder;
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
        let pc = await hre.viem.getPublicClient();
        let targets: Address[] = [];
        let targetCount = await evaluateValueOrHREFn(
            coordinatorConfig.targetCount,
            hre,
            options,
        );
        for (let i = 0; i < targetCount; i++) {
            let targetContractName = `${prefix}Target${i}Deployer`;

            let target = await ensureDeployed(
                `${name}_${targetContractName}`,
                targetContractName as any,
                extraArgs ?? [],
                options,
            );
            targets.push(target.address);
        }

        // Deploy the coordinator
        let args = [
            coordinatorConfig.name,
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
                { gas: 6_750_000n, ...options.viemConfig },
            );
            let tx = await factory.write.deployTarget(args as any, {
                gas: 6_750_000n,
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
        let deployOptions = await evaluateValueOrHREFn(
            instanceConfig.options,
            hre,
            options,
        );
        let args = [
            deploymentId,
            coordinatorAddress,
            instanceConfig.name,
            poolDeployConfig,
            extraData,
            instanceConfig.contribution,
            fixedAPR,
            timestretchAPR,
            deployOptions,
            salt,
        ];

        // Simulate and deploy
        console.log(`deploying ${name}_${prefix}Hyperdrive`);
        let value = 0n;
        if (
            poolDeployConfig.baseToken === ETH_ADDRESS &&
            deployOptions.asBase
        ) {
            value = instanceConfig.contribution;
        }
        let { result: address } = await factory.simulate.deployAndInitialize(
            args as any,
            { gas: 6_750_000n, value },
        );
        let tx = await factory.write.deployAndInitialize(args as any, {
            gas: 6_750_000n,
            value,
        });
        await pc.waitForTransactionReceipt({ hash: tx });

        // Save
        console.log(` - Saving ${name}_${prefix}Hyperdrive`);
        deployments.add(name, `${prefix}Hyperdrive`, address);

        // NOTE: There's a bug in hardhat that results in receiving a garbage address for Target0.
        //       Because of this, we need to retrieve the correct address from the Hyperdrive instance once deployed.
        deployments.add(
            `${name}_${prefix}Target0`,
            `${prefix}Target0`,
            await (
                await hre.viem.getContractAt("IHyperdrive", address)
            ).read.target0(),
        );
        return hre.viem.getContractAt(`${prefix}Hyperdrive` as string, address);
    };
    hre.hyperdriveDeploy = {
        deployments,
        ensureDeployed,
        deployCheckpointRewarder,
        deployCheckpointSubrewarder,
        deployFactory,
        deployCoordinator: deployCoordinator as any,
        deployInstance: deployInstance as any,
    };
});
