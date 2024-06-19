import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import "./tasks";
import {
    SEPOLIA_CHECKPOINT_REWARDER,
    SEPOLIA_CHECKPOINT_SUBREWARDER,
    SEPOLIA_DAI_14DAY,
    SEPOLIA_DAI_30DAY,
    SEPOLIA_ERC4626_COORDINATOR,
    SEPOLIA_EZETH_14DAY,
    SEPOLIA_EZETH_30DAY,
    SEPOLIA_EZETH_COORDINATOR,
    SEPOLIA_FACTORY,
    SEPOLIA_RETH_14DAY,
    SEPOLIA_RETH_30DAY,
    SEPOLIA_RETH_COORDINATOR,
    SEPOLIA_STETH_14DAY,
    SEPOLIA_STETH_30DAY,
    SEPOLIA_STETH_COORDINATOR,
} from "./tasks/deploy/config/";

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
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY ?? "",
    },
    networks: {
        hardhat: {
            accounts: [
                {
                    privateKey: env.PRIVATE_KEY ?? DEFAULT_PK,
                    balance: "1000000000000000000",
                },
            ],
            hyperdriveDeploy: {
                checkpointRewarders: [SEPOLIA_CHECKPOINT_REWARDER],
                checkpointSubrewarders: [SEPOLIA_CHECKPOINT_SUBREWARDER],
                factories: [SEPOLIA_FACTORY],
                coordinators: [
                    SEPOLIA_ERC4626_COORDINATOR,
                    SEPOLIA_STETH_COORDINATOR,
                    SEPOLIA_RETH_COORDINATOR,
                    SEPOLIA_EZETH_COORDINATOR,
                ],
                instances: [
                    SEPOLIA_DAI_14DAY,
                    SEPOLIA_DAI_30DAY,
                    SEPOLIA_EZETH_14DAY,
                    SEPOLIA_EZETH_30DAY,
                    SEPOLIA_RETH_14DAY,
                    SEPOLIA_RETH_30DAY,
                    SEPOLIA_STETH_14DAY,
                    SEPOLIA_STETH_30DAY,
                ],
            },
        },
    },
};

export default config;
