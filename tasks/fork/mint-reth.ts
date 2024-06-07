import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";
import {
    MAINNET_RETH_ADDRESS,
    MAINNET_RETH_WHALE,
} from "../deploy/lib/constants";

export type MintRETHParams = HyperdriveDeployBaseTaskParams & {
    address: string;
    amount: string;
};

HyperdriveDeployBaseTask(
    task(
        "fork:mint-reth",
        "Mints the specified amount of RETH to the input address",
    ),
)
    .addParam("address", "address to send RETH", undefined, types.string)
    .addParam("amount", "amount (in ether) to mint", undefined, types.string)
    .setAction(
        async (
            { address, amount }: Required<MintRETHParams>,
            { viem, artifacts },
        ) => {
            let transferData = encodeFunctionData({
                abi: (
                    await artifacts.readArtifact(
                        "solmate/tokens/ERC20.sol:ERC20",
                    )
                ).abi,
                functionName: "transfer",
                args: [address as Address, parseEther(amount!)],
            });

            let tc = await viem.getTestClient({
                mode: "anvil",
            });
            await tc.setBalance({
                address: MAINNET_RETH_WHALE,
                value: parseEther("1"),
            });
            let tx = await tc.sendUnsignedTransaction({
                from: MAINNET_RETH_WHALE,
                to: MAINNET_RETH_ADDRESS,
                data: transferData,
            });
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
