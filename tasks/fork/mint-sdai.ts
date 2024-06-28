import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";
import {
    MAINNET_SDAI_ADDRESS,
    MAINNET_SDAI_WHALE,
} from "../deploy/lib/constants";

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
            { viem, artifacts },
        ) => {
            let contract = await viem.getContractAt(
                "solmate/tokens/ERC20.sol:ERC20",
                MAINNET_SDAI_ADDRESS,
            );
            let balance = await contract.read.balanceOf([MAINNET_SDAI_WHALE]);
            if (balance < parseEther(amount)) {
                console.log(
                    "ERROR: insufficient funds in SDAI whale account, skipping...",
                );
                return;
            }

            let pc = await viem.getPublicClient();
            let transferData = encodeFunctionData({
                abi: (await artifacts.readArtifact("ERC20Mintable")).abi,
                functionName: "transfer",
                args: [address as Address, parseEther(amount!)],
            });

            let tc = await viem.getTestClient({
                mode: "anvil",
            });
            await tc.setBalance({
                address: MAINNET_SDAI_WHALE,
                value: parseEther("1"),
            });
            let tx = await tc.sendUnsignedTransaction({
                from: MAINNET_SDAI_WHALE,
                to: MAINNET_SDAI_ADDRESS,
                data: transferData,
            });
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
