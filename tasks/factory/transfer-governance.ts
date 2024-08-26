import { task, types } from "hardhat/config";
import { Address, parseEther } from "viem";
import {
    HyperdriveDeployNamedTask,
    HyperdriveDeployNamedTaskParams,
} from "../deploy";

export type FactoryTransferGovernanceParams =
    HyperdriveDeployNamedTaskParams & {
        governance: string;
    };

HyperdriveDeployNamedTask(
    task(
        "factory:transfer-governance",
        "removes the specified deployer coordinator from the factory",
    ),
)
    .addParam("governance", "the governance address", undefined, types.string)
    .setAction(
        async (
            { name, governance }: Required<FactoryTransferGovernanceParams>,
            { viem, hyperdriveDeploy: { deployments }, network },
        ) => {
            // Get the factory contract.
            let deployment = deployments.byName(name);
            console.log(
                `removing ${name} ${deployment.contract} at ${deployment.address} from the factory ...`,
            );
            let factoryAddress = deployments.byName(
                "ElementDAO Hyperdrive Factory",
            ).address as Address;
            const factoryContract = await viem.getContractAt(
                "IHyperdriveFactory",
                factoryAddress,
            );

            // Update the maximum timestretch APR to 20%.
            let pc = await viem.getPublicClient();
            let tx = await factoryContract.write.updateMaxTimeStretchAPR([
                parseEther("0.2"),
            ]);
            await pc.waitForTransactionReceipt({ hash: tx });
            console.log(
                `factory maxTimestretchAPR = ${await factoryContract.read.maxTimeStretchAPR()}`,
            );

            // FIXME: Remove this.
            //
            // Transfer governance of the old pools to the Element DAO.
            let poolAddresses = [
                "0xd7e470043241C10970953Bd8374ee6238e77D735",
                "0x324395D5d835F84a02A75Aa26814f6fD22F25698",
                "0xca5dB9Bb25D09A9bF3b22360Be3763b5f2d13589",
                "0xd41225855A5c5Ba1C672CcF4d72D1822a5686d30",
                "0xA29A771683b4857bBd16e1e4f27D5B6bfF53209B",
                "0x4c3054e51b46BE3191be9A05e73D73F1a2147854",
            ];
            for (const poolAddress of poolAddresses) {
                const poolContract = await viem.getContractAt(
                    "IHyperdrive",
                    poolAddress as Address,
                );
                tx = await poolContract.write.setGovernance([
                    governance as Address,
                ]);
                await pc.waitForTransactionReceipt({ hash: tx });
            }

            // Transfer hyperdrive governance to the Element DAO.
            tx = await factoryContract.write.updateHyperdriveGovernance([
                governance as Address,
            ]);
            await pc.waitForTransactionReceipt({ hash: tx });
            console.log(
                `factory hyperdrive governance = ${await factoryContract.read.hyperdriveGovernance()}`,
            );

            // Transfer governance to the Element DAO.
            tx = await factoryContract.write.updateGovernance([
                governance as Address,
            ]);
            await pc.waitForTransactionReceipt({ hash: tx });
            console.log(
                `factory hyperdrive governance = ${await factoryContract.read.governance()}`,
            );

            // FIXME: Remove this.
            //
            // Check the pool addresses.
            poolAddresses = [
                "0xd7e470043241C10970953Bd8374ee6238e77D735",
                "0x324395D5d835F84a02A75Aa26814f6fD22F25698",
                "0xca5dB9Bb25D09A9bF3b22360Be3763b5f2d13589",
                "0xd41225855A5c5Ba1C672CcF4d72D1822a5686d30",
                "0xA29A771683b4857bBd16e1e4f27D5B6bfF53209B",
                "0x4c3054e51b46BE3191be9A05e73D73F1a2147854",
                "0x158Ed87D7E529CFE274f3036ade49975Fb10f030",
                "0xc8D47DE20F7053Cc02504600596A647A482Bbc46",
            ];
            for (const poolAddress of poolAddresses) {
                const poolContract = await viem.getContractAt(
                    "IHyperdrive",
                    poolAddress as Address,
                );
                console.log(
                    `pool governance = ${(await poolContract.read.getPoolConfig()).governance}`,
                );
            }
        },
    );
