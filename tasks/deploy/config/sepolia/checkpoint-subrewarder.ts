import { Address, parseEther } from "viem";
import { HyperdriveCheckpointSubrewarderConfig } from "../../lib";
import { SEPOLIA_CHECKPOINT_REWARDER_NAME } from "./checkpoint-rewarder";

export const SEPOLIA_CHECKPOINT_SUBREWARDER_NAME = "CHECKPOINT_SUBREWARDER";

const FUNDING = parseEther("10000");

export const SEPOLIA_CHECKPOINT_SUBREWARDER: HyperdriveCheckpointSubrewarderConfig =
    {
        name: SEPOLIA_CHECKPOINT_SUBREWARDER_NAME,
        prepare: async (hre, options) => {
            // Deploy the base token.
            await hre.hyperdriveDeploy.ensureDeployed(
                "DAI",
                "ERC20Mintable",
                [
                    "DAI",
                    "DAI",
                    18,
                    (await hre.getNamedAccounts())["deployer"] as Address,
                    true,
                    parseEther("10000"),
                ],
                options,
            );
        },
        constructorArguments: async (hre) => [
            SEPOLIA_CHECKPOINT_SUBREWARDER_NAME,
            hre.hyperdriveDeploy.deployments.byName(
                SEPOLIA_CHECKPOINT_REWARDER_NAME,
            ).address,
            (await hre.getNamedAccounts())["deployer"] as Address,
            hre.hyperdriveDeploy.deployments.byName(`DELV Hyperdrive Registry`)
                .address,
            hre.hyperdriveDeploy.deployments.byName("DAI").address,
            parseEther("1"),
            parseEther("1"),
        ],
        setup: async (hre) => {
            // update the subrewarder in the rewarder contract
            let pc = await hre.viem.getPublicClient();
            let rewarder = await hre.viem.getContractAt(
                "HyperdriveCheckpointRewarder",
                hre.hyperdriveDeploy.deployments.byName(
                    SEPOLIA_CHECKPOINT_REWARDER_NAME,
                ).address,
            );
            let tx = await rewarder.write.updateSubrewarder([
                hre.hyperdriveDeploy.deployments.byName(
                    SEPOLIA_CHECKPOINT_SUBREWARDER_NAME,
                ).address,
            ]);
            await pc.waitForTransactionReceipt({ hash: tx });

            // get the base token
            let baseToken = await hre.viem.getContractAt(
                "ERC20Mintable",
                hre.hyperdriveDeploy.deployments.byName("DAI").address,
            );

            // mint some tokens for checkpoint rewards
            tx = await baseToken.write.mint([FUNDING]);
            await pc.waitForTransactionReceipt({ hash: tx });

            // approve the subrewarder for the contribution
            tx = await baseToken.write.approve([
                hre.hyperdriveDeploy.deployments.byName(
                    SEPOLIA_CHECKPOINT_SUBREWARDER_NAME,
                ).address,
                FUNDING,
            ]);
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    };
