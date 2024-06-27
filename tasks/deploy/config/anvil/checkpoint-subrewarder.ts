import { Address, maxUint256, parseEther } from "viem";
import { HyperdriveCheckpointSubrewarderConfig } from "../../lib";

let { env } = process;

const FUNDING = parseEther("10000");

export const ANVIL_CHECKPOINT_SUBREWARDER: HyperdriveCheckpointSubrewarderConfig =
    {
        name: "CHECKPOINT_SUBREWARDER",
        prepare: async (hre, options) => {
            // Deploy the base token.
            let baseToken = await hre.hyperdriveDeploy.ensureDeployed(
                "BASE_TOKEN",
                "ERC20Mintable",
                [
                    env.BASE_TOKEN_NAME!,
                    env.BASE_TOKEN_SYMBOL!,
                    parseInt(env.BASE_TOKEN_DECIMALS!),
                    env.ADMIN! as Address,
                    env.IS_COMPETITION_MODE! === "true",
                    maxUint256,
                ],
                options,
            );
        },
        constructorArguments: async (hre) => [
            "CHECKPOINT_SUBREWARDER",
            hre.hyperdriveDeploy.deployments.byName("CHECKPOINT_REWARDER")
                .address,
            "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
            hre.hyperdriveDeploy.deployments.byName("DELV Hyperdrive Registry")
                .address,
            hre.hyperdriveDeploy.deployments.byName("BASE_TOKEN").address,
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
                hre.hyperdriveDeploy.deployments.byName("BASE_TOKEN").address,
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
