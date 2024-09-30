import { Address, keccak256, parseEther, toBytes, zeroAddress } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { SDAI_ADDRESS_MAINNET, THREE_MONTHS } from "../../lib/constants";
import { MAINNET_CORN_COORDINATOR_NAME } from "./corn-coordinator";
import { MAINNET_FACTORY_NAME } from "./factory";

// The name of the pool.
export const MAINNET_CORN_SDAI_91DAY_NAME =
    "ElementDAO 91 Day Corn sDAI Hyperdrive";

// We use a contribution of 100 sDAI.
const CONTRIBUTION = parseEther("100");

export const MAINNET_CORN_SDAI_91DAY: HyperdriveInstanceConfig<"Corn"> = {
    name: MAINNET_CORN_SDAI_91DAY_NAME,
    prefix: "Corn",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(MAINNET_CORN_COORDINATOR_NAME)
            .address,
    deploymentId: keccak256(toBytes(MAINNET_CORN_SDAI_91DAY_NAME)),
    salt: toBytes32("0x69420"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.08"),
    timestretchAPR: parseEther("0.075"),
    options: async (hre) => ({
        extraData: "0x",
        asBase: true,
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    // Prepare to deploy the contract by setting approvals.
    prepare: async (hre) => {
        let baseToken = await hre.viem.getContractAt(
            "contracts/src/interfaces/IERC20.sol:IERC20",
            SDAI_ADDRESS_MAINNET,
        );
        let tx = await baseToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName(
                MAINNET_CORN_COORDINATOR_NAME,
            ).address,
            CONTRIBUTION,
        ]);
        let pc = await hre.viem.getPublicClient();
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        let factoryContract = await hre.viem.getContractAt(
            "HyperdriveFactory",
            hre.hyperdriveDeploy.deployments.byName(MAINNET_FACTORY_NAME)
                .address,
        );
        return {
            baseToken: SDAI_ADDRESS_MAINNET,
            vaultSharesToken: zeroAddress,
            circuitBreakerDelta: parseEther("0.075"),
            minimumShareReserves: parseEther("0.001"), // 1e15
            minimumTransactionAmount: parseEther("0.001"), // 1e15
            positionDuration: parseDuration(THREE_MONTHS),
            checkpointDuration: parseDuration("1 day"),
            timeStretch: 0n,
            governance: await factoryContract.read.hyperdriveGovernance(),
            feeCollector: await factoryContract.read.feeCollector(),
            sweepCollector: await factoryContract.read.sweepCollector(),
            checkpointRewarder: await factoryContract.read.checkpointRewarder(),
            ...(await getLinkerDetails(
                hre,
                hre.hyperdriveDeploy.deployments.byName(MAINNET_FACTORY_NAME)
                    .address,
            )),
            fees: {
                curve: parseEther("0.01"),
                flat: normalizeFee(parseEther("0.0005"), THREE_MONTHS),
                governanceLP: parseEther("0.15"),
                governanceZombie: parseEther("0.03"),
            },
        };
    },
};
