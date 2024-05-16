import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import "./tasks";
import {
    SEPOLIA_DAI_14DAY,
    SEPOLIA_DAI_30DAY,
    SEPOLIA_ERC4626_COORDINATOR,
    SEPOLIA_FACTORY,
} from "./tasks/deploy/config/";
// import {
//     SAMPLE_COORDINATOR,
//     SAMPLE_FACTORY,
//     SAMPLE_INSTANCE,
// } from "./tasks/deploy/config/sample";

const { env } = process;
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
                instances: [SEPOLIA_DAI_14DAY, SEPOLIA_DAI_30DAY],
            },
        },
        // localhost: {
        //     url: "http://127.0.0.1:8545/",
        //     accounts: [env.PRIVATE_KEY!],
        //     hyperdriveDeploy: {
        //         factories: [SAMPLE_FACTORY],
        //         coordinators: [SAMPLE_COORDINATOR],
        //         instances: [SAMPLE_INSTANCE],
        //     },
        // },
        sepolia: {
            chainId: 11155111,
            accounts: [env.PRIVATE_KEY!],
            url: env.SEPOLIA_RPC_URL!,
            verify: {
                etherscan: {
                    apiKey: env.ETHERSCAN_API_KEY!,
                    apiUrl: "https://api-sepolia.etherscan.io",
                },
            },
            live: true,
            hyperdriveDeploy: {
                factories: [SEPOLIA_FACTORY],
                coordinators: [SEPOLIA_ERC4626_COORDINATOR],
                instances: [SEPOLIA_DAI_14DAY, SEPOLIA_DAI_30DAY],
            },
        },
        // base_sepolia: {
        //     accounts: [env.PRIVATE_KEY!],
        //     url: env.BASE_SEPOLIA_RPC_URL!,
        //     verify: {
        //         etherscan: {
        //             apiKey: env.ETHERSCAN_BASE_API_KEY!,
        //             apiUrl: "https://api-sepolia.basescan.org",
        //         },
        //     },
        //     live: true,
        //     hyperdriveDeploy: {
        //         factories: [SEPOLIA_FACTORY],
        //         coordinators: [
        //             SEPOLIA_ERC4626_COORDINATOR,
        //             SEPOLIA_STETH_COORDINATOR,
        //             SEPOLIA_RETH_COORDINATOR,
        //             SEPOLIA_EZETH_COORDINATOR,
        //         ],
        //         instances: [
        //             SEPOLIA_DAI_14DAY,
        //             SEPOLIA_DAI_30DAY,
        //             SEPOLIA_STETH_14DAY,
        //             SEPOLIA_STETH_30DAY,
        //             SEPOLIA_RETH_14DAY,
        //             SEPOLIA_RETH_30DAY,
        //             SEPOLIA_EZETH_14DAY,
        //             SEPOLIA_EZETH_30DAY,
        //         ],
        //     },
        // },
    },
    etherscan: {
        apiKey: env.ETHERSCAN_API_KEY!,
    },
};

export default config;
