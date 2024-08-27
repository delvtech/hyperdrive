import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import baseConfig from "./hardhat.config";
import "./tasks";
import {
    LINEA_EZETH_182DAY,
    LINEA_EZETH_COORDINATOR,
    LINEA_FACTORY,
} from "./tasks/deploy/config/linea";

const { env } = process;

const config: HardhatUserConfig = {
    ...baseConfig,
    networks: {
        linea: {
            live: true,
            url: env.HYPERDRIVE_ETHEREUM_URL!,
            accounts: [env.DEPLOYER_PRIVATE_KEY!, env.PAUSER_PRIVATE_KEY!],
            hyperdriveDeploy: {
                factories: [LINEA_FACTORY],
                coordinators: [LINEA_EZETH_COORDINATOR],
                instances: [LINEA_EZETH_182DAY],
                checkpointRewarders: [],
                checkpointSubrewarders: [],
            },
        },
    },
};

export default config;
