import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";
import { MAINNET_SDAI_ADDRESS } from "../deploy/lib/constants";

export type MintSDAIParams = HyperdriveDeployBaseTaskParams & {
    address: string;
    amount: string;
};

HyperdriveDeployBaseTask(
    task(
        "fork:mint-sdai",
        "Mints the specified amount of SDAI to the input address",
    ),
)
    .addParam("address", "address to send SDAI", undefined, types.string)
    .addParam("amount", "amount (in ether) to mint", undefined, types.string)
    .setAction(
        async (
            { address, amount }: Required<MintSDAIParams>,
            { viem, artifacts, run },
        ) => {
            await run("fork:mint-dai", { address, amount });
            let data = encodeFunctionData({
                abi: (await artifacts.readArtifact("ERC4626")).abi,
                functionName: "deposit",
                args: [parseEther(amount), address as Address],
            });
            let tc = await viem.getTestClient({
                mode: "anvil",
            });
            let tx = await tc.sendUnsignedTransaction({
                from: address as Address,
                to: MAINNET_SDAI_ADDRESS,
                data,
                value: parseEther(amount),
            });
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
