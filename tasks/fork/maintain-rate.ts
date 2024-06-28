import { task, types } from "hardhat/config";
import { keccak256, parseEther, toHex } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
    MAINNET_RETH_ADDRESS,
    MAINNET_STETH_ADDRESS,
} from "../deploy";
import { sleep } from "./lib";

export type MaintainRateParams = HyperdriveDeployBaseTaskParams & {
    rate: string;
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
    .setAction(async ({ rate }, { viem }) => {
        let tc = await viem.getTestClient({
            mode: "anvil",
        });
        let pc = await viem.getPublicClient();
        let interval = 60; // minutes
        let rateFraction = parseEther("1") / parseEther(rate);
        // Every hour, increase the balance of each vault by an amount proportional to the annual rate.
        while (true) {
            console.log("increasing balance of underlying vaults...");

            // For STETH, modify the `beaconBalance` storage slot value.
            let slot = keccak256(toHex("lido.Lido.beaconBalance"));
            let stethCurrentBalance = BigInt(
                (await pc.getStorageAt({
                    address: MAINNET_STETH_ADDRESS,
                    slot,
                }))!,
            );
            let stethBalanceIncrease =
                (stethCurrentBalance * BigInt(interval)) /
                (365n * 24n * rateFraction);
            await tc.setStorageAt({
                address: MAINNET_STETH_ADDRESS,
                index: slot,
                value: toHex(
                    BigInt(stethCurrentBalance!) + stethBalanceIncrease,
                    {
                        size: 32,
                    },
                ),
            });
            console.log(`steth balance increased by ${stethBalanceIncrease}`);

            // For RETH, send ETH to the RocketTokenRETH contract.
            let rethCurrentBalance = await pc.getBalance({
                address: MAINNET_RETH_ADDRESS,
            });
            let rethBalanceIncrease =
                (rethCurrentBalance * BigInt(interval)) /
                (365n * 24n * rateFraction);
            await tc.setBalance({
                address: MAINNET_RETH_ADDRESS,
                value: rethCurrentBalance + rateFraction,
            });
            console.log(`reth balance increased by ${rethBalanceIncrease}`);

            // For SDAI, nothing needs to be done so long as the underlying `rho` value is not recalculated.
            await sleep(interval);
        }
    });
