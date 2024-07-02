import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import baseConfig from "./hardhat.config";
import "./tasks";
import {
    MAINNET_FORK_CHECKPOINT_REWARDER,
    MAINNET_FORK_CHECKPOINT_SUBREWARDER,
    MAINNET_FORK_DAI_14DAY,
    MAINNET_FORK_DAI_30DAY,
    MAINNET_FORK_ERC4626_COORDINATOR,
    MAINNET_FORK_FACTORY,
    MAINNET_FORK_RETH_14DAY,
    MAINNET_FORK_RETH_30DAY,
    MAINNET_FORK_RETH_COORDINATOR,
    MAINNET_FORK_STETH_14DAY,
    MAINNET_FORK_STETH_30DAY,
    MAINNET_FORK_STETH_COORDINATOR,
} from "./tasks/deploy/config/mainnet-fork";

const { env } = process;
let DEFAULT_PK =
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

const config: HardhatUserConfig = {
    ...baseConfig,
    networks: {
        mainnet_fork: {
            live: false,
            url: env.RPC_URL ?? "http://anvil:8545",
            accounts: [env.ADMIN_PRIVATE_KEY ?? DEFAULT_PK],
            hyperdriveDeploy: {
                checkpointRewarders: [MAINNET_FORK_CHECKPOINT_REWARDER],
                checkpointSubrewarders: [MAINNET_FORK_CHECKPOINT_SUBREWARDER],
                factories: [MAINNET_FORK_FACTORY],
                coordinators: [
                    MAINNET_FORK_ERC4626_COORDINATOR,
                    MAINNET_FORK_STETH_COORDINATOR,
                    MAINNET_FORK_RETH_COORDINATOR,
                ],
                instances: [
                    MAINNET_FORK_DAI_14DAY,
                    MAINNET_FORK_DAI_30DAY,
                    MAINNET_FORK_STETH_14DAY,
                    MAINNET_FORK_STETH_30DAY,
                    MAINNET_FORK_RETH_14DAY,
                    MAINNET_FORK_RETH_30DAY,
                ],
            },
        },
    },
};

export default config;
