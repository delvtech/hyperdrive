import { HardhatUserConfig, task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-foundry";
import "hardhat-deploy";
import "dotenv/config";
import "./tasks";
import {
  ERC4626InstanceDeployConfigInput,
  FactoryDeployConfigInput,
  StETHInstanceDeployConfigInput,
} from "./tasks";
import { RETHInstanceDeployConfigInput } from "./tasks/deploy/instances/reth";

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
  deploymentId: "0xabbabacc",
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

const ANVIL_FACTORY = {
  //   ARG ADMIN
  // ARG IS_COMPETITION_MODE
  // ARG BASE_TOKEN_NAME
  // ARG BASE_TOKEN_SYMBOL
  // ARG BASE_TOKEN_DECIMALS
  // ARG VAULT_NAME
  // ARG VAULT_SYMBOL
  // ARG VAULT_STARTING_RATE
  // ARG LIDO_STARTING_RATE
  // ARG FACTORY_CHECKPOINT_DURATION
  // ARG FACTORY_MIN_CHECKPOINT_DURATION
  // ARG FACTORY_MAX_CHECKPOINT_DURATION
  // ARG FACTORY_MIN_POSITION_DURATION
  // ARG FACTORY_MAX_POSITION_DURATION
  // ARG FACTORY_MIN_FIXED_APR
  // ARG FACTORY_MAX_FIXED_APR
  // ARG FACTORY_MIN_TIME_STRETCH_APR
  // ARG FACTORY_MAX_TIME_STRETCH_APR
  // ARG FACTORY_MIN_CURVE_FEE
  // ARG FACTORY_MIN_FLAT_FEE
  // ARG FACTORY_MIN_GOVERNANCE_LP_FEE
  // ARG FACTORY_MIN_GOVERNANCE_ZOMBIE_FEE
  // ARG FACTORY_MAX_CURVE_FEE
  // ARG FACTORY_MAX_FLAT_FEE
  // ARG FACTORY_MAX_GOVERNANCE_LP_FEE
  // ARG FACTORY_MAX_GOVERNANCE_ZOMBIE_FEE
  // ARG ERC4626_HYPERDRIVE_CONTRIBUTION
  // ARG ERC4626_HYPERDRIVE_FIXED_APR
  // ARG ERC4626_HYPERDRIVE_TIME_STRETCH_APR
  // ARG ERC4626_HYPERDRIVE_MINIMUM_SHARE_RESERVES
  // ARG ERC4626_HYPERDRIVE_MINIMUM_TRANSACTION_AMOUNT
  // ARG ERC4626_HYPERDRIVE_POSITION_DURATION
  // ARG ERC4626_HYPERDRIVE_CHECKPOINT_DURATION
  // ARG ERC4626_HYPERDRIVE_CURVE_FEE
  // ARG ERC4626_HYPERDRIVE_FLAT_FEE
  // ARG ERC4626_HYPERDRIVE_GOVERNANCE_LP_FEE
  // ARG ERC4626_HYPERDRIVE_GOVERNANCE_ZOMBIE_FEE
  // ARG STETH_HYPERDRIVE_CONTRIBUTION
  // ARG STETH_HYPERDRIVE_FIXED_APR
  // ARG STETH_HYPERDRIVE_TIME_STRETCH_APR
  // ARG STETH_HYPERDRIVE_MINIMUM_SHARE_RESERVES
  // ARG STETH_HYPERDRIVE_MINIMUM_TRANSACTION_AMOUNT
  // ARG STETH_HYPERDRIVE_POSITION_DURATION
  // ARG STETH_HYPERDRIVE_CHECKPOINT_DURATION
  // ARG STETH_HYPERDRIVE_CURVE_FEE
  // ARG STETH_HYPERDRIVE_FLAT_FEE
  // ARG STETH_HYPERDRIVE_GOVERNANCE_LP_FEE
  // ARG STETH_HYPERDRIVE_GOVERNANCE_ZOMBIE_FEE
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
