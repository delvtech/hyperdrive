import { task, types } from "hardhat/config";
import { Address, encodeFunctionData, parseEther, zeroAddress } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
    SXDAI_ADDRESS_GNOSIS,
    WXDAI_ADDRESS_GNOSIS,
} from "../deploy";

export type MintWXDAIParams = HyperdriveDeployBaseTaskParams & {
    address: string;
    amount: string;
};

HyperdriveDeployBaseTask(
    task(
        "fork:mint-wxdai",
        "Mints the specified amount of WXDAI to the input address",
    ),
)
    .addOptionalParam(
        "address",
        "address to send WXDAI",
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
            { address, amount }: Required<MintWXDAIParams>,
            { viem, artifacts, getNamedAccounts },
        ) => {
            if (address === zeroAddress) {
                address = (await getNamedAccounts())["deployer"];
            }
            let contract = await viem.getContractAt(
                "solmate/tokens/ERC20.sol:ERC20",
                WXDAI_ADDRESS_GNOSIS,
            );
            let balance = await contract.read.balanceOf([SXDAI_ADDRESS_GNOSIS]);
            if (balance < parseEther(amount)) {
                console.log(
                    "ERROR: insufficient funds in WXDAI whale account, skipping...",
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
                address: SXDAI_ADDRESS_GNOSIS,
                value: parseEther("1"),
            });
            let tx = await tc.sendUnsignedTransaction({
                from: SXDAI_ADDRESS_GNOSIS,
                to: WXDAI_ADDRESS_GNOSIS,
                data: transferData,
            });
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
