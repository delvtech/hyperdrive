import { $ } from "bun";
import {
  createPublicClient,
  decodeAbiParameters,
  http,
  parseAbiItem,
  extractChain,
} from "viem";
import { sepolia, mainnet, base, optimism, anvil } from "viem/chains";

// Environment
let env = {
  FOUNDRY_PROFILE: "production",
  FOUNDRY_RPC_URL:
    "https://sepolia.infura.io/v3/448dc10060c6413bbd1129beb4c3c925",
  FOUNDRY_CHAIN_ID: 11155111,
  ETHERSCAN_API_KEY: "B5QYUJZEB31E9MSBTE4TA4HURTD99UQFFP",
  POOL_TYPE: "ERC4626",
  POOL_ADDRESS: "0x392839dA0dACAC790bd825C81ce2c5E264D793a8",
  GOVERNANCE_ADDRESS: "0x338D5634c391ef47FB797417542aa75F4f71A4a6",
} as const;

// Get the chain
const chain = extractChain({
  chains: [sepolia, mainnet, base, optimism, anvil],
  id: env.FOUNDRY_CHAIN_ID,
});

// Verification Flags
const verify_flags = [
  "--watch",
  "--compiler-version",
  "v0.8.20+commit.a1b79de6",
  "--num-of-optimizations",
  "10000000",
  "--evm-version",
  "paris",
];

// Client
let client = createPublicClient({
  transport: http(env.FOUNDRY_RPC_URL),
  chain,
});

// Abi's we're gonna need
const pool_config_struct_abi =
  "(address,address,address,bytes32,uint256,uint256,uint256,uint256,uint256,uint256,address,address,address,(uint256,uint256,uint256,uint256))" as const;
const pool_config_fn_abi =
  `function getPoolConfig() external view returns ${pool_config_struct_abi}` as const;
const constructor_abi =
  `constructor(${pool_config_struct_abi},address,address,address,address,address)` as const;

// Retrieve the pool config
let poolConfig = await client.readContract({
  address: env.POOL_ADDRESS as `0x${string}`,
  abi: [parseAbiItem(pool_config_fn_abi)],
  functionName: "getPoolConfig",
  args: [],
});
let [
  baseToken,
  vaultSharesToken,
  linkerFactory,
  linkerHash,
  initialSharePrice,
  minReserves,
  minTxAmount,
  positionDuration,
  checkpointDuration,
  timeStretch,
  governance,
  feeCollector,
  swapCollector,
  fees,
] = poolConfig;

// Get the targets

let targets = await client.multicall({
  contracts: [
    {
      functionName: "target0",
      abi: [parseAbiItem("function target0() external view returns (address)")],
      address: env.POOL_ADDRESS as `0x${string}`,
    },
    {
      functionName: "target1",
      abi: [parseAbiItem("function target1() external view returns (address)")],
      address: env.POOL_ADDRESS as `0x${string}`,
    },
    {
      functionName: "target2",
      abi: [parseAbiItem("function target2() external view returns (address)")],
      address: env.POOL_ADDRESS as `0x${string}`,
    },
    {
      functionName: "target3",
      abi: [parseAbiItem("function target3() external view returns (address)")],
      address: env.POOL_ADDRESS as `0x${string}`,
    },
    {
      functionName: "target4",
      abi: [parseAbiItem("function target4() external view returns (address)")],
      address: env.POOL_ADDRESS as `0x${string}`,
    },
  ],
});

for (let i = 0; i < targets.length; i++) {
  console.log(
    await $`cast abi-encode ${constructor_abi} '(${baseToken},${vaultSharesToken},${linkerFactory},${linkerHash},${initialSharePrice},${minReserves},${minTxAmount},${positionDuration},${checkpointDuration},${timeStretch},${env.GOVERNANCE_ADDRESS},${feeCollector},${swapCollector},(${fees}))'`
  );
  console.log(`forge verify-contract --watch --compiler-version v0.8.20+commit.a1b79de6 --num-of-optimizations 10000000 --evm-version paris --constructor-args \
    ${baseToken} \
    ${vaultSharesToken} \
    ${linkerFactory} \
    ${linkerHash} \
    ${initialSharePrice} \
    ${minReserves} \
    ${minTxAmount} \
    ${positionDuration} \
    ${checkpointDuration} \
    ${timeStretch} \
    ${env.GOVERNANCE_ADDRESS} \
    ${feeCollector} \
    ${swapCollector} \
    "(${fees})" \
    ${targets[i].result} \
    ${env.POOL_TYPE}
  `);
}
