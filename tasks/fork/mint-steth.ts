import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther, zeroAddress } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";
import { STETH_ADDRESS_MAINNET } from "../deploy/lib/constants";

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
    .addOptionalParam(
        "address",
        "address to send STETH",
        zeroAddress,
        types.string,
    )
    .addOptionalParam(
        "amount",
        "amount (in ether) to mint",
        "100",
        types.string,
    )
    .setAction(
        async (
            { address, amount }: Required<MintSTETHParams>,
            { viem, artifacts, getNamedAccounts },
        ) => {
            if (address === zeroAddress) {
                address = (await getNamedAccounts())["deployer"];
            }
            let submitData = encodeFunctionData({
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
                to: STETH_ADDRESS_MAINNET,
                data: submitData,
                value: parseEther(amount!),
            });
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
