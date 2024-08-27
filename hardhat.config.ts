import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import "./tasks";

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.22",
        settings: {
            viaIR: false,
            optimizer: {
                enabled: true,
                runs: 13000,
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
        pauser: {
            default: 1,
        },
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY ?? "",
    },
    networks: {},
};

export default config;
