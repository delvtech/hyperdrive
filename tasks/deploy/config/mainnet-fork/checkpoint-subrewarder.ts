import { parseEther } from "viem";
import {
    HyperdriveCheckpointSubrewarderConfig,
    MAINNET_DAI_ADDRESS,
} from "../../lib";

const FUNDING = parseEther("10000");

export const MAINNET_FORK_CHECKPOINT_SUBREWARDER: HyperdriveCheckpointSubrewarderConfig =
    {
        name: "CHECKPOINT_SUBREWARDER",
        constructorArguments: async (hre) => [
            "CHECKPOINT_SUBREWARDER",
            hre.hyperdriveDeploy.deployments.byName("CHECKPOINT_REWARDER")
                .address,
            "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
            hre.hyperdriveDeploy.deployments.byName("MAINNET_FORK_REGISTRY")
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
                hre.hyperdriveDeploy.deployments.byName("CHECKPOINT_REWARDER")
                    .address,
            );
            let tx = await rewarder.write.updateSubrewarder([
                hre.hyperdriveDeploy.deployments.byName(
                    "CHECKPOINT_SUBREWARDER",
                ).address,
            ]);
            await pc.waitForTransactionReceipt({ hash: tx });

            // get the base token
            let baseToken = await hre.viem.getContractAt(
                "ERC20Mintable",
                MAINNET_DAI_ADDRESS,
            );

            // mint some tokens for checkpoint rewards
            tx = await baseToken.write.mint([FUNDING]);
            await pc.waitForTransactionReceipt({ hash: tx });

            // approve the subrewarder for the contribution
            tx = await baseToken.write.approve([
                hre.hyperdriveDeploy.deployments.byName(
                    "CHECKPOINT_SUBREWARDER",
                ).address,
                FUNDING,
            ]);
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    };
