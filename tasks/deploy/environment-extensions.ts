// To extend one of Hardhat's types, you need to import the module where it has been defined, and redeclare it.
import {
    ContractName,
    deployContract,
} from "@nomicfoundation/hardhat-viem/types";
import { extendEnvironment, types } from "hardhat/config";
import { Artifact } from "hardhat/types/artifacts";
import "hardhat/types/config";
import "hardhat/types/runtime";
import { ConfigurableTaskDefinition } from "hardhat/types/runtime";
import type * as viemT from "viem";
import { isHex } from "viem";
import { Deployments } from "./deployments";

export type HyperdriveDeployRuntimeOptions = {
    // Skip saving the deployment artifacts and data
    noSave?: boolean;
    // Skip verifying the deployment
    noVerify?: boolean;
    // Overwrite existing deployment artifacts (default=true)
    overwrite?: boolean;
    // Options to pass to `viem.deployContract`
    viemConfig?: {
        gas?: bigint;
        gasPrice?: bigint;
        maxFeePerGas?: bigint;
        maxPriorityFeePerGas?: bigint;
    };
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
    let config = hre.config.networks[hre.network.name].hyperdriveDeploy;
    let deployContract: typeof hre.hyperdriveDeploy.deployContract = async (
        name,
        contract,
        args,
        { noSave, noVerify, overwrite, viemConfig } = {},
    ) => {
        let artifact = await hre.artifacts.readArtifact(contract);
        if (!overwrite && !!deployments.byNameSafe(name, hre.network.name)) {
            console.log(`skipping ${name}, found existing deployment`);
            return await hre.viem.getContractAt(
                contract as string,
                deployments.byNameSafe(name, hre.network.name)!.address,
            );
        }
        console.log(`deploying ${name}...`);

        const instance = await hre.viem.deployContract(
            contract as ContractName<typeof contract>,
            args as any,
            { ...viemConfig, gas: 15_000_000n },
        );

        if (!noSave) {
            console.log(` - saving ${name}...`);
            deployments.add(name, contract, instance.address, hre.network.name);
            await hhDeployments.save(name, {
                address: instance.address,
                args,
                ...artifact,
            });
        }

        if (!noVerify && hre.network.live) {
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

            // Lookup the LPMath contract and ensure it's deployed.
            // - Generate the link object from the artifact for use later
            let lpMath = coordinatorConfig.lpMath;
            let lpMathDeployment = deployments.byNameSafe(
                lpMath,
                hre.network.name,
            );
            let lpMathAddress;
            if (!lpMathDeployment) {
                let { address } = await deployContract(
                    `LPMath_${hre.network.name}`,
                    "LPMath",
                    [],
                    options,
                );
                lpMathDeployment = deployments.byNameSafe(
                    `LPMath_${hre.network.name}`,
                    hre.network.name,
                );
                lpMathAddress = address;
            } else {
                lpMathAddress = lpMathDeployment.address;
            }
            let lpMathArtifact = await hre.artifacts.readArtifact(
                lpMathDeployment?.contract!,
            );
            let libraries: Link[] = [
                {
                    address: lpMathAddress,
                    sourceName: lpMathArtifact.sourceName,
                    libraryName: "LPMath",
                },
            ];

            // Parse the token field and deploy it if it is defined and not a string
            let token = coordinatorConfig.token;
            let tokenAddress;
            if (token && typeof token !== "string") {
                if (token.deploy) {
                    await token.deploy(hre);
                }
                let tokenDeployment = deployments.byName(
                    token.name,
                    hre.network.name,
                );
                tokenAddress = tokenDeployment.address;
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

            // Obtain the associated HyperdriveFactory instance
            let factoryDeployment = deployments.byName(
                coordinatorConfig.factoryName,
                hre.network.name,
            );
            let factory = await hre.viem.getContractAt(
                factoryDeployment.contract,
                factoryDeployment.address,
            );

            // Begin assembling the coordinator constructor args
            let coordinatorArgs = [factory.address, coreDeployer.address];

            // Deploy all of the target deployers and push them to the constructor arguments array
            // for the coordinator
            let deployer = (await hre.getNamedAccounts())[
                "deployer"
            ]! as `0x${string}`;
            let wc = await hre.viem.getWalletClient(deployer);
            let pc = await hre.viem.getPublicClient();
            for (let i = 0; i < coordinatorConfig.targetCount; i++) {
                let targetContractName = `${prefix}Target${i}Deployer`;

                // retrieve from deployments and continue if it already exists
                let targetDeployment = deployments.byNameSafe(
                    `${name}_${targetContractName}`,
                    hre.network.name,
                );
                if (!options?.overwrite && !!targetDeployment) {
                    coordinatorArgs.push(targetDeployment.address);
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
                    args: [],
                    gas: 15_000_000n,
                });
                let receipt = await pc.waitForTransactionReceipt({ hash: tx });
                let address = receipt.contractAddress!;

                // handle options
                if (!options?.noSave) {
                    console.log(` - saving ${name}...`);
                    deployments.add(
                        `${name}_${targetContractName}`,
                        targetContractName,
                        address,
                        hre.network.name,
                    );
                    await hhDeployments.save(name, {
                        address: address,
                        args: [],
                        abi: targetArtifact.abi,
                    });
                }
                if (!options?.noVerify && hre.network.live) {
                    console.log(` - verifying ${name}...`);
                    await hre.run("verify:verify", {
                        address: address,
                        constructorArguments: [],
                        network: hre.network.name,
                    });
                }

                coordinatorArgs.push(address);
            }

            // Deploy the coordinator
            if (tokenAddress) coordinatorArgs.push(tokenAddress);
            let coordinator = await deployContract(
                `${name}_${contract}`,
                contract,
                coordinatorArgs,
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
            // run the token setup function if it exists
            if (baseToken.deploy) await baseToken.deploy(hre);
            let tokenDeployment = deployments.byName(
                baseToken.name,
                hre.network.name,
            );
            baseTokenAddress = tokenDeployment.address;
        } else if (baseToken) {
            baseTokenAddress = baseToken as `0x${string}`;
        }

        // Parse the vaultSharesToken field and deploy it if it is defined and not a string
        let vaultSharesToken = instanceConfig.poolDeployConfig.vaultSharesToken;
        let vaultSharesTokenAddress;
        if (vaultSharesToken && typeof vaultSharesToken !== "string") {
            // run the token deploy function if it exists
            if (vaultSharesToken.deploy) await vaultSharesToken.deploy(hre);
            let tokenDeployment = deployments.byName(
                vaultSharesToken.name,
                hre.network.name,
            );
            vaultSharesTokenAddress = tokenDeployment.address;
        } else if (vaultSharesToken) {
            vaultSharesTokenAddress = vaultSharesToken as `0x${string}`;
        }

        // Add the linkerFactory and codeHash to the poolDeployConfig.
        let poolDeployConfig = {
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
        let initialVaultSharePrice;
        for (let i = 0; i < targetCount; i++) {
            let contractName = `${prefix}Target${i}`;
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
                { gas: 15_000_000n, ...options?.viemConfig },
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
                { gas: 15_000_000n },
            );
            await pc.waitForTransactionReceipt({ hash: tx });

            // Read the InitialVaultSharePrice from the coordinator's deployment struct since it is
            // it is the only additional field needed to convert PoolDeployConfig into the
            // instance's constructor arguments.
            initialVaultSharePrice = (
                await coordinator.read.deployments([
                    instanceConfig.deploymentId,
                ])
            ).initialSharePrice;

            // Save
            if (!options?.noSave) {
                deployments.add(
                    `${name}_${contractName}`,
                    contractName,
                    address,
                    hre.network.name,
                );
                await hhDeployments.save(name, {
                    address: address,
                    args: [{ ...poolDeployConfig, initialVaultSharePrice }],
                    abi: (await hre.artifacts.readArtifact(contractName)).abi,
                });
            }
            // Verify
            if (!options?.noVerify && hre.network.live)
                await hre.run("verify:verify", {
                    address: address,
                    constructorArguments: [
                        { ...poolDeployConfig, initialVaultSharePrice },
                    ],
                    network: hre.network.name,
                });

            // Read the deployment data for the target and add to the list
            targets.push(address);
        }

        // Deploy the Hyperdrive instance
        let hyperdriveConstructorArgs = [
            instanceConfig.deploymentId,
            coordinator.address,
            poolDeployConfig,
            instanceConfig.options.extraData,
            instanceConfig.contribution,
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
                gas: 15_000_000n,
            },
        );
        let tx = await factory.write.deployAndInitialize(
            hyperdriveConstructorArgs as any,
            { gas: 15_000_000n },
        );
        await pc.waitForTransactionReceipt({ hash: tx });

        // Save
        let abi = (await hre.artifacts.readArtifact(contract)).abi;
        if (!options?.noSave) {
            deployments.add(
                `${name}_${contract}`,
                contract,
                address,
                hre.network.name,
            );
            await hhDeployments.save(name, {
                address: address,
                args: hyperdriveConstructorArgs,
                abi,
            });
        }
        // Verify
        if (!options?.noVerify && hre.network.live)
            await hre.run("verify:verify", {
                address: address,
                constructorArguments: hyperdriveConstructorArgs,
                network: hre.network.name,
            });

        return hre.viem.getContractAt(contract, address);
    };
    hre.hyperdriveDeploy = {
        deployments,
        deployContract,
        deployFactory,
        deployCoordinator,
        deployInstance,
    };
});

export interface Link {
    sourceName: string;
    libraryName: string;
    address: string;
}

async function linkBytecode(
    artifact: Artifact,
    libraries: Link[],
): Promise<viemT.Hex> {
    const { isHex } = await import("viem");
    let bytecode = artifact.bytecode;

    // TODO: measure performance impact
    for (const { sourceName, libraryName, address } of libraries) {
        const linkReferences = artifact.linkReferences[sourceName][libraryName];
        for (const { start, length } of linkReferences) {
            bytecode =
                bytecode.substring(0, 2 + start * 2) +
                address.substring(2) +
                bytecode.substring(2 + (start + length) * 2);
        }
    }

    return isHex(bytecode) ? bytecode : `0x${bytecode}`;
}
