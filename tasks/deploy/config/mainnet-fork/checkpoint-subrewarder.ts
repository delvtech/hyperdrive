import { Address, formatEther, parseEther } from "viem";
import {
    HyperdriveCheckpointSubrewarderConfig,
    MAINNET_DAI_ADDRESS,
} from "../../lib";
import { MAINNET_FORK_CHECKPOINT_REWARDER_NAME } from "./checkpoint-rewarder";

const MAINNET_FORK_CHECKPOINT_SUBREWARDER_NAME = "CHECKPOINT_SUBREWARDER";

const FUNDING = parseEther("10000");

export const MAINNET_FORK_CHECKPOINT_SUBREWARDER: HyperdriveCheckpointSubrewarderConfig =
    {
        name: MAINNET_FORK_CHECKPOINT_SUBREWARDER_NAME,
        constructorArguments: async (hre) => [
            MAINNET_FORK_CHECKPOINT_SUBREWARDER_NAME,
            hre.hyperdriveDeploy.deployments.byName(
                MAINNET_FORK_CHECKPOINT_REWARDER_NAME,
            ).address,
            (await hre.getNamedAccounts())["deployer"] as Address,
            hre.hyperdriveDeploy.deployments.byName("DELV Hyperdrive Registry")
                .address,
            MAINNET_DAI_ADDRESS,
            parseEther("1"),
            parseEther("1"),
        ],
        setup: async (hre) => {
            // update the subrewarder in the rewarder contract
            let pc = await hre.viem.getPublicClient();
            let rewarder = await hre.viem.getContractAt(
                "HyperdriveCheckpointRewarder",
                hre.hyperdriveDeploy.deployments.byName(
                    MAINNET_FORK_CHECKPOINT_REWARDER_NAME,
                ).address,
            );
            let tx = await rewarder.write.updateSubrewarder([
                hre.hyperdriveDeploy.deployments.byName(
                    MAINNET_FORK_CHECKPOINT_SUBREWARDER_NAME,
                ).address,
            ]);
            await pc.waitForTransactionReceipt({ hash: tx });

            // get the base token
            let baseToken = await hre.viem.getContractAt(
                "ERC20Mintable",
                MAINNET_DAI_ADDRESS,
            );

            // mint some tokens for checkpoint rewards
            await hre.run("fork:mint-dai", {
                amount: formatEther(FUNDING),
                address: (await hre.getNamedAccounts())["deployer"],
            });

            // approve the subrewarder for the contribution
            tx = await baseToken.write.approve([
                hre.hyperdriveDeploy.deployments.byName(
                    MAINNET_FORK_CHECKPOINT_SUBREWARDER_NAME,
                ).address,
                FUNDING,
            ]);
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    };
