import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { task, types } from "hardhat/config";
import { z } from "zod";
import { DeployInstanceParams, zInstanceDeployConfig } from "./schema";

dayjs.extend(duration);

// Set the base token to always be the ETH letant.
export let zEzETHInstanceDeployConfig = zInstanceDeployConfig
    .transform((v) => ({
        ...v,
        poolDeployConfig: {
            ...v.poolDeployConfig,
            baseToken:
                "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE" as `0x${string}`,
        },
    }))
    .superRefine((v, c) => {
        // Contribution via the base token (ETH) are not allowed for EzETH.
        if (v.options.asBase) {
            c.addIssue({
                code: z.ZodIssueCode.custom,
                message:
                    "`options.asBase` must be set to false for EzETH Hyperdrive instances.",
                path: ["options.asBase"],
            });
        }
    });

export type EzETHInstanceDeployConfigInput = z.input<
    typeof zEzETHInstanceDeployConfig
>;
export type EzETHInstanceDeployConfig = z.infer<
    typeof zEzETHInstanceDeployConfig
>;

task("deploy:instances:ezeth", "deploys the EzETH deployment coordinator")
    .addParam("name", "name of the instance to deploy", undefined, types.string)
    .addOptionalParam("admin", "admin address", undefined, types.string)
    .setAction(
        async (
            { name, admin }: DeployInstanceParams,
            {
                deployments,
                run,
                network,
                viem,
                getNamedAccounts,
                config: hardhatConfig,
            },
        ) => {
            console.log(`starting hyperdrive deployment ${name}`);
            let deployer = (await getNamedAccounts())[
                "deployer"
            ] as `0x${string}`;
            // Read and parse the provided configuration file
            let config = hardhatConfig.networks[
                network.name
            ].instances?.ezeth?.find((i) => i.name === name);
            if (!config)
                throw new Error(
                    `unable to find instance for network ${network.name} with name ${name}`,
                );

            // Set 'admin' to the deployer address if not specified via param
            if (!admin?.length) admin = deployer;

            // Get the ezeth token address from the deployer coordinator
            let coordinatorAddress = (
                await deployments.get("EzETHHyperdriveDeployerCoordinator")
            ).address as `0x${string}`;
            let coordinator = await viem.getContractAt(
                "EzETHHyperdriveDeployerCoordinator",
                coordinatorAddress,
            );
            let ezeth = await viem.getContractAt(
                "MockEzEthPool",
                await coordinator.read.ezETH(),
            );
            config.poolDeployConfig.vaultSharesToken = ezeth.address;

            // Ensure the deployer has sufficiet funds for the contribution.
            let pc = await viem.getPublicClient();
            if (
                (await pc.getBalance({ address: deployer })) <
                config.contribution
            )
                throw new Error("insufficient ETH balance for contribution");

            // Obtain shares for the contribution.
            await ezeth.write.submit([deployer], {
                value: config.contribution,
            });

            // Ensure the deployer has approved the deployer coordinator for ezeth shares.
            let allowance = await ezeth.read.allowance([
                deployer,
                coordinatorAddress,
            ]);
            if (allowance < config.contribution) {
                console.log("approving coordinator for contribution...");
                await ezeth.write.approve([
                    coordinatorAddress,
                    config.contribution * 2n,
                ]);
            }

            // Deploy the targets and hyperdrive instance
            await run("deploy:instances:shared", { prefix: "ezeth", name });
        },
    );
