import { HardhatUserConfig, task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-foundry";
import "hardhat-deploy";
import "@nomicfoundation/hardhat-ignition-viem";
import "dotenv/config";
import "./tasks";

const { env } = process;
const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 10_000_000,
      },
    },
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  networks: {
    sepolia: {
      accounts: [env.PRIVATE_KEY!],
      url: env.SEPOLIA_RPC_URL!,
      verify: {
        etherscan: {
          apiKey: env.ETHERSCAN_API_KEY!,
        },
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
