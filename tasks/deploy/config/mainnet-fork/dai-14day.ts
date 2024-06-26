import { formatEther, parseEther } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { MAINNET_DAI_ADDRESS, MAINNET_SDAI_ADDRESS } from "../../lib/constants";
import { MAINNET_FORK_CHECKPOINT_REWARDER_NAME } from "./checkpoint-rewarder";
import { MAINNET_FORK_ERC4626_COORDINATOR_NAME } from "./erc4626-coordinator";
import {
    MAINNET_FORK_FACTORY_GOVERNANCE_ADDRESS,
    MAINNET_FORK_FACTORY_NAME,
} from "./factory";

export const MAINNET_FORK_DAI_14DAY_NAME = "DAI_14_DAY";
const CONTRIBUTION = parseEther("10000");

export const MAINNET_FORK_DAI_14DAY: HyperdriveInstanceConfig<"ERC4626"> = {
    name: MAINNET_FORK_DAI_14DAY_NAME,
    prefix: "ERC4626",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(
            MAINNET_FORK_ERC4626_COORDINATOR_NAME,
        ).address,
    deploymentId: toBytes32(MAINNET_FORK_DAI_14DAY_NAME),
    salt: toBytes32("0x69420"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.10"),
    timestretchAPR: parseEther("0.10"),
    options: {
        extraData: "0x",
        asBase: true,
        destination: process.env.ADMIN! as `0x${string}`,
    },
    // Prepare to deploy the contract by setting approvals and minting sufficient
    // tokens for the contribution.
    prepare: async (hre) => {
        let baseToken = await hre.viem.getContractAt(
            "ERC20Mintable",
            MAINNET_DAI_ADDRESS,
        );
        let tx = await baseToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName(
                MAINNET_FORK_ERC4626_COORDINATOR_NAME,
            ).address,
            CONTRIBUTION,
        ]);
        let pc = await hre.viem.getPublicClient();
        await pc.waitForTransactionReceipt({ hash: tx });
        await hre.run("fork:mint-dai", {
            amount: formatEther(CONTRIBUTION),
            address: (await hre.getNamedAccounts())["deployer"],
        });
    },
    poolDeployConfig: async (hre) => {
        return {
            baseToken: MAINNET_DAI_ADDRESS,
            vaultSharesToken: MAINNET_SDAI_ADDRESS,
            circuitBreakerDelta: parseEther("0.6"),
            minimumShareReserves: parseEther("10"),
            minimumTransactionAmount: parseEther("0.001"),
            positionDuration: parseDuration("14 days"),
            checkpointDuration: parseDuration("1 day"),
            timeStretch: 0n,
            governance: MAINNET_FORK_FACTORY_GOVERNANCE_ADDRESS,
            feeCollector: MAINNET_FORK_FACTORY_GOVERNANCE_ADDRESS,
            sweepCollector: MAINNET_FORK_FACTORY_GOVERNANCE_ADDRESS,
            checkpointRewarder: hre.hyperdriveDeploy.deployments.byName(
                MAINNET_FORK_CHECKPOINT_REWARDER_NAME,
            ).address,
            ...(await getLinkerDetails(
                hre,
                hre.hyperdriveDeploy.deployments.byName(
                    MAINNET_FORK_FACTORY_NAME,
                ).address,
            )),
            fees: {
                curve: parseEther("0.01"),
                flat: normalizeFee(parseEther("0.0005"), "14 days"),
                governanceLP: parseEther("0.15"),
                governanceZombie: parseEther("0.03"),
            },
        };
    },
};
