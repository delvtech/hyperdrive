import { formatEther, parseEther } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { MAINNET_DAI_ADDRESS, MAINNET_SDAI_ADDRESS } from "../../lib/constants";

const CONTRIBUTION = parseEther("10000");

export const MAINNET_FORK_DAI_14DAY: HyperdriveInstanceConfig<"ERC4626"> = {
    name: "DAI_14_DAY",
    prefix: "ERC4626",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName("ERC4626_COORDINATOR").address,
    deploymentId: toBytes32("DAI_14_DAY_2"),
    salt: toBytes32("0x69420"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.10"),
    timestretchAPR: parseEther("0.10"),
    options: {
        extraData: "0x",
        asBase: true,
        destination: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
    },
    // Prepare to deploy the contract by setting approvals and minting sufficient
    // tokens for the contribution.
    prepare: async (hre) => {
        let baseToken = await hre.viem.getContractAt(
            "ERC20Mintable",
            MAINNET_DAI_ADDRESS,
        );
        let tx = await baseToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName("ERC4626_COORDINATOR")
                .address,
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
            governance: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
            feeCollector: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
            sweepCollector: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
            ...(await getLinkerDetails(
                hre,
                hre.hyperdriveDeploy.deployments.byName("FACTORY").address,
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
