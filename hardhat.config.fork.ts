import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import "./tasks";
import {
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
    solidity: {
        version: "0.8.20",
        settings: {
            viaIR: false,
            optimizer: {
                enabled: true,
                runs: 10000000,
            },
            evmVersion: "paris",
            metadata: {
                useLiteralContent: true,
            },
        },
    },
    namedAccounts: {
        deployer: {
            default: 0,
        },
    },
    paths: {
        artifacts: "./artifacts",
    },
    networks: {
        mainnet_fork: {
            live: false,
            url: env.HYPERDRIVE_ETHEREUM_URL,
            accounts: [env.DEPLOYER_PRIVATE_KEY ?? DEFAULT_PK],
            hyperdriveDeploy: {
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
    etherscan: {
        apiKey: env.ETHERSCAN_API_KEY ?? "",
    },
};

export default config;
