import { task } from "hardhat/config";
import { keccak256, toHex } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
    MAINNET_RETH_ADDRESS,
    MAINNET_SDAI_ADDRESS,
    MAINNET_STETH_ADDRESS,
} from "../deploy";
import { sleep } from "./lib";

export type MaintainRateParams = HyperdriveDeployBaseTaskParams & {};

HyperdriveDeployBaseTask(
    task(
        "fork:maintain-rate",
        "Advances time for all hyperdrive instances creating checkpoints along the way if '--checkpoint' is provided a duration",
    ),
).setAction(async ({}, { viem, hyperdriveDeploy, config, network }) => {
    let tc = await viem.getTestClient({
        mode: "anvil",
    });
    let pc = await viem.getPublicClient();
    let poolAddresses = config.networks[
        network.name
    ].hyperdriveDeploy?.instances.map(
        (instance) =>
            hyperdriveDeploy.deployments.byName(instance.name).address,
    );
    let poolContracts = !poolAddresses
        ? []
        : await Promise.all(
              poolAddresses.map(async (a) =>
                  viem.getContractAt("IHyperdriveRead", a),
              ),
          );
    let interval = 60; // minutes
    let rateFraction = 20n; // 1/20 gives a 5% rate.
    while (true) {
        console.log("increasing balance of underlying vaults...");
        for (let instance of poolContracts) {
            let vaultSharesToken = await instance.read.vaultSharesToken();
            let currentBalance: bigint;
            let increase: bigint;
            switch (vaultSharesToken) {
                case MAINNET_STETH_ADDRESS:
                    let slot = keccak256(toHex("lido.Lido.beaconBalance"));
                    currentBalance = BigInt(
                        (await pc.getStorageAt({
                            address: MAINNET_STETH_ADDRESS,
                            slot,
                        }))!,
                    );
                    increase =
                        (currentBalance * BigInt(interval)) /
                        (365n * 24n * rateFraction);
                    await tc.setStorageAt({
                        address: MAINNET_STETH_ADDRESS,
                        index: slot,
                        value: toHex(BigInt(currentBalance!) + increase, {
                            size: 32,
                        }),
                    });
                    console.log(`steth balance increased by ${increase}`);
                    break;
                case MAINNET_RETH_ADDRESS:
                    currentBalance = await pc.getBalance({
                        address: MAINNET_RETH_ADDRESS,
                    });
                    increase =
                        (currentBalance * BigInt(interval)) /
                        (365n * 24n * rateFraction);
                    await tc.setBalance({
                        address: MAINNET_RETH_ADDRESS,
                        value: currentBalance + rateFraction,
                    });
                    console.log(`reth balance increased by ${increase}`);
                    break;

                case MAINNET_SDAI_ADDRESS:
                    // Nothing needs to be done here so long as `rho` is not recalculated.
                    break;

                default:
            }
        }
        sleep(interval);
    }
});
