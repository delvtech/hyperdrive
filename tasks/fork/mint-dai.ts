import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
    MAINNET_DAI_ADDRESS,
    MAINNET_DAI_WHALE,
} from "../deploy";

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
            let contract = await viem.getContractAt(
                "solmate/tokens/ERC20.sol:ERC20",
                MAINNET_DAI_ADDRESS,
            );
            let balance = await contract.read.balanceOf([MAINNET_DAI_WHALE]);
            if (balance < parseEther(amount)) {
                console.log(
                    "ERROR: insufficient funds in DAI whale account, skipping...",
                );
                return;
            }

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
                address: MAINNET_DAI_WHALE,
                value: parseEther("1"),
            });
            let tx = await tc.sendUnsignedTransaction({
                from: MAINNET_DAI_WHALE,
                to: MAINNET_DAI_ADDRESS,
                data: transferData,
            });
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
