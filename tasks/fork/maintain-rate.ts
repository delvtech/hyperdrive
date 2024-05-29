import { task } from "hardhat/config";
import { keccak256, toHex } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
    MAINNET_RETH_ADDRESS,
    MAINNET_SDAI_ADDRESS,
    MAINNET_STETH_ADDRESS,
} from "../deploy";

export type MaintainRateParams = HyperdriveDeployBaseTaskParams & {
    // time: DurationStrig;
    // checkpoint?: DurationString;
};

HyperdriveDeployBaseTask(
    task(
        "fork:maintain-rate",
        "Advances time for all hyperdrive instances creating checkpoints along the way if '--checkpoint' is provided a duration",
    ),
).setAction(
    async ({}, { viem, artifacts, hyperdriveDeploy, config, network }) => {
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

        for (let instance of poolContracts) {
            let vaultSharesToken = await instance.read.vaultSharesToken();
            let currentBalance: bigint;
            switch (vaultSharesToken) {
                case MAINNET_STETH_ADDRESS:
                    let slot = keccak256(toHex("lido.Lido.beaconBalance"));
                    currentBalance = BigInt(
                        (await pc.getStorageAt({
                            address: MAINNET_STETH_ADDRESS,
                            slot,
                        }))!,
                    );
                    console.log(BigInt(currentBalance!));
                    await tc.setStorageAt({
                        address: MAINNET_STETH_ADDRESS,
                        index: slot,
                        value: toHex(
                            BigInt(currentBalance!) +
                                BigInt(currentBalance!) / 100n,
                            { size: 32 },
                        ),
                    });
                    break;
                case MAINNET_RETH_ADDRESS:
                    currentBalance = await pc.getBalance({
                        address: MAINNET_RETH_ADDRESS,
                    });
                    await tc.setBalance({
                        address: MAINNET_RETH_ADDRESS,
                        value: currentBalance + currentBalance / 100n,
                    });
                    break;
                case MAINNET_SDAI_ADDRESS:
                    break;

                default:
            }
        }
    },
);
