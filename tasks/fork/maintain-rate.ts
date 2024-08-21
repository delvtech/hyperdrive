import { task, types } from "hardhat/config";
import { HttpNetworkUserConfig } from "hardhat/types";
import { keccak256, parseEther, toHex } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
    MAINNET_ETHERFI_ADDRESS,
    MAINNET_ETHERFI_MEMBERSHIP_MANAGER,
    MAINNET_RETH_ADDRESS,
    MAINNET_STETH_ADDRESS,
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

            // For STETH, modify the `beaconBalance` storage slot value.
            let slot = keccak256(toHex("lido.Lido.beaconBalance"));
            let stethCurrentBalance = BigInt(
                (await pc.getStorageAt({
                    address: MAINNET_STETH_ADDRESS,
                    slot,
                }))!,
            );
            let stethBalanceIncrease =
                (stethCurrentBalance * BigInt(interval) * parseEther(rate)) /
                (365n * 24n * BigInt(1e18));
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

            // For RETH, update the ETH balance of the RocketTokenRETH contract.
            let rethCurrentBalance = await pc.getBalance({
                address: MAINNET_RETH_ADDRESS,
            });
            let rethBalanceIncrease =
                (rethCurrentBalance * BigInt(interval) * parseEther(rate)) /
                (365n * 24n * BigInt(1e18));
            await tc.setBalance({
                address: MAINNET_RETH_ADDRESS,
                value: rethCurrentBalance + rethBalanceIncrease,
            });
            console.log(`reth balance increased by ${rethBalanceIncrease}`);

            // TODO: This won't necessarily use the right rate.
            //
            // For SDAI, nothing needs to be done so long as the underlying `rho`
            // value is not recalculated.

            // For EETH, we can call rebase on the Etherfi contracts using an
            // impersonated account.
            const config = hre.network.config as HttpNetworkUserConfig;
            config.accounts = "remote";
            await tc.impersonateAccount({
                address: MAINNET_ETHERFI_MEMBERSHIP_MANAGER,
            });
            let etherfi = await hre.viem.getContractAt(
                "ILiquidityPool",
                MAINNET_ETHERFI_ADDRESS,
            );
            let etherToAdd =
                ((await etherfi.read.getTotalPooledEther()) *
                    BigInt(interval) *
                    parseEther(rate)) /
                (365n * 24n * BigInt(1e18));
            await etherfi.write.rebase([etherToAdd], {
                account: MAINNET_ETHERFI_MEMBERSHIP_MANAGER,
            });
            await tc.setBalance({
                address: MAINNET_ETHERFI_ADDRESS,
                value: etherToAdd,
            });
            await tc.stopImpersonatingAccount({
                address: MAINNET_ETHERFI_MEMBERSHIP_MANAGER,
            });
            console.log(`etherfi total assets increased by ${etherToAdd}`);

            // TODO: This won't necessarily use the right rate.
            //
            // For Morpho, nothing needs to be done and interest will accrue at
            // the market rate.

            await sleep(interval * 60);
        }
    });
