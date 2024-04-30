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
    hardhat: {
      accounts: [
        { privateKey: env.PRIVATE_KEY!, balance: "1000000000000000000" },
      ],
      factory: {
        governance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
        hyperdriveGovernance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
        defaultPausers: ["0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8"],
        feeCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
        sweepCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
        checkpointDurationResolution: "8 hours",
        minCheckpointDuration: "24 hours",
        maxCheckpointDuration: "24 hours",
        minPositionDuration: "7 days",
        maxPositionDuration: "30 days",
        minFixedAPR: "0.01",
        maxFixedAPR: "0.6",
        minTimeStretchAPR: "0.01",
        maxTimeStretchAPR: "0.6",
        minFees: {
          curve: "0.001",
          flat: "0.0001",
          governanceLP: "0.15",
          governanceZombie: "0.03",
        },
        maxFees: {
          curve: "0.01",
          flat: "0.001",
          governanceLP: "0.15",
          governanceZombie: "0.03",
        },
      },
      // coordinators: {
      //   reth: "0x....",
      //   lido: "0x...."
      // },
      instances: {
        erc4626: [
          {
            name: "TESTERC4626",
            deploymentId: "0xabbabac",
            salt: "0x69420",
            contribution: "0.1",
            fixedAPR: "0.5",
            timestretchAPR: "0.5",
            options: {
              // destination: "0xsomeone",
              asBase: true,
              // extraData: "0x",
            },
            poolDeployConfig: {
              // baseToken: "0x...",
              // vaultSharesToken: "0x...",
              minimumShareReserves: "0.001",
              minimumTransactionAmount: "0.001",
              positionDuration: "30 days",
              checkpointDuration: "1 day",
              timeStretch: "0",
              governance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
              feeCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
              sweepCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
              fees: {
                curve: "0.001",
                flat: "0.0001",
                governanceLP: "0.15",
                governanceZombie: "0.03",
              },
            },
          },
        ],
      },
    },
    sepolia: {
      accounts: [env.PRIVATE_KEY!],
      url: env.SEPOLIA_RPC_URL!,
      verify: {
        etherscan: {
          apiKey: env.ETHERSCAN_API_KEY!,
        },
      },
      factory: {
        governance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
        hyperdriveGovernance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
        defaultPausers: ["0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8"],
        feeCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
        sweepCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
        checkpointDurationResolution: "8 hours",
        minCheckpointDuration: "24 hours",
        maxCheckpointDuration: "24 hours",
        minPositionDuration: "7 days",
        maxPositionDuration: "30 days",
        minFixedAPR: "0.01",
        maxFixedAPR: "0.6",
        minTimeStretchAPR: "0.01",
        maxTimeStretchAPR: "0.6",
        minFees: {
          curve: "0.001",
          flat: "0.0001",
          governanceLP: "0.15",
          governanceZombie: "0.03",
        },
        maxFees: {
          curve: "0.01",
          flat: "0.001",
          governanceLP: "0.15",
          governanceZombie: "0.03",
        },
      },
      // coordinators: {
      //   reth: "0x....",
      //   lido: "0x...."
      // },
      instances: {
        erc4626: [
          {
            name: "TESTERC4626",
            deploymentId: "0xabbabac",
            salt: "0x69420",
            contribution: "0.1",
            fixedAPR: "0.5",
            timestretchAPR: "0.5",
            options: {
              // destination: "0xsomeone",
              asBase: true,
              // extraData: "0x",
            },
            poolDeployConfig: {
              // baseToken: "0x...",
              // vaultSharesToken: "0x...",
              minimumShareReserves: "0.001",
              minimumTransactionAmount: "0.001",
              positionDuration: "30 days",
              checkpointDuration: "1 day",
              timeStretch: "0",
              governance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
              feeCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
              sweepCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
              fees: {
                curve: "0.001",
                flat: "0.0001",
                governanceLP: "0.15",
                governanceZombie: "0.03",
              },
            },
          },
        ],
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
