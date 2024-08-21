import { task, types } from "hardhat/config";
import { Address, parseEther } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";

export type MintETHParams = HyperdriveDeployBaseTaskParams & {
    address: string;
    amount: string;
};

HyperdriveDeployBaseTask(
    task(
        "fork:mint-eth",
        "Mints the specified amount of ETH to the input address",
    ),
)
    .addParam("address", "address to send ETH", undefined, types.string)
    .addOptionalParam(
        "amount",
        "amount (in ether) to mint",
        "100",
        types.string,
    )
    .setAction(
        async ({ address, amount }: Required<MintETHParams>, { viem }) => {
            let tc = await viem.getTestClient({
                mode: "anvil",
            });
            let pc = await viem.getPublicClient();
            await tc.setBalance({
                address: address as Address,
                value:
                    parseEther(amount!) +
                    (await pc.getBalance({ address: address as Address })),
            });
        },
    );
