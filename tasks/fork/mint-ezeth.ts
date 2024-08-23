import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther, zeroAddress } from "viem";
import {
    EZETH_ADDRESS_MAINNET,
    EZETH_WHALE_MAINNET,
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";

export type MintEZETHParams = HyperdriveDeployBaseTaskParams & {
    address: string;
    amount: string;
};

HyperdriveDeployBaseTask(
    task(
        "fork:mint-ezeth",
        "Mints the specified amount of EZETH to the input address",
    ),
)
    .addOptionalParam(
        "address",
        "address to send EZETH",
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
            { address, amount }: Required<MintEZETHParams>,
            { viem, artifacts, getNamedAccounts },
        ) => {
            if (address === zeroAddress) {
                address = (await getNamedAccounts())["deployer"];
            }
            let contract = await viem.getContractAt(
                "solmate/tokens/ERC20.sol:ERC20",
                EZETH_ADDRESS_MAINNET,
            );
            let balance = await contract.read.balanceOf([EZETH_WHALE_MAINNET]);
            if (balance < parseEther(amount)) {
                console.log(
                    "ERROR: insufficient funds in EZETH whale account, skipping...",
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
                address: EZETH_WHALE_MAINNET,
                value: parseEther("1"),
            });
            let tx = await tc.sendUnsignedTransaction({
                from: EZETH_WHALE_MAINNET,
                to: EZETH_ADDRESS_MAINNET,
                data: transferData,
            });
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
