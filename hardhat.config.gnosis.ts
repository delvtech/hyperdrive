import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import baseConfig from "./hardhat.config";
import "./tasks";
import {
    GNOSIS_CHAINLINK_COORDINATOR,
    GNOSIS_ERC4626_COORDINATOR,
    GNOSIS_FACTORY,
    GNOSIS_SXDAI_182DAY,
    GNOSIS_WSTETH_182DAY,
} from "./tasks/deploy/config/gnosis";

const { env } = process;

const config: HardhatUserConfig = {
    ...baseConfig,
    networks: {
        gnosis: {
            live: true,
            chainId: 100,
            url: env.HYPERDRIVE_ETHEREUM_URL!,
            accounts: [env.DEPLOYER_PRIVATE_KEY!, env.PAUSER_PRIVATE_KEY!],
            hyperdriveDeploy: {
                factories: [GNOSIS_FACTORY],
                coordinators: [
                    GNOSIS_CHAINLINK_COORDINATOR,
                    GNOSIS_ERC4626_COORDINATOR,
                ],
                instances: [GNOSIS_WSTETH_182DAY, GNOSIS_SXDAI_182DAY],
                checkpointRewarders: [],
                checkpointSubrewarders: [],
            },
        },
    },
    etherscan: {
        customChains: [
            {
                network: "gnosis",
                chainId: 100,
                urls: {
                    apiURL: "https://api.gnosisscan.io/api",
                    browserURL: "https://gnosisscan.io/",
                },
            },
        ],
        apiKey: {
            gnosis: env.GNOSISSCAN_API_KEY ?? "",
        },
    },
};

export default config;
