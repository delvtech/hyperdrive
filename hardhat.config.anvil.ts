import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import baseConfig from "./hardhat.config";
import "./tasks";
import {
    ANVIL_CHECKPOINT_REWARDER,
    ANVIL_CHECKPOINT_SUBREWARDER,
    ANVIL_ERC4626_COORDINATOR,
    ANVIL_ERC4626_HYPERDRIVE,
    ANVIL_FACTORY,
    ANVIL_STETH_COORDINATOR,
    ANVIL_STETH_HYPERDRIVE,
} from "./tasks/deploy/config/anvil";

const { env } = process;
let DEFAULT_PK =
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

const config: HardhatUserConfig = {
    ...baseConfig,
    networks: {
        anvil: {
            live: false,
            url: env.HYPERDRIVE_ETHEREUM_URL ?? "http://127.0.0.1:8545",
            accounts: [env.DEPLOYER_PRIVATE_KEY ?? DEFAULT_PK],
            hyperdriveDeploy: {
                checkpointRewarders: [ANVIL_CHECKPOINT_REWARDER],
                checkpointSubrewarders: [ANVIL_CHECKPOINT_SUBREWARDER],
                factories: [ANVIL_FACTORY],
                coordinators: [
                    ANVIL_ERC4626_COORDINATOR,
                    ANVIL_STETH_COORDINATOR,
                ],
                instances: [ANVIL_ERC4626_HYPERDRIVE, ANVIL_STETH_HYPERDRIVE],
            },
        },
    },
};

export default config;
