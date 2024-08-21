import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther, zeroAddress } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";
import {
    RETH_ADDRESS_MAINNET,
    RETH_WHALE_MAINNET,
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
    .addOptionalParam(
        "address",
        "address to send RETH",
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
            { address, amount }: Required<MintRETHParams>,
            { viem, artifacts, getNamedAccounts },
        ) => {
            if (address === zeroAddress) {
                address = (await getNamedAccounts())["deployer"];
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
                address: RETH_WHALE_MAINNET,
                value: parseEther("1"),
            });
            let tx = await tc.sendUnsignedTransaction({
                from: RETH_WHALE_MAINNET,
                to: RETH_ADDRESS_MAINNET,
                data: transferData,
            });
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
