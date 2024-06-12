import { parseEther } from "viem";
import { HyperdriveCheckpointSubrewarderConfig } from "../../lib";

const FUNDING = parseEther("10000");

export const SEPOLIA_CHECKPOINT_SUBREWARDER: HyperdriveCheckpointSubrewarderConfig =
    {
        name: "CHECKPOINT_SUBREWARDER",
        prepare: async (hre, options) => {
            // Deploy the base token.
            await hre.hyperdriveDeploy.ensureDeployed(
                "DAI",
                "ERC20Mintable",
                [
                    "DAI",
                    "DAI",
                    18,
                    "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
                    true,
                    parseEther("10000"),
                ],
                options,
            );
        },
        constructorArguments: async (hre) => [
            "CHECKPOINT_SUBREWARDER",
            hre.hyperdriveDeploy.deployments.byName("CHECKPOINT_REWARDER")
                .address,
            "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
            hre.hyperdriveDeploy.deployments.byName("SEPOLIA_REGISTRY").address,
            hre.hyperdriveDeploy.deployments.byName("DAI").address,
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
                hre.hyperdriveDeploy.deployments.byName("DAI").address,
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
