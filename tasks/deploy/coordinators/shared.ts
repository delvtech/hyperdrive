import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { subtask, types } from "hardhat/config";
import { DeploySaveParams } from "../save";
import { validHyperdrivePrefixes } from "../types";
dayjs.extend(duration);

export type DeployCoordinatorsBaseParams = {
    prefix: keyof typeof validHyperdrivePrefixes;
};

/**
 * Deploys the core deployer and all targets for a deployer coordinator
 * - Unfortunately, by parameterizing the contract names we lose some type-checking ability
 */
subtask(
    "deploy:coordinators:shared",
    "shared deployment steps for deployer coordinators",
)
    .addParam(
        "prefix",
        "contract prefix for the coordinator",
        undefined,
        types.string,
    )
    .setAction(
        async ({ prefix }: DeployCoordinatorsBaseParams, { run, viem }) => {
            let prefixValue = validHyperdrivePrefixes[prefix];
            // Deploy the core deployer
            console.log(`deploying ${prefixValue}HyperdriveCoreDeployer...`);
            let core = await viem.deployContract(
                `${prefixValue}HyperdriveCoreDeployer` as any,
            );
            await run("deploy:save", {
                name: `${prefixValue}HyperdriveCoreDeployer`,
                args: [],
                abi: core.abi,
                address: core.address,
                contract: `${prefixValue}HyperdriveCoreDeployer`,
            } as DeploySaveParams);

            // Deploy the targets
            let targets: `0x${string}`[] = [];
            for (let i = 0; i < 5; i++) {
                console.log(`deploying ${prefixValue}Target${i}Deployer...`);
                let contract = await viem.deployContract(
                    `${prefixValue}Target${i}Deployer`,
                );
                targets.push(contract.address);
                await run("deploy:save", {
                    name: `${prefixValue}Target${i}Deployer`,
                    args: [],
                    abi: contract.abi,
                    address: contract.address,
                    contract: `${prefixValue}Target${i}Deployer`,
                } as DeploySaveParams);
            }
        },
    );
