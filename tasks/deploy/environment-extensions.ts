// To extend one of Hardhat's types, you need to import the module where it has been defined, and redeclare it.
import {
    ContractName,
    DeployContractConfig,
    deployContract,
} from "@nomicfoundation/hardhat-viem/types";
import { extendEnvironment } from "hardhat/config";
import "hardhat/types/config";
import "hardhat/types/runtime";
import { Deployments } from "./deployments";

import { types } from "hardhat/config";
import { ConfigurableTaskDefinition } from "hardhat/types/runtime";
import { PoolDeployConfig } from "./instances/schema";

export type HyperdriveDeployRuntimeOptions = {
    // Skip saving the deployment artifacts and data
    noSave?: boolean;
    // Skip verifying the deployment
    noVerify?: boolean;
    // Overwrite existing deployment artifacts (default=true)
    overwrite?: boolean;
    // Options to pass to `viem.deployContract`
    viemConfig?: DeployContractConfig;
};

export type HyperdriveDeployBaseTaskParams = HyperdriveDeployRuntimeOptions & {
    // Name of the primary contract to deploy
    //  - supporting contract names will be derived from it if applicable
    name: string;
};

export const HyperdriveDeployBaseTask = (task: ConfigurableTaskDefinition) =>
    task
        .addParam(
            "name",
            "name of the primary contract to deploy (supporting contract names will be derived from it)",
            undefined,
            types.string,
        )
        .addOptionalParam(
            "noSave",
            "skip saving deployment artifacts and data",
            false,
            types.boolean,
        )
        .addOptionalParam(
            "noVerify",
            "skip verifying the deployment",
            false,
            types.boolean,
        )
        .addOptionalParam(
            "overwrite",
            "overwrite deployment artifacts if they exist",
            false,
            types.boolean,
        );

export type HyperdriveDeployCoordinatorRuntimeOptions =
    HyperdriveDeployRuntimeOptions & {
        approveWithFactory?: boolean;
    };

export const HyperdriveDeployCoordinatorTask = (
    task: ConfigurableTaskDefinition,
) =>
    HyperdriveDeployBaseTask(task).addOptionalParam(
        "approveWithFactory",
        "attempt approving the HyperdriveDeployerCoordinator with its factory (will fail if deployer address is not governance)",
        false,
        types.boolean,
    );

declare module "hardhat/types/runtime" {
    interface HardhatRuntimeEnvironment {
        hyperdriveDeploy: {
            deployments: ReturnType<typeof Deployments.get>;
            deployContract: <T extends string>(
                name: string,
                contract: T,
                args: Parameters<typeof deployContract<T>>[1],
                options?: HyperdriveDeployRuntimeOptions,
            ) => ReturnType<typeof deployContract<T>>;
            deployFactory: (
                name: string,
                options?: HyperdriveDeployRuntimeOptions,
            ) => ReturnType<typeof deployContract<"HyperdriveFactory">>;
            deployCoordinator: <T extends string>(
                name: string,
                options?: HyperdriveDeployCoordinatorRuntimeOptions,
            ) => ReturnType<typeof deployContract<T>>;
            deployInstance: <T extends string>(
                name: string,
                options?: HyperdriveDeployRuntimeOptions,
            ) => ReturnType<typeof deployContract<T>>;
        };
    }
}

