import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import "./tasks";
import {
  ERC4626InstanceDeployConfigInput,
  FactoryDeployConfigInput,
  StETHInstanceDeployConfigInput,
} from "./tasks";
import { RETHInstanceDeployConfigInput } from "./tasks/deploy/instances/reth";
import { EzETHInstanceDeployConfigInput } from "./tasks/deploy/instances/ezeth";

const TEST_FACTORY: FactoryDeployConfigInput = {
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
};

const TEST_ERC4626: ERC4626InstanceDeployConfigInput = {
  name: "TEST_ERC4626",
  deploymentId: "0x666",
  salt: "0x694201",
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
};

const TEST_STETH: StETHInstanceDeployConfigInput = {
  name: "TEST_STETH",
  deploymentId: "0x66666661",
  salt: "0x6942011",
  contribution: "0.01",
  fixedAPR: "0.5",
  timestretchAPR: "0.5",
  options: {
    // destination: "0xsomeone",
    asBase: false,
    // extraData: "0x",
  },
  poolDeployConfig: {
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
};

const TEST_EZETH: EzETHInstanceDeployConfigInput = {
  name: "TEST_EZETH",
  deploymentId: "0xabbabac",
  salt: "0x69420",
  contribution: "0.1",
  fixedAPR: "0.5",
  timestretchAPR: "0.5",
  options: {
    // destination: "0xsomeone",
    asBase: false,
    // extraData: "0x",
  },
  poolDeployConfig: {
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
};

const TEST_RETH: RETHInstanceDeployConfigInput = {
  name: "TEST_RETH",
  deploymentId: "0x665",
  salt: "0x69420111232",
  contribution: "0.01",
  fixedAPR: "0.5",
  timestretchAPR: "0.5",
  options: {
    // destination: "0xsomeone",
    asBase: false,
    // extraData: "0x",
  },
  poolDeployConfig: {
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
};

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
        { privateKey: env.PRIVATE_KEY!, balance: "1000000000000000000" },
      ],
      factory: TEST_FACTORY,
      // coordinators: {
      //   reth: "0x....",
      //   lido: "0x...."
      // },
      instances: {
        erc4626: [TEST_ERC4626],
        steth: [TEST_STETH],
        reth: [TEST_RETH],
        ezeth: [TEST_EZETH],
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
      factory: TEST_FACTORY,
      // coordinators: {
      //   reth: "0x....",
      //   lido: "0x...."
      // },
      instances: {
        erc4626: [TEST_ERC4626],
        steth: [TEST_STETH],
        reth: [TEST_RETH],
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
