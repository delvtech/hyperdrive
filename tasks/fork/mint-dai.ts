import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther, zeroAddress } from "viem";
import {
    DAI_ADDRESS_MAINNET,
    DAI_WHALE_MAINNET,
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
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
    .addOptionalParam(
        "address",
        "address to send DAI",
        zeroAddress,
        types.string,
    )
    .addOptionalParam(
        "amount",
        "amount (in ether) to mint",
        "10000",
        types.string,
    )
    .setAction(
        async (
            { address, amount }: Required<MintDAIParams>,
            { viem, artifacts, getNamedAccounts },
        ) => {
            if (address === zeroAddress) {
                address = (await getNamedAccounts())["deployer"];
            }
            let contract = await viem.getContractAt(
                "solmate/tokens/ERC20.sol:ERC20",
                DAI_ADDRESS_MAINNET,
            );
            let balance = await contract.read.balanceOf([DAI_WHALE_MAINNET]);
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
                address: DAI_WHALE_MAINNET,
                value: parseEther("1"),
            });
            let tx = await tc.sendUnsignedTransaction({
                from: DAI_WHALE_MAINNET,
                to: DAI_ADDRESS_MAINNET,
                data: transferData,
            });
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
