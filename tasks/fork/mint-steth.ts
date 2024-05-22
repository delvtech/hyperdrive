import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";
import { MAINNET_STETH_ADDRESS } from "../deploy/lib/constants";

export type MintSTETHParams = HyperdriveDeployBaseTaskParams & {
    address: string;
    amount: string;
};

HyperdriveDeployBaseTask(
    task(
        "fork:mint-steth",
        "Mints the specified amount of STETH to the input address",
    ),
)
    .addParam("address", "address to send STETH", undefined, types.string)
    .addParam("amount", "amount (in ether) to mint", undefined, types.string)
    .setAction(
        async (
            { address, amount }: Required<MintSTETHParams>,
            { viem, artifacts, run },
        ) => {
            await run("fork:mint-eth", { address, amount });
            let data = encodeFunctionData({
                abi: (await artifacts.readArtifact("MockLido")).abi,
                functionName: "submit",
                args: [address as Address],
            });
            let tc = await viem.getTestClient({
                mode: "anvil",
            });
            let tx = await tc.sendUnsignedTransaction({
                from: address as Address,
                to: MAINNET_STETH_ADDRESS,
                data,
                value: parseEther(amount),
            });
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
