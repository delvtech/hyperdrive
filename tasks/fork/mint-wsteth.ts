import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther, zeroAddress } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
    WSTETH_ADDRESS_GNOSIS,
    WSTETH_ADDRESS_MAINNET,
    WSTETH_WHALE_GNOSIS,
    WSTETH_WHALE_MAINNET,
} from "../deploy";

export type MintWSTETHParams = HyperdriveDeployBaseTaskParams & {
    address: string;
    amount: string;
};

HyperdriveDeployBaseTask(
    task(
        "fork:mint-wsteth",
        "Mints the specified amount of WSTETH to the input address",
    ),
)
    .addOptionalParam(
        "address",
        "address to send WSTETH",
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
            { address, amount }: Required<MintWSTETHParams>,
            { viem, artifacts, getNamedAccounts, network },
        ) => {
            if (address === zeroAddress) {
                address = (await getNamedAccounts())["deployer"];
            }
            let wstethAddress =
                network.name === "gnosis"
                    ? WSTETH_ADDRESS_GNOSIS
                    : WSTETH_ADDRESS_MAINNET;
            let wstethWhale =
                network.name === "gnosis"
                    ? WSTETH_WHALE_GNOSIS
                    : WSTETH_WHALE_MAINNET;
            let contract = await viem.getContractAt(
                "solmate/tokens/ERC20.sol:ERC20",
                wstethAddress,
            );
            let balance = await contract.read.balanceOf([wstethWhale]);
            if (balance < parseEther(amount)) {
                console.log(
                    "ERROR: insufficient funds in WSTETH whale account, skipping...",
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
                address: wstethWhale,
                value: parseEther("1"),
            });
            let tx = await tc.sendUnsignedTransaction({
                from: wstethWhale,
                to: wstethAddress,
                data: transferData,
            });
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
