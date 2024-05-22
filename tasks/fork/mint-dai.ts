import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";
import { MAINNET_DAI_ADDRESS } from "../deploy/lib/constants";

export type MintDAIParams = HyperdriveDeployBaseTaskParams & {
    address: string;
    amount: string;
};

HyperdriveDeployBaseTask(
    task(
        "fork:mint-dai",
        "Mints the specified amount of DAI to the input address",
    ),
)
    .addParam("address", "address to send DAI", undefined, types.string)
    .addParam("amount", "amount (in ether) to mint", undefined, types.string)
    .setAction(
        async (
            { address, amount }: Required<MintDAIParams>,
            { viem, artifacts },
        ) => {
            let transferData = encodeFunctionData({
                abi: (await artifacts.readArtifact("ERC20Mintable")).abi,
                functionName: "transferFrom",
                args: [
                    MAINNET_DAI_ADDRESS,
                    address as Address,
                    parseEther(amount!),
                ],
            });
            let tc = await viem.getTestClient({
                mode: "anvil",
            });
            await tc.setBalance({
                address: MAINNET_DAI_ADDRESS,
                value: parseEther("1"),
            });
            await tc.impersonateAccount({
                address: MAINNET_DAI_ADDRESS as Address,
            });
            let tx = await tc.sendUnsignedTransaction({
                from: MAINNET_DAI_ADDRESS,
                to: MAINNET_DAI_ADDRESS,
                data: transferData,
            });
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
