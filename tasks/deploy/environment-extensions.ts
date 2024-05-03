// To extend one of Hardhat's types, you need to import the module where it has been defined, and redeclare it.
import { ContractName } from "@nomicfoundation/hardhat-viem/types";
import { extendEnvironment } from "hardhat/config";
import { type ArtifactsMap } from "hardhat/types/artifacts";
import "hardhat/types/config";
import "hardhat/types/runtime";
import { Address, ContractConstructorArgs, GetContractReturnType } from "viem";
import { Deployments } from "./deployments";
import { InstanceDeployConfig, PoolDeployConfig } from "./instances/schema";
import { DeploySaveParams } from "./save";

export type HyperdriveCategories =
    | "ERC4626"
    | "StETH"
    | "RETH"
    | "LsETH"
    | "EzETH";

export type HyperdriveTargetIndices = "0" | "1" | "2" | "3" | "4";

declare module "hardhat/types/runtime" {
    interface HardhatRuntimeEnvironment {
        hyperdrive: {
            deployContract: <T extends keyof ArtifactsMap>(
                contract: T,
                name: ContractName<T>,
                args: ContractConstructorArgs<ArtifactsMap[T]["abi"]>,
            ) => Promise<GetContractReturnType<ArtifactsMap[T]["abi"]>>;
            deployPool: <T extends `${HyperdriveCategories}Hyperdrive`>(
                coordinator: Address,
                contract: T,
                name: ContractName<T>,
                args: InstanceDeployConfig,
            ) => Promise<GetContractReturnType<ArtifactsMap[T]["abi"]>>;
        };
    }
}

extendEnvironment((hre) => {
    hre.hyperdrive = {
        deployContract: async (contract, name, args) => {
            const instance = await hre.viem.deployContract(
                contract as any,
                args as any,
                {},
            );
            await hre.run("deploy:save", {
                abi: instance.abi,
                address: instance.address,
                args,
                contract,
                name,
            } as DeploySaveParams);
            return instance as unknown as GetContractReturnType<
                ArtifactsMap[typeof contract]["abi"]
            >;
        },
        deployPool: async (coordinator, contract, name, args) => {
            const factory = await hre.viem.getContractAt(
                "HyperdriveFactory",
                Deployments.get().byName("HyperdriveFactory", hre.network.name)
                    .address,
                {},
            );
            const coordinatorContract = await hre.viem.getContractAt(
                "HyperdriveDeployerCoordinator",
                coordinator,
                {},
            );

            let poolDeployConfig = {
                ...args.poolDeployConfig,
                linkerFactory: await factory.read.linkerFactory(),
                linkerCodeHash: await factory.read.linkerCodeHash(),
            } as PoolDeployConfig;
            let pc = await hre.viem.getPublicClient();
            let initialVaultSharePrice;
            for (let i = 0; i < 5; i++) {
                let { result: address } = await factory.simulate.deployTarget([
                    args.deploymentId,
                    coordinatorContract.address,
                    {
                        ...args.poolDeployConfig,
                        linkerFactory: await factory.read.linkerFactory(),
                        linkerCodeHash: await factory.read.linkerCodeHash(),
                    } as PoolDeployConfig,
                    args.options.extraData,
                    args.fixedAPR,
                    args.timestretchAPR,
                    BigInt(i),
                    args.salt,
                ]);
                let tx = await factory.write.deployTarget([
                    args.deploymentId,
                    coordinatorContract.address,
                    {
                        ...args.poolDeployConfig,
                        linkerFactory: await factory.read.linkerFactory(),
                        linkerCodeHash: await factory.read.linkerCodeHash(),
                    } as PoolDeployConfig,
                    args.options.extraData,
                    args.fixedAPR,
                    args.timestretchAPR,
                    BigInt(i),
                    args.salt,
                ]);
                await pc.waitForTransactionReceipt({
                    hash: tx,
                    confirmations: hre.network.live ? 3 : 1,
                });
                let targetContract = await hre.viem.getContractAt(
                    `HyperdriveTarget${i}`,
                    address,
                );
                initialVaultSharePrice = (
                    await coordinatorContract.read.deployments([
                        args.deploymentId,
                    ])
                ).initialSharePrice;
                await hre.run("deploy:save", {
                    abi: targetContract.abi,
                    address: targetContract.address,
                    args: [
                        {
                            ...args,
                            initialVaultSharePrice,
                        },
                    ],
                    contract,
                    name,
                } as DeploySaveParams);
            }

            let deployer = (await hre.getNamedAccounts())["deployer"];
            let { result: hyperdriveAddress } =
                await factory.simulate.deployAndInitialize([
                    args.deploymentId,
                    coordinator,
                    poolDeployConfig,
                    args.options.extraData,
                    args.contribution,
                    args.fixedAPR,
                    args.timestretchAPR,
                    {
                        ...args.options,
                        destination:
                            (args.options.destination as Address) ??
                            (deployer as string),
                    },
                    args.salt,
                ]);
            let hyperdriveTx = await factory.write.deployAndInitialize([
                args.deploymentId,
                coordinator,
                poolDeployConfig,
                args.options.extraData,
                args.contribution,
                args.fixedAPR,
                args.timestretchAPR,
                {
                    ...args.options,
                    destination:
                        (args.options.destination as Address) ??
                        (deployer as string),
                },
                args.salt,
            ]);
            await pc.waitForTransactionReceipt({ hash: hyperdriveTx });
            let hyperdrive = await hre.viem.getContractAt(
                contract as any,
                hyperdriveAddress,
            );

            await hre.run("deploy:save", {
                abi: hyperdrive.abi,
                address: hyperdrive.address,
                args: [
                    {
                        ...args,
                        initialVaultSharePrice,
                    },
                ],
                contract,
                name,
            } as DeploySaveParams);
            return hyperdrive as unknown as GetContractReturnType<
                ArtifactsMap[typeof contract]["abi"]
            >;
        },
    };
});

// type depconf<T extends string> = {
// [K in keyof]
// }
