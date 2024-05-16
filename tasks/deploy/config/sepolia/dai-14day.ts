import { parseEther, toFunctionSelector } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";

const CONTRIBUTION = parseEther("10000");

export const SEPOLIA_DAI_14DAY: HyperdriveInstanceConfig<"ERC4626"> = {
    name: "DAI_14_DAY",
    prefix: "ERC4626",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName("ERC4626_COORDINATOR").address,
    deploymentId: toBytes32("DAI_14_DAY"),
    salt: toBytes32("0x69420"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.10"),
    timestretchAPR: parseEther("0.10"),
    targetCount: 4,
    options: {
        extraData: "0x",
        asBase: true,
        destination: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
    },
    poolDeployConfig: async (hre, options) => {
        let pc = await hre.viem.getPublicClient();
        let baseToken = await hre.hyperdriveDeploy.ensureDeployed(
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
        let vaultSharesToken = await hre.hyperdriveDeploy.ensureDeployed(
            "SDAI",
            "MockERC4626",
            [
                hre.hyperdriveDeploy.deployments.byName("DAI").address,
                "Savings DAI",
                "SDAI",
                parseEther("0.10"),
                "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
                true,
                parseEther("10000"),
            ],
            options,
        );

        // allow minting by the public
        let tx = await baseToken.write.setPublicCapability([
            toFunctionSelector("mint(uint256)"),
            true,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
        tx = await vaultSharesToken.write.setPublicCapability([
            toFunctionSelector("mint(uint256)"),
            true,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
        tx = await baseToken.write.setPublicCapability([
            toFunctionSelector("mint(address,uint256)"),
            true,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
        tx = await vaultSharesToken.write.setPublicCapability([
            toFunctionSelector("mint(address,uint256)"),
            true,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });

        // approve the coordinator for the contribution
        tx = await baseToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName("ERC4626_COORDINATOR")
                .address,
            CONTRIBUTION,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });

        // mint some tokens for the contribution
        tx = await baseToken.write.mint([CONTRIBUTION]);
        await pc.waitForTransactionReceipt({ hash: tx });

        return {
            baseToken: baseToken.address,
            vaultSharesToken: vaultSharesToken.address,
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
