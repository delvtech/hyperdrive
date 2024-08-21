import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";
import {
    SDAI_ADDRESS_MAINNET,
    SDAI_WHALE_MAINNET,
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
    .addOptionalParam(
        "amount",
        "amount (in ether) to mint",
        "10000",
        types.string,
    )
    .setAction(
        async (
            { address, amount }: Required<MintSDAIParams>,
            { viem, artifacts },
        ) => {
            let contract = await viem.getContractAt(
                "solmate/tokens/ERC20.sol:ERC20",
                SDAI_ADDRESS_MAINNET,
            );
            let balance = await contract.read.balanceOf([SDAI_WHALE_MAINNET]);
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
                address: SDAI_WHALE_MAINNET,
                value: parseEther("1"),
            });
            let tx = await tc.sendUnsignedTransaction({
                from: SDAI_WHALE_MAINNET,
                to: SDAI_ADDRESS_MAINNET,
                data: transferData,
            });
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
