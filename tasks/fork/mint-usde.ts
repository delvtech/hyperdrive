import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther, zeroAddress } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
    USDE_ADDRESS_MAINNET,
    USDE_WHALE_MAINNET,
} from "../deploy";

export type MintUSDEParams = HyperdriveDeployBaseTaskParams & {
    address: string;
    amount: string;
};

HyperdriveDeployBaseTask(
    task(
        "fork:mint-usde",
        "Mints the specified amount of USDE to the input address",
    ),
)
    .addOptionalParam(
        "address",
        "address to send USDE",
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
            { address, amount }: Required<MintUSDEParams>,
            { viem, artifacts, getNamedAccounts },
        ) => {
            if (address === zeroAddress) {
                address = (await getNamedAccounts())["deployer"];
            }

            let contract = await viem.getContractAt(
                "solmate/tokens/ERC20.sol:ERC20",
                USDE_ADDRESS_MAINNET,
            );
            let balance = await contract.read.balanceOf([USDE_WHALE_MAINNET]);
            if (balance < parseEther(amount)) {
                console.log(
                    "ERROR: insufficient funds in USDE whale account, skipping...",
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
                address: USDE_WHALE_MAINNET,
                value: parseEther("1"),
            });
            let tx = await tc.sendUnsignedTransaction({
                from: USDE_WHALE_MAINNET,
                to: USDE_ADDRESS_MAINNET,
                data: transferData,
            });
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
