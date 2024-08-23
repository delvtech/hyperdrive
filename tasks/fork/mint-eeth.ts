import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther, zeroAddress } from "viem";
import {
    EETH_ADDRESS_MAINNET,
    ETHERFI_WHALE_MAINNET,
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";

export type MintEETHParams = HyperdriveDeployBaseTaskParams & {
    address: string;
    amount: string;
};

HyperdriveDeployBaseTask(
    task(
        "fork:mint-eeth",
        "Mints the specified amount of eETH to the input address",
    ),
)
    .addOptionalParam(
        "address",
        "address to send eETH",
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
            { address, amount }: Required<MintEETHParams>,
            { viem, artifacts, getNamedAccounts },
        ) => {
            if (address === zeroAddress) {
                address = (await getNamedAccounts())["deployer"];
            }
            let contract = await viem.getContractAt(
                "solmate/tokens/ERC20.sol:ERC20",
                EETH_ADDRESS_MAINNET,
            );
            let balance = await contract.read.balanceOf([
                ETHERFI_WHALE_MAINNET,
            ]);
            if (balance < parseEther(amount)) {
                console.log(
                    "ERROR: insufficient funds in eETH whale account, skipping...",
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
                address: ETHERFI_WHALE_MAINNET,
                value: parseEther("1"),
            });
            let tx = await tc.sendUnsignedTransaction({
                from: ETHERFI_WHALE_MAINNET,
                to: EETH_ADDRESS_MAINNET,
                data: transferData,
            });
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
