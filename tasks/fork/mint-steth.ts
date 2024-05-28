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
            { viem, artifacts },
        ) => {
            let transferData = encodeFunctionData({
                abi: (await artifacts.readArtifact("MockLido")).abi,
                functionName: "submit",
                args: [address as Address],
            });

            let pc = await viem.getPublicClient();
            let tc = await viem.getTestClient({
                mode: "anvil",
            });
            await tc.setBalance({
                address: address as Address,
                value:
                    (await pc.getBalance({ address: address as Address })) +
                    parseEther(amount!),
            });
            let tx = await tc.sendUnsignedTransaction({
                from: address as Address,
                to: MAINNET_STETH_ADDRESS,
                data: transferData,
                value: parseEther(amount!),
            });
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
