import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther, zeroAddress } from "viem";
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
    .addOptionalParam(
        "address",
        "address to send USDC",
        zeroAddress,
        types.string,
    )
    .addOptionalParam("amount", "amount of USDC to mint", "10000", types.string)
    .setAction(
        async (
            { address, amount }: Required<MintUSDCParams>,
            { viem, artifacts, getNamedAccounts },
        ) => {
            if (address === zeroAddress) {
                address = (await getNamedAccounts())["deployer"];
            }
            let adjustedAmount = BigInt(amount) * 1_000_000n;
            let contract = await viem.getContractAt(
                "solmate/tokens/ERC20.sol:ERC20",
                USDC_ADDRESS_MAINNET,
            );

            // Ensure the whale has sufficient token balance.
            let balance = await contract.read.balanceOf([USDC_WHALE_MAINNET]);
            if (balance < adjustedAmount) {
                console.log(
                    "ERROR: insufficient funds in USDC whale account, skipping...",
                );
                return;
            }

            // Prepare the raw "mint" transaction data.
            let transferData = encodeFunctionData({
                abi: (
                    await artifacts.readArtifact(
                        "solmate/tokens/ERC20.sol:ERC20",
                    )
                ).abi,
                functionName: "transfer",
                args: [address as Address, adjustedAmount],
            });

            // Ensure the whale has enough eth to perform the "mint".
            let tc = await viem.getTestClient({
                mode: "anvil",
            });
            await tc.setBalance({
                address: USDC_WHALE_MAINNET,
                value: parseEther("1"),
            });

            // Send an unsigned transaction (will only work on anvil/hardhat).
            let tx = await tc.sendUnsignedTransaction({
                from: USDC_WHALE_MAINNET,
                to: USDC_ADDRESS_MAINNET,
                data: transferData,
            });
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
