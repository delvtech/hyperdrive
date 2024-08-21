import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
    USDC_ADDRESS_MAINNET,
    USDC_WHALE_MAINNET,
} from "../deploy";

export type MintUSDCParams = HyperdriveDeployBaseTaskParams & {
    address: string;
    amount: string;
};

HyperdriveDeployBaseTask(
    task(
        "fork:mint-usdc",
        "Mints the specified amount of USDC to the input address",
    ),
)
    .addParam("address", "address to send USDC", undefined, types.string)
    .addOptionalParam("amount", "amount of USDC to mint", "10000", types.string)
    .setAction(
        async (
            { address, amount }: Required<MintUSDCParams>,
            { viem, artifacts },
        ) => {
            let adjustedAmount = BigInt(amount) * 1_000_000n;
            let contract = await viem.getContractAt(
                "solmate/tokens/ERC20.sol:ERC20",
                USDC_ADDRESS_MAINNET,
            );
            let balance = await contract.read.balanceOf([USDC_WHALE_MAINNET]);
            if (balance < parseEther(amount)) {
                console.log(
                    "ERROR: insufficient funds in USDC whale account, skipping...",
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
                args: [address as Address, adjustedAmount],
            });

            let tc = await viem.getTestClient({
                mode: "anvil",
            });
            await tc.setBalance({
                address: USDC_WHALE_MAINNET,
                value: adjustedAmount,
            });
            let tx = await tc.sendUnsignedTransaction({
                from: USDC_WHALE_MAINNET,
                to: USDC_ADDRESS_MAINNET,
                data: transferData,
            });
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
