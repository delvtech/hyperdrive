import { task, types } from "hardhat/config";
import { Address } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "./deploy";

export type MarketStateParams = HyperdriveDeployBaseTaskParams & {
    address: string;
};

HyperdriveDeployBaseTask(
    task(
        "hyperdrive:market-state",
        "returns the market state for the provided hyperdrive instance",
    ),
)
    .addParam(
        "address",
        "address of the hyperdrive pool",
        undefined,
        types.string,
    )
    .setAction(
        async (
            { address }: Required<MarketStateParams>,
            { viem, hyperdriveDeploy: { deployments }, network },
        ) => {
            let instance = await viem.getContractAt(
                "IHyperdriveRead",
                address as Address,
            );
            let info = await instance.read.getMarketState();
            console.log(info);
        },
    );
