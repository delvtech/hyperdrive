import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import "./tasks";
import { SAMPLE_HYPERDRIVE } from "./tasks/deploy/config/sample";

const { env } = process;
const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.20",
        settings: {
            optimizer: {
                enabled: true,
                runs: 10_000_000,
            },
            evmVersion: "paris",
        },
    },
    namedAccounts: {
        deployer: {
            default: 0,
        },
    },
    networks: {
        hardhat: {
            accounts: [
                {
                    privateKey: env.PRIVATE_KEY!,
                    balance: "1000000000000000000",
                },
            ],
            hyperdriveDeploy: SAMPLE_HYPERDRIVE,
        },
        sepolia: {
            chainId: 11155111,
            accounts: [env.PRIVATE_KEY!],
            url: env.SEPOLIA_RPC_URL!,
            verify: {
                etherscan: {
                    apiKey: env.ETHERSCAN_API_KEY!,
                },
            },
            live: true,

            hyperdriveDeploy: SAMPLE_HYPERDRIVE,
        },
    },
    etherscan: {
        apiKey: {
            sepolia: env.ETHERSCAN_API_KEY!,
        },
    },
};

export default config;
