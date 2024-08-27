import { task, types } from "hardhat/config";
import {
    encodeAbiParameters,
    encodeFunctionData,
    keccak256,
    parseAbiParameters,
    parseEther,
    toHex,
} from "viem";
import {
    CHAINLINK_AGGREGATOR_ADDRESS_GNOSIS,
    CHAINLINK_AGGREGATOR_WSTETH_ETH_PROXY_GNOSIS,
    EETH_LIQUIDITY_POOL_ADDRESS_MAINNET,
    EETH_MEMBERSHIP_MANAGER_ADDRESS_MAINNET,
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
    RETH_ADDRESS_MAINNET,
    STETH_ADDRESS_MAINNET,
} from "../deploy";
import { sleep } from "./lib";

export type MaintainRateParams = HyperdriveDeployBaseTaskParams & {
    rate: string;
    interval: number;
};

HyperdriveDeployBaseTask(
    task(
        "fork:maintain-rate",
        "Increase the balances of all underlying vaults on a fork network so that they produce yield.",
    ),
)
    .addOptionalParam(
        "rate",
        "rate to set for all underlying vaults (scaled to 1e18)",
        "0.03",
        types.string,
    )
    .addOptionalParam(
        "interval",
        "time in hours between balance updates",
        1,
        types.int,
    )
    .setAction(async ({ rate, interval }: MaintainRateParams, hre) => {
        let tc = await hre.viem.getTestClient({
            mode: "anvil",
        });
        let pc = await hre.viem.getPublicClient();

        // Every hour, increase the balance of each vault by an amount proportional to the annual rate.
        while (true) {
            console.log("increasing balance of underlying vaults...");

            // Mainnet Pools
            if (hre.network.name === "mainnet_fork") {
                // For STETH, modify the `beaconBalance` storage slot value.
                let slot = keccak256(toHex("lido.Lido.beaconBalance"));
                let stethCurrentBalance = BigInt(
                    (await pc.getStorageAt({
                        address: STETH_ADDRESS_MAINNET,
                        slot,
                    }))!,
                );
                let stethBalanceIncrease =
                    (stethCurrentBalance *
                        BigInt(interval) *
                        parseEther(rate)) /
                    (365n * 24n * BigInt(1e18));
                await tc.setStorageAt({
                    address: STETH_ADDRESS_MAINNET,
                    index: slot,
                    value: toHex(
                        BigInt(stethCurrentBalance!) + stethBalanceIncrease,
                        {
                            size: 32,
                        },
                    ),
                });
                console.log(
                    `steth balance increased by ${stethBalanceIncrease}`,
                );

                // For RETH, update the ETH balance of the RocketTokenRETH contract.
                let rethCurrentBalance = await pc.getBalance({
                    address: RETH_ADDRESS_MAINNET,
                });
                let rethBalanceIncrease =
                    (rethCurrentBalance * BigInt(interval) * parseEther(rate)) /
                    (365n * 24n * BigInt(1e18));
                await tc.setBalance({
                    address: RETH_ADDRESS_MAINNET,
                    value: rethCurrentBalance + rethBalanceIncrease,
                });
                console.log(`reth balance increased by ${rethBalanceIncrease}`);

                // TODO: This won't necessarily use the right rate.
                //
                // For SDAI, nothing needs to be done so long as the underlying `rho`
                // value is not recalculated.

                // For EETH, we can call rebase on the Etherfi contract using an
                // impersonated account.
                let etherfi = await hre.viem.getContractAt(
                    "ILiquidityPool",
                    EETH_LIQUIDITY_POOL_ADDRESS_MAINNET,
                );
                let etherToAdd =
                    ((await etherfi.read.getTotalPooledEther()) *
                        BigInt(interval) *
                        parseEther(rate)) /
                    (365n * 24n * BigInt(1e18));
                let txData = encodeFunctionData({
                    abi: (await hre.artifacts.readArtifact("ILiquidityPool"))
                        .abi,
                    functionName: "rebase",
                    args: [etherToAdd],
                });
                await tc.sendUnsignedTransaction({
                    from: EETH_MEMBERSHIP_MANAGER_ADDRESS_MAINNET,
                    to: EETH_LIQUIDITY_POOL_ADDRESS_MAINNET,
                    data: txData,
                });
                await tc.setBalance({
                    address: EETH_LIQUIDITY_POOL_ADDRESS_MAINNET,
                    value: etherToAdd,
                });
                console.log(`etherfi total assets increased by ${etherToAdd}`);

                // TODO: This won't necessarily use the right rate.
                //
                // For Morpho, nothing needs to be done and interest will accrue at
                // the market rate.
            } else if (hre.network.name === "gnosis") {
                // Chainlink wstETH

                // Get the latest round ID and answer. We'll overwrite this round ID
                // with the updated answer.
                let chainlinkAggregatorContract = await hre.viem.getContractAt(
                    "contracts/src/interfaces/IChainlinkAggregatorV3.sol:IChainlinkAggregatorV3",
                    CHAINLINK_AGGREGATOR_WSTETH_ETH_PROXY_GNOSIS,
                );
                let [roundId, answer, _, updatedAt] =
                    await chainlinkAggregatorContract.read.latestRoundData();
                let latestRoundLocation = encodeAbiParameters(
                    parseAbiParameters("uint32, uint256"),
                    [Number(roundId), 44n],
                );

                // Accrue interest in the Chainlink wstETH market. We do this by
                // overwriting the latest round's answer.
                let tc = await hre.viem.getTestClient();
                await tc.setStorageAt({
                    address: CHAINLINK_AGGREGATOR_ADDRESS_GNOSIS,
                    index: latestRoundLocation,
                    value:
                        (answer * BigInt(interval) * parseEther(rate)) /
                        (365n * 24n * BigInt(1e18)),
                });
            }

            await sleep(interval * 60);
        }
    });
