import dayjs from "dayjs";
import _duration from "dayjs/plugin/duration";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Address, Hex, parseEther, toHex } from "viem";
import {
    CREATE_X_FACTORY,
    CREATE_X_FACTORY_DEPLOYER,
    CREATE_X_PRESIGNED_TRANSACTION,
} from "./constants";
import { HyperdriveDeployRuntimeOptions } from "./environment-extensions";
import {
    DurationString,
    ExtractValueOrHREFn,
    ValueOrHREFn,
    parseDuration,
} from "./types";

dayjs.extend(_duration);

/**
 * Deploys the CreateX contract on anvil networks if it hasn't already been
 * deployed.
 */
export async function deployCreateX(hre: HardhatRuntimeEnvironment) {
    // If the network is anvil, we need to deploy the CREATEX factory if it
    // hasn't been deployed before.
    let pc = await hre.viem.getPublicClient();
    let bytecode = await pc.getBytecode({
        address: CREATE_X_FACTORY as Address,
    });
    if (hre.network.name == "anvil" && !bytecode) {
        let tc = await hre.viem.getTestClient();
        await tc.setBalance({
            value: parseEther("1"),
            address: CREATE_X_FACTORY_DEPLOYER,
        });
        let wc = await hre.viem.getWalletClient(CREATE_X_FACTORY_DEPLOYER);
        await wc.sendRawTransaction({
            serializedTransaction: CREATE_X_PRESIGNED_TRANSACTION,
        });
    }
}

/**
 * Generates a 32-byte hex string from the input value.
 */
export function toBytes32(name: string): Hex {
    return toHex(name, { size: 32 });
}

/**
 * Retrieve the linkerFactory and the linkerCodeHash for the factory at the specified address.
 */
export async function getLinkerDetails(
    hre: HardhatRuntimeEnvironment,
    factoryAddress: Address,
) {
    let factory = await hre.viem.getContractAt(
        "HyperdriveFactory",
        factoryAddress,
    );
    let linkerFactory = await factory.read.linkerFactory();
    let linkerCodeHash = await (
        await hre.viem.getContractAt("ERC20ForwarderFactory", linkerFactory)
    ).read.ERC20LINK_HASH();
    return {
        linkerFactory,
        linkerCodeHash,
    };
}

/**
 * Determines whether the supplied input is a value or {@link HardhatRuntimeEnvironment} function.
 * If function, evaluate and return.
 * If value, return unmodified.
 */
export async function evaluateValueOrHREFn<T extends ValueOrHREFn<unknown>>(
    valueOrFunction: T,
    hre: HardhatRuntimeEnvironment,
    options?: HyperdriveDeployRuntimeOptions,
): Promise<ExtractValueOrHREFn<T>> {
    return typeof valueOrFunction === "function"
        ? await valueOrFunction(hre, options)
        : valueOrFunction;
}

/**
 * Converts the input `fee` and `duration` into an annualized fee rate
 */
export function normalizeFee(fee: bigint, duration: DurationString) {
    return (
        fee /
        (BigInt(dayjs.duration(365, "days").asSeconds()) /
            parseDuration(duration))
    );
}
