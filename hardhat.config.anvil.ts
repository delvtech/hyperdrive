import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import baseConfig from "./hardhat.config";
import "./tasks";
import {
    SEPOLIA_CHECKPOINT_REWARDER,
    SEPOLIA_CHECKPOINT_SUBREWARDER,
    SEPOLIA_FACTORY,
    SEPOLIA_MORPHO_BLUE_COORDINATOR,
    SEPOLIA_MORPHO_BLUE_DAI_14DAY,
} from "./tasks/deploy/config/sepolia";

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
                checkpointRewarders: [SEPOLIA_CHECKPOINT_REWARDER],
                checkpointSubrewarders: [SEPOLIA_CHECKPOINT_SUBREWARDER],
                factories: [SEPOLIA_FACTORY],
                coordinators: [
                    // SEPOLIA_ERC4626_COORDINATOR,
                    // SEPOLIA_STETH_COORDINATOR,
                    SEPOLIA_MORPHO_BLUE_COORDINATOR,
                ],
                instances: [
                    // SEPOLIA_ERC4626_HYPERDRIVE,
                    // SEPOLIA_STETH_HYPERDRIVE,
                    SEPOLIA_MORPHO_BLUE_DAI_14DAY,
                ],
            },
        },
    },
};

export default config;
