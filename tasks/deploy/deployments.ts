import fs from "fs";
import path from "path";
import { zeroAddress } from "viem";
import { z } from "zod";
import { zAddress } from "./types";

// File used to store live network data
export const DEPLOYMENTS_FILENAME = "deployments.json";

// File used to store local network data
export const LOCAL_FILENAME = "deployments.local.json";
export const LOCAL_NETWORK_NAME = "hardhat";

/**
 * Absolute path to the deployments file
 *
 * We use `__dirname` which gives us the location of this source file.
 * Since tasks can be run from any directory, this is the best point of reference.
 */
export const DEPLOYMENTS_PATH = path.resolve(
    __dirname,
    path.join("../../", DEPLOYMENTS_FILENAME),
);
export const LOCAL_DEPLOYMENTS_PATH = path.resolve(
    __dirname,
    path.join("../../", LOCAL_FILENAME),
);

/** Schema for {@link DeployedContract} */
export const zDeployedContract = z.object({
    contract: z.string().min(1, "contract cannot be empty"),
    address: zAddress.refine((v) => !(v === zeroAddress), {
        message: "address for DeployedContract cannot be the zero address",
    }),
    timestamp: z.string().datetime(),
});

/**
 * Information for a deployed contract. The `contract` field should
 * have a corresponding `.sol` file somewhere in the `/contracts` directory.
 *
 * ```json
 *  {
 *    "contract": "HyperdriveFactory",
 *    "address": "0x0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
 *    "timestamp": "2020-01-01T00:00:00.123Z"
 *  }
 * ```
 */
export type DeployedContract = z.infer<typeof zDeployedContract>;

/** Schema for {@link DeploymentsFile} */
export const zDeployments = z
    .record(
        z.string({ description: "network name" }),
        z.record(
            z.string({ description: "deployed contract name" }),
            zDeployedContract,
        ),
    )
    // Check for duplicate addresses within a network.
    .superRefine((val, ctx) =>
        Object.values(val).forEach(
            (v) =>
                new Set(Object.values(v).map((v) => v.address)).size !=
                    Object.values(v).length &&
                ctx.addIssue({
                    code: "custom",
                    message: `the same address is specified for more than one DeployedContract in the network`,
                }),
        ),
    );

/**
 * Tracks deployed contracts across all networks.
 *
 * ```json
 * {
 *   "sepolia": {
 *     "DAI_SDAI_ERC4626Hyperdrive": {
 *       "contract": "ERC4626Hyperdrive",
 *       "address": "0x0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
 *       "timestamp": "2020-01-01T00:00:00.123Z"
 *     },
 *     "StETHHyperdrive": {
 *       "contract": "StETHHyperdrive",
 *       "address": "0x0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
 *       "timestamp": "2020-01-01T00:00:00.123Z"
 *     }
 *   },
 *   "mainnet": {
 *     // more contracts here...
 *   }
 * }
 * ```
 */
export type DeploymentsFile = z.infer<typeof zDeployments>;

/**
 * Logic for interacting with the {@link DeploymentsFile}.
 *
 * This class is implemented as a singleton because multiple
 * import locations could result in multiple instances that
 * may compete for filesystem access.
 */
export class Deployments {
    static #instance: Deployments;

    #f: DeploymentsFile;

    private constructor() {
        if (!fs.existsSync(DEPLOYMENTS_PATH))
            fs.writeFileSync(DEPLOYMENTS_PATH, "{}");
        if (!fs.existsSync(LOCAL_DEPLOYMENTS_PATH))
            fs.writeFileSync(LOCAL_DEPLOYMENTS_PATH, "{}");
        this.#f = zDeployments.parse(
            JSON.parse(fs.readFileSync(DEPLOYMENTS_PATH).toString()),
        );
    }

    static get() {
        if (!Deployments.#instance) {
            Deployments.#instance = new Deployments();
        }
        return Deployments.#instance;
    }

    /**
     * Returns a list of {@link DeployedContract}s for the specified network.
     *
     * The unique name for each deployed contract is included.
     */
    byNetwork(network: string): (DeployedContract & { name: string })[] {
        return network in this.#f
            ? Object.entries(this.#f[network]).map(([k, v]) => ({
                  name: k,
                  ...v,
              }))
            : [];
    }

    /**
     * Returns the {@link DeployedContract} throwing if it does not exist.
     */
    byName(name: string, network: string) {
        if (!(network in this.#f) || !(name in this.#f[network]))
            throw new Error(`contract not found`);
        return this.#f[network][name];
    }

    /**
     * Returns whether a {@link DeployedContract} or undefined if it does not exist.
     */
    byNameSafe(name: string, network: string) {
        try {
            return this.byName(name, network);
        } catch (e) {}
    }

    /**
     * Returns a list of {@link DeployedContract}s that have the specified source contract.
     */
    byContract(contract: string, network?: string) {
        return Object.entries(this.#f)
            .filter(([k, _]) => (network ? k === network : true))
            .flatMap(([_, v]) => Object.values(v))
            .filter((dc) => dc.contract === contract);
    }

    /**
     * Returns the specified {@link DeployedContract} throwing if it does not exist.
     */
    byAddress(address: string, network: string) {
        let contract = Object.entries(this.#f)
            .filter(([k, _]) => (network ? k === network : false))
            .flatMap(([_, v]) => Object.values(v))
            .find((dc) => dc.address === address);
        if (!contract) throw new Error("contract not found");
    }

    /**
     * Returns the specified {@link DeployedContract} or undefined if it does not exist.
     */
    byAddressSafe(address: string, network: string) {
        return Object.entries(this.#f)
            .filter(([k, _]) => (network ? k === network : false))
            .flatMap(([_, v]) => Object.values(v))
            .find((dc) => dc.address === address);
    }

    /**
     * Parses the deployed contract information and adds it to the file.
     *
     * NOTE: Throws an error if the parsed information or the resulting
     * deployments file is invalid.
     */
    add(name: string, contract: string, address: string, network: string) {
        let parsed = zDeployedContract.parse({
            contract,
            address,
            timestamp: new Date().toISOString(),
        });
        if (!(network in this.#f)) this.#f[network] = {};
        this.#f[network][name] = parsed;
        this.#updateFile(network);
    }

    /**
     * Removes the {@link DeployedContract} with the specified name and network.
     *
     * NOTE: This function does not throw when the contract is not present.
     */
    remove(name: string, network: string) {
        if (this.byName(name, network)) {
            delete this.#f[network][name];
            this.#updateFile(network);
        }
    }

    /**
     * Write the current {@link DeploymentsFile} object to disk.
     */
    #updateFile(network: string) {
        let isLocal = network == LOCAL_NETWORK_NAME;
        let data = isLocal
            ? {
                  [LOCAL_NETWORK_NAME]: this.#f[LOCAL_NETWORK_NAME],
              }
            : this.#f;
        try {
            fs.writeFileSync(
                isLocal ? LOCAL_DEPLOYMENTS_PATH : DEPLOYMENTS_PATH,
                JSON.stringify(zDeployments.parse(data), null, 4),
            );
        } catch (e) {
            console.error(e);
            console.error(this.#f);
            throw e;
        }
    }
}
