import { parseEther, toFunctionSelector } from "viem";
import { HyperdriveInstanceDeployConfigInput } from "../../lib";

const CONTRIBUTION = "10000";

export const MORPHO_DAI_14DAY: HyperdriveInstanceDeployConfigInput = {
    name: "MORPHO_DAI_14DAY",
    contract: "ERC4626Hyperdrive",
    coordinatorName: "ERC4626_COORDINATOR",
    deploymentId: "0x666666",
    salt: "0x69420",
    contribution: CONTRIBUTION,
    fixedAPR: "0.05",
    timestretchAPR: "0.05",
    options: {
        // destination: "0xsomeone", defaults to deployer
        asBase: true,
        // extraData: "0x",
    },
    poolDeployConfig: {
        baseToken: {
            name: "DAI",
            deploy: async (hre) => {
                let pc = await hre.viem.getPublicClient();
                let baseToken = await hre.hyperdriveDeploy.deployContract(
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
                );
                // allow minting by the public
                let tx = await baseToken.write.setPublicCapability([
                    toFunctionSelector("mint(uint256)"),
                    true,
                ]);
                await pc.waitForTransactionReceipt({ hash: tx });
                tx = await baseToken.write.setPublicCapability([
                    toFunctionSelector("mint(address,uint256)"),
                    true,
                ]);
                await pc.waitForTransactionReceipt({ hash: tx });
                // approve the coordinator for the contribution
                tx = await baseToken.write.approve([
                    hre.hyperdriveDeploy.deployments.byName(
                        "ERC4626_COORDINATOR",
                    ).address,
                    parseEther(CONTRIBUTION),
                ]);
                await pc.waitForTransactionReceipt({ hash: tx });
                tx = await baseToken.write.mint([parseEther(CONTRIBUTION)]);
                await pc.waitForTransactionReceipt({ hash: tx });
            },
        },
        vaultSharesToken: "0x3A2031f3FAb5AA2b5c47c02fcD9f26072977834c",
        circuitBreakerDelta: "0.6",
        minimumShareReserves: "10",
        minimumTransactionAmount: "0.001",
        positionDuration: "14 days",
        checkpointDuration: "1 day",
        timeStretch: "0",
        governance: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
        feeCollector: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
        sweepCollector: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
        fees: {
            curve: "0.01",
            flat: "0.0005",
            governanceLP: "0.15",
            governanceZombie: "0.03",
        },
    },
};
