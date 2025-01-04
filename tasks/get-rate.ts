import { task, types } from "hardhat/config";
import { Address, formatEther, maxUint256, parseEther } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "./deploy";

// import * as hyperwasm from "@delvtech/hyperdrive-wasm";

export type MarketStateParams = HyperdriveDeployBaseTaskParams & {
    address: string;
    amount: string;
};

HyperdriveDeployBaseTask(
    task(
        "hyperdrive:get-rate",
        "returns the spot rate for the provided hyperdrive instance",
    ),
)
    .addParam(
        "address",
        "address of the hyperdrive pool",
        undefined,
        types.string,
    )
    .addParam(
        "amount",
        "the amount to short the pool by in ether",
        undefined,
        types.string,
    )
    .setAction(
        async (
            { address, amount }: Required<MarketStateParams>,
            { viem, hyperdriveDeploy: { deployments }, network },
        ) => {
            const hyperwasm = await import("@delvtech/hyperdrive-wasm");
            let instance = await viem.getContractAt(
                "IHyperdriveRead",
                address as Address,
            );
            let poolInfo = await instance.read.getPoolInfo();
            let poolConfig = await instance.read.getPoolConfig();
            const spotRate = hyperwasm.spotRate({ poolInfo, poolConfig });
            const spotPrice = hyperwasm.spotPrice({ poolInfo, poolConfig });
            const maxShort = hyperwasm.maxShort({
                openVaultSharePrice: poolConfig.initialVaultSharePrice,
                checkpointExposure: poolInfo.longExposure,
                budget: maxUint256,
                poolInfo,
                poolConfig,
            });

            console.log("current spotRate ", formatEther(spotRate));
            console.log("current spotPrice", formatEther(spotPrice));
            console.log("maxShort", formatEther(maxShort));

            const price = hyperwasm.spotPriceAfterShort({
                bondAmount: parseEther(amount),
                poolInfo,
                poolConfig,
            });
            const apr = hyperwasm.calcAprGivenFixedPrice({
                price,
                positionDuration: poolConfig.positionDuration,
            });
            console.log("price   ", price);
            console.log("apr     ", formatEther(apr));
        },
    );
