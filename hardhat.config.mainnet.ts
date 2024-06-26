import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import baseConfig from "./hardhat.config";
import "./tasks";
import {
    MAINNET_DAI_14DAY,
    MAINNET_DAI_30DAY,
    MAINNET_ERC4626_COORDINATOR,
    MAINNET_FACTORY,
    MAINNET_STETH_14DAY,
    MAINNET_STETH_30DAY,
    MAINNET_STETH_COORDINATOR,
} from "./tasks/deploy/config/mainnet";

// FIXME: Don't need this.
const { env } = process;
let DEFAULT_PK =
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

const config: HardhatUserConfig = {
    ...baseConfig,
    networks: {
        mainnet_fork: {
            live: false,
            // FIXME: Don't need the default.
            url: env.HYPERDRIVE_ETHEREUM_URL ?? "http://anvil:8545",
            accounts: [env.DEPLOYER_PRIVATE_KEY ?? DEFAULT_PK],
            hyperdriveDeploy: {
                factories: [MAINNET_FACTORY],
                coordinators: [
                    MAINNET_ERC4626_COORDINATOR,
                    MAINNET_STETH_COORDINATOR,
                ],
                instances: [
                    MAINNET_DAI_14DAY,
                    MAINNET_DAI_30DAY,
                    MAINNET_STETH_14DAY,
                    MAINNET_STETH_30DAY,
                ],
            },
        },
    },
};

export default config;