extendEnvironment((hre) => {
    let hhDeployments = hre.deployments;
    let deployments = Deployments.get();
    console.log(hre.config.networks[hre.network.name]);
    let config = hre.config.networks[hre.network.name].hyperdriveDeploy;
    let deployContract: typeof hre.hyperdriveDeploy.deployContract = async (
        name,
        contract,
        args,
        { noSave, noVerify, overwrite, viemConfig } = {},
    ) => {
        let artifact = hre.artifacts.readArtifactSync(contract);
        if (!overwrite && !!deployments.byNameSafe(name, hre.network.name)) {
            console.log(`skipping ${name}, found existing deployment`);
            return hre.viem.getContractAt(
                contract as string,
                deployments.byNameSafe(name, hre.network.name)!.address,
            );
        }
        console.log(`deploying ${name}...`);

        const instance = await hre.viem.deployContract(
            contract as ContractName<typeof contract>,
            args as any,
            viemConfig,
        );

        if (!noSave) {
            console.log(` - saving ${name}...`);
            deployments.add(name, contract, instance.address, hre.network.name);
            hhDeployments.save(name, {
                address: instance.address,
                args,
                abi: artifact.abi,
            });
        }

        if (!noVerify) {
            console.log(` - verifying ${name}...`);
            await hre.run("verify:verify", {
                address: instance.address,
                constructorArguments: args,
                network: hre.network.name,
            });
        }

        return hre.viem.getContractAt(contract as string, instance.address);
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
        let forwarder = await deployContract(
            name + "_FORWARDER",
            "ERC20ForwarderFactory",
            [],
            options,
        );
        let linkerHash = await forwarder.read.ERC20LINK_HASH();
        let args = [
            {
                ...(factoryConfig as Omit<
                    typeof factoryConfig,
                    "name" | "contract" | "setup"
                >),
                linkerFactory: forwarder.address,
                linkerCodeHash: linkerHash,
            },
            name,
        ];

        let instance = await deployContract(
            name,
            "HyperdriveFactory",
            args,
            options,
        );

        let setupFunction = config?.factories?.find(
            (f) => f.name === name,
        )?.setup;
        if (setupFunction) {
            console.log(` - running setup function for ${name}`);
            await setupFunction(hre);
        }
        return instance;
    };

    let deployCoordinator: typeof hre.hyperdriveDeploy.deployCoordinator =
        async (name, options) => {
            // Retrieve configuration for the coordinator by finding one with the same name/network
            // in the configuration file
            let coordinatorConfig = config?.coordinators?.find(
                (f) => f.name === name,
            );
            if (!coordinatorConfig) {
                throw new Error(
                    `no factory deploy configuration found for ${name}`,
                );
            }

            // Parse out the prefix from the contract so it can be used to name the various
            // components
            let contract = coordinatorConfig.contract;
            if (!contract.endsWith("HyperdriveDeployerCoordinator")) {
                throw new Error(
                    `unable to parse coordinator contract ${contract}`,
                );
            }
            let prefix = contract.replace("HyperdriveDeployerCoordinator", "");

            // // Lookup the LPMath contract and deploy it if not found
            // let lpMath = coordinatorConfig.lpMath;
            // let lpMathDeployment = deployments.byNameSafe(
            //     lpMath,
            //     hre.network.name,
            // );
            // let lpMathAddress;
            // if (!lpMathDeployment) {
            //     let { address } = await deployContract(
            //         `LPMath_${hre.network.name}`,
            //         "LPMath",
            //         [],
            //         options,
            //     );
            //     lpMathAddress = address;
            // } else {
            //     lpMathAddress = lpMathDeployment.address;
            // }

            // Parse the token field and deploy it if it is defined and not a string
            let token = coordinatorConfig.token;
            let tokenAddress;
            if (token && typeof token !== "string") {
                let tokenInstance = await deployContract(
                    token.name,
                    token.contract,
                    token.constructorArgs,
                    options,
                );
                // run the token setup function if it exists
                if (token.setup) await token.setup(hre);
                tokenAddress = tokenInstance.address;
            } else if (token) {
                tokenAddress = token as `0x${string}`;
            }

            // Deploy the HyperdriveCoreDeployer
            let coreDeployerContractName = `${prefix}HyperdriveCoreDeployer`;
            let coreDeployer = await deployContract(
                `${name}_${coreDeployerContractName}`,
                coreDeployerContractName,
                [],
                options,
            );

            // Obtain the associated HyperdriveFactory instance to obtain the number of targets
            let factoryDeployment = deployments.byName(
                coordinatorConfig.factoryName,
                hre.network.name,
            );
            let factory = await hre.viem.getContractAt(
                factoryDeployment.contract,
                factoryDeployment.address,
            );
            if (!factory.read.getNumberOfTargets)
                throw new Error(
                    `unable to get number of targets for factory ${coordinatorConfig.factoryName}`,
                );
            let targetCount =
                (await factory.read.getNumberOfTargets()) as bigint;

            // Deploy all of the target deployers and push them to the constructor arguments array
            // for the coordinator
            let args = [coreDeployer.address];
            for (let i = 0; i < targetCount; i++) {
                let targetContractName = `${prefix}Target${i}Deployer`;
                args.push(
                    (
                        await deployContract(
                            `${name}_${targetContractName}`,
                            targetContractName,
                            [],
                            {
                                ...options,
                                viemConfig: {
                                    ...options?.viemConfig,
                                    // libraries: { LPMath: lpMathAddress },
                                },
                            },
                        )
                    ).address,
                );
            }

            // Deploy the coordinator
            if (tokenAddress) args.push(tokenAddress);
            let coordinator = await deployContract(
                `${name}_${contract}`,
                contract,
                args,
                options,
            );
            if (coordinatorConfig.setup) {
                console.log(` - running setup function for ${name}`);
                await coordinatorConfig.setup(hre);
            }

            // Optionally register the coordinator with the factory if enabled and having the
            // correct permissions
            if (options?.approveWithFactory) {
                let factoryGovernanceAddress = await factory.read.governance();
                let deployer = (await hre.getNamedAccounts())["deployer"];
                if (deployer === factoryGovernanceAddress) {
                    console.log(`adding ${name}_${contract} to factory`);
                    await factory.write.addDeployerCoordinator([
                        coordinator.address,
                    ]);
                } else {
                    console.log(
                        `unable to add ${name}_${contract} to factory, deployer is not governance`,
                    );
                }
            }

            return coordinator;
        };

    let deployInstance: typeof hre.hyperdriveDeploy.deployInstance = async (
        name,
        options,
    ) => {
        // Retrieve configuration for the coordinator by finding one with the same name/network
        // in the configuration file
        let instanceConfig = config?.instances?.find((f) => f.name === name);
        if (!instanceConfig) {
            throw new Error(
                `no factory deploy configuration found for ${name}`,
            );
        }

        // Parse out the prefix from the contract so it can be used to name the various
        // components
        let contract = instanceConfig.contract;
        if (!contract.endsWith("Hyperdrive")) {
            throw new Error(`unable to parse coordinator contract ${contract}`);
        }
        let prefix = contract.replace("Hyperdrive", "");

        // Retrieve the HyperdriveDeployerCoordinator from the configuration and ensure it is
        // approved with its factory before continuing
        let coordinatorDeployment = deployments.byName(
            instanceConfig.coordinatorName,
            hre.network.name,
        );
        let coordinator = await hre.viem.getContractAt(
            `HyperdriveDeployerCoordinator`,
            coordinatorDeployment.address,
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

        // Parse the baseToken field and deploy it if it is defined and not a string
        let baseToken = instanceConfig.poolDeployConfig.baseToken;
        let baseTokenAddress;
        if (baseToken && typeof baseToken !== "string") {
            let tokenInstance = await deployContract(
                baseToken.name,
                baseToken.contract,
                baseToken.constructorArgs,
                options,
            );
            // run the token setup function if it exists
            if (baseToken.setup) await baseToken.setup(hre);
            baseTokenAddress = tokenInstance.address;
        } else if (baseToken) {
            baseTokenAddress = baseToken as `0x${string}`;
        }

        // Parse the vaultSharesToken field and deploy it if it is defined and not a string
        let vaultSharesToken = instanceConfig.poolDeployConfig.vaultSharesToken;
        let vaultSharesTokenAddress;
        if (vaultSharesToken && typeof vaultSharesToken !== "string") {
            let tokenInstance = await deployContract(
                vaultSharesToken.name,
                vaultSharesToken.contract,
                vaultSharesToken.constructorArgs,
                options,
            );
            // run the token setup function if it exists
            if (vaultSharesToken.setup) await vaultSharesToken.setup(hre);
            vaultSharesTokenAddress = tokenInstance.address;
        } else if (vaultSharesToken) {
            vaultSharesTokenAddress = vaultSharesToken as `0x${string}`;
        }

        // Add the linkerFactory and codeHash to the poolDeployConfig.
        let poolDeployConfig: PoolDeployConfig = {
            ...instanceConfig.poolDeployConfig,
            baseToken: baseTokenAddress!,
            vaultSharesToken: vaultSharesTokenAddress!,
            linkerFactory: await factory.read.linkerFactory(),
            linkerCodeHash: await factory.read.linkerCodeHash(),
        };

        // Obtain the number of targets from the coordinator
        let targetCount = await coordinator.read.getNumberOfTargets();

        // Obtain the factory deployment and artifacts to use for simulation and calling the
        // `deployTarget` function.
        let pc = await hre.viem.getPublicClient();
        let targets: `0x${string}`[] = [];
        for (let i = 0; i < targetCount; i++) {
            let contractName = `Target${i}`;
            let args = [
                instanceConfig.deploymentId,
                coordinator.address,
                poolDeployConfig,
                instanceConfig.options.extraData,
                instanceConfig.fixedAPR,
                instanceConfig.timestretchAPR,
                BigInt(i),
                instanceConfig.salt,
            ];

            // Simulate and deploy the target
            //  - Skip if deployment already exists and overwrite=false
            //  - Simulate the deployment of the target so we can obtain the address.
            if (
                !!deployments.byNameSafe(
                    `${name}_${contractName}`,
                    hre.network.name,
                ) &&
                !options?.overwrite
            ) {
                console.log(
                    `skipping ${name}_${contractName}, found existing deployment`,
                );
                targets.push(
                    deployments.byName(
                        `${name}_${contractName}`,
                        hre.network.name,
                    ).address,
                );
                continue;
            }
            let { result: address } = await factory.simulate.deployTarget(
                args as any,
                { gas: 1_500_000n, ...options?.viemConfig },
            );
            let tx = await factory.write.deployTarget(
                [
                    instanceConfig.deploymentId,
                    coordinator.address,
                    poolDeployConfig as any,
                    instanceConfig.options.extraData,
                    instanceConfig.fixedAPR,
                    instanceConfig.timestretchAPR,
                    BigInt(i),
                    instanceConfig.salt,
                ],
                { gas: 1_500_000n, ...options?.viemConfig },
            );
            await pc.waitForTransactionReceipt({ hash: tx });

            // Read the InitialVaultSharePrice from the coordinator's deployment struct since it is
            // it is the only additional field needed to convert PoolDeployConfig into the
            // instance's constructor arguments.
            let constructorArgs = {
                ...args,
                initialVaultSharePrice: (
                    await coordinator.read.deployments([
                        instanceConfig.deploymentId,
                    ])
                ).initialSharePrice,
            };

            // Save
            if (!options?.noSave) {
                deployments.add(
                    `${name}_${contractName}`,
                    contractName,
                    address,
                    hre.network.name,
                );
                hhDeployments.save(name, {
                    address: address,
                    args: constructorArgs,
                    abi: (await hre.artifacts.readArtifact(contractName)).abi,
                });
            }
            // Verify
            if (!options?.noVerify)
                await hre.run("verify:verify", {
                    address: address,
                    constructorArguments: constructorArgs,
                    network: hre.network.name,
                });

            // Read the deployment data for the target and add to the list
            targets.push(address);
        }

        // Deploy the Hyperdrive instance
        let hyperdriveConstructorArgs = [
            instanceConfig.deploymentId,
            coordinator.address,
            {
                ...poolDeployConfig,
                initialVaultSharePrice: await coordinator.read.deployments([
                    instanceConfig.deploymentId,
                ]),
            },
            instanceConfig.options.extraData,
            instanceConfig.fixedAPR,
            instanceConfig.timestretchAPR,
            {
                ...instanceConfig.options,
                destination:
                    instanceConfig.options.destination ??
                    (await hre.getNamedAccounts())["deployer"],
            },
            instanceConfig.salt,
        ];

        // Skip if deployment already exists and overwrite=false
        if (
            !!deployments.byNameSafe(`${name}_${contract}`, hre.network.name) &&
            !options?.overwrite
        ) {
            console.log(
                `skipping ${name}_${contract}, found existing deployment`,
            );
            return hre.viem.getContractAt(
                `${name}_${contract}`,
                deployments.byName(`${name}_${contract}`, hre.network.name)
                    .address,
            );
        }

        // Simulate and deploy
        let { result: address } = await factory.simulate.deployAndInitialize(
            hyperdriveConstructorArgs as any,
            {
                gas: 1_500_000n,
                ...options?.viemConfig,
            },
        );
        let tx = await factory.write.deployAndInitialize(
            hyperdriveConstructorArgs as any,
            { gas: 1_500_000n, ...options?.viemConfig },
        );
        await pc.waitForTransactionReceipt({ hash: tx });

        // Save
        if (!options?.noSave) {
            deployments.add(
                `${name}_${contract}`,
                contract,
                address,
                hre.network.name,
            );
            hhDeployments.save(name, {
                address: address,
                args: hyperdriveConstructorArgs,
                abi: (await hre.artifacts.readArtifact(contract)).abi,
            });
        }
        // Verify
        if (!options?.noVerify)
            await hre.run("verify:verify", {
                address: address,
                constructorArguments: hyperdriveConstructorArgs,
                network: hre.network.name,
            });

        return hre.viem.getContractAt(`${name}_${contract}`, address);
    };
    hre.hyperdriveDeploy = {
        deployments,
        deployContract,
        deployFactory,
        deployCoordinator,
        deployInstance: {} as any,
    };
});
