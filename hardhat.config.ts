import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import "./tasks";
import {
    SAMPLE_COORDINATOR,
    SAMPLE_FACTORY,
    SAMPLE_INSTANCE,
} from "./tasks/deploy/config/sample";
import {
    SEPOLIA_DAI_14DAY,
    SEPOLIA_ERC4626_COORDINATOR,
    SEPOLIA_FACTORY,
} from "./tasks/deploy/config/sepolia";

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
            hyperdriveDeploy: {
                factories: [SEPOLIA_FACTORY],
                coordinators: [SEPOLIA_ERC4626_COORDINATOR],
                instances: [SEPOLIA_DAI_14DAY],
            },
        },
        localhost: {
            url: "http://127.0.0.1:8545/",
            accounts: [env.PRIVATE_KEY!],
            hyperdriveDeploy: {
                factories: [SAMPLE_FACTORY],
                coordinators: [SAMPLE_COORDINATOR],
                instances: [SAMPLE_INSTANCE],
            },
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
            hyperdriveDeploy: {
                factories: [SEPOLIA_FACTORY],
                coordinators: [SEPOLIA_ERC4626_COORDINATOR],
                instances: [SEPOLIA_DAI_14DAY],
            },
        },
    },
    etherscan: {
        apiKey: {
            sepolia: env.ETHERSCAN_API_KEY!,
        },
    },
};

export default config;
