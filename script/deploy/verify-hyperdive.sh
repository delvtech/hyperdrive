#!/bin/bash

################################################################################
####
####  _   _
#### | | | |
#### | | | |___  __ _  __ _  ___
#### | | | / __|/ _` |/ _` |/ _ \
#### | |_| \__ \ (_| | (_| |  __/
####  \___/|___/\__,_|\__, |\___|
####                   __/ |
####                  |___/
####
#### # This script verifies a hyperdrive instance and its targets with Etherscan.
####
#### Using a '.env' file:
####
#### The following parameters MUST be supplied:
####
#### 1. FOUNDRY_PROFILE    - EX: "production"
#### 2. RPC_URL            - EX: "https://mainnet.infura.io/v3/<your_api_key>"
#### 3. CHAIN_ID
#### 4. ETHERSCAN_API_KEY
#### 5. POOL_TYPE          - Must be one of "ERC4626" | "EzETH" | "LsETH" | "RETH" | "StETH"
#### 6. POOL_ADDRESS
#### 7. GOVERNANCE_ADDRESS
####
#### Both positional arguments and environment variables are supported,
#### with arguments having priority.
####
#### EXAMPLES
####
#### Environment:
####
####            source .sepolia_dai_10day.env && ./script/verify-hyperdrive.sh
####
#### Arguments:
####
####            ./script/verify-hyperdrive.sh \
####              <foundry_profile> \
####              <rpc_url> \
####              <chain_id> \
####              <etherscan_api_key> \
####              <pool_type> \
####              <pool_address> \
####              <gov_address> \
####
################################################################################

FOUNDRY_PROFILE="${1:-$FOUNDRY_PROFILE}"
FOUNDRY_RPC_URL="${2:-$FOUNDRY_RPC_URL}"
FOUNDRY_CHAIN_ID="${3:-$FOUNDRY_CHAIN_ID}"
ETHERSCAN_API_KEY="${4:-$ETHERSCAN_API_KEY}"
POOL_TYPE="${5:-$POOL_TYPE}"
POOL_ADDRESS="${6:-$POOL_ADDRESS}"
GOVERNANCE_ADDRESS="${7:-$GOVERNANCE_ADDRESS}"

echo "FOUNDRY_PROFILE=${FOUNDRY_PROFILE}"
echo "FOUNDRY_RPC_URL=${FOUNDRY_RPC_URL}"
echo "FOUNDRY_CHAIN_ID=${FOUNDRY_CHAIN_ID}"
echo "ETHERSCAN_API_KEY=${ETHERSCAN_API_KEY}"
echo "POOL_TYPE=${POOL_TYPE}"
echo "POOL_ADDRESS=${POOL_ADDRESS}"
echo "GOVERNANCE_ADDRESS=${GOVERNANCE_ADDRESS}"

################################################################################
# ______      __            _ _
# |  _  \    / _|          | | |
# | | | |___| |_ __ _ _   _| | |_ ___
# | | | / _ \  _/ _` | | | | | __/ __|
# | |/ /  __/ || (_| | |_| | | |_\__ \
# |___/ \___|_| \__,_|\__,_|_|\__|___/
#
# Variables that shouldn't change run-to-run, modify this script to update them
#
################################################################################

verify_flags=(
  --watch
  --compiler-version
  "v0.8.20+commit.a1b79de6"
  --num-of-optimizations
  10000000
  --evm-version
  paris
)

#################################################################################
# ______           _   _____              __ _
# | ___ \         | | /  __ \            / _(_)
# | |_/ /__   ___ | | | /  \/ ___  _ __ | |_ _  __ _
# |  __/ _ \ / _ \| | | |    / _ \| '_ \|  _| |/ _` |
# | | | (_) | (_) | | | \__/\ (_) | | | | | | | (_| |
# \_|  \___/ \___/|_|  \____/\___/|_| |_|_| |_|\__, |
#                                               __/ |
#                                              |___/
#
# The IHyperdrive.PoolConfig struct is a constructor argument
# for all targets and the Hyperdrive instance. The only field modified
# during deployment or soon after is the governance address, however the
# rest of the fields can be read from what is on-chain and used to populate
# the constructor arguments for verification.
#
################################################################################

# Retrieve the current PoolConfig from the deployed Hyperdrive instance.
pool_config_abi="(address,address,address,bytes32,uint256,uint256,uint256,uint256,uint256,uint256,address,address,address,(uint256,uint256,uint256,uint256))"
config=($(cast call ${POOL_ADDRESS} "getPoolConfig()${pool_config_abi}" --rpc-url ${FOUNDRY_RPC_URL} --chain-id ${FOUNDRY_CHAIN_ID}))
echo "POOL_CONFIG=${config[*]}"

# Extract the individual fields from the PoolConfig.
# - Sometimes indices are skipped in the array because `cast` returns
# 	two values when representing uint256's: decimal and scientific notation.
# - Unfortunately, `abi-encode` cannot parse scientific notation,
# 	so we must obtain the decimal value from the output.
base_token=${config[0]}
vault_shares_token=${config[1]}
linker_factory=${config[2]}
linker_hash=${config[3]}
initial_share_price=${config[4]}
min_reserves=${config[6]}
min_tx_amount=${config[8]}
position_duration=${config[10]}
checkpoint_duration=${config[12]}
time_stretch=${config[14]}
governance=${GOVERNANCE_ADDRESS}
fee_collector=${config[17]}
swap_collector=${config[18]}
curve_fee=${config[19]:1} # remove leading parenthesis that gets picked up
flat_fee=${config[21]}
lp_fee=${config[23]}
zombie_fee=${config[25]}

# ABI encode the values of our PoolConfig.
#
# NOTE: When ABI encoding functions, typically a 4 byte signature based on the function name is included.
#       With constructors this is not the case, and no function signature is included.
encoded_pool_config=$(
  cast \
    abi-encode \
    "constructor${pool_config_abi}" \
    ${base_token} \
    ${vault_shares_token} \
    ${linker_factory} \
    ${linker_hash} \
    ${initial_share_price} \
    ${min_reserves} \
    ${min_tx_amount} \
    ${position_duration} \
    ${checkpoint_duration} \
    ${time_stretch} \
    ${governance} \
    ${fee_collector} \
    ${swap_collector} \
    "(${curve_fee},${flat_fee},${lp_fee},${zombie_fee})" # Structs/Tuples must be passed in as a singular, non-ABI-encoded values.
)

echo "ENCODED_POOL_CONFIG=${encoded_pool_config}"
################################################################################
#
#  _____                    _
# |_   _|                  | |
#   | | __ _ _ __ __ _  ___| |_ ___
#   | |/ _` | '__/ _` |/ _ \ __/ __|
#   | | (_| | | | (_| |  __/ |_\__ \
#   \_/\__,_|_|  \__, |\___|\__|___/
#                 __/ |
#                |___/
#
# Retrieve the target addresses from the Hyperdrive instance.
# Verify each target by passing in the ABI encoded PoolConfig.
#
################################################################################

# Obtain the list of target addresses from the Hyperdrive instance.
targets=(
  $(cast call ${POOL_ADDRESS} "target0()(address)" --rpc-url ${FOUNDRY_RPC_URL} --chain-id ${FOUNDRY_CHAIN_ID})
  $(cast call ${POOL_ADDRESS} "target1()(address)" --rpc-url ${FOUNDRY_RPC_URL} --chain-id ${FOUNDRY_CHAIN_ID})
  $(cast call ${POOL_ADDRESS} "target2()(address)" --rpc-url ${FOUNDRY_RPC_URL} --chain-id ${FOUNDRY_CHAIN_ID})
  $(cast call ${POOL_ADDRESS} "target3()(address)" --rpc-url ${FOUNDRY_RPC_URL} --chain-id ${FOUNDRY_CHAIN_ID})
  $(cast call ${POOL_ADDRESS} "target4()(address)" --rpc-url ${FOUNDRY_RPC_URL} --chain-id ${FOUNDRY_CHAIN_ID})
)

# Verify each target.
for idx in "${!targets[@]}"; do
  forge verify-contract \
    ${verify_flags[*]} \
    --constructor-args "${encoded_pool_config}" \
    --chain-id "${FOUNDRY_CHAIN_ID}" \
    "${targets[$idx]}" \
    "${POOL_TYPE}Target${idx}"
done

echo "TARGETS=${config[*]}"

################################################################################
#
#  _   _                          _      _
# | | | |                        | |    (_)
# | |_| |_   _ _ __   ___ _ __ __| |_ __ ___   _____
# |  _  | | | | '_ \ / _ \ '__/ _` | '__| \ \ / / _ \
# | | | | |_| | |_) |  __/ | | (_| | |  | |\ V /  __/
# \_| |_/\__, | .__/ \___|_|  \__,_|_|  |_| \_/ \___|
#         __/ | |
#        |___/|_|
#
# Use the previously gathered data to assemble the deployed
# constructor arguments and verify the contract.
#
################################################################################

constructor_abi="constructor(${pool_config_abi},address,address,address,address,address)"
constructor_args_raw=(
  "(${base_token},${vault_shares_token},${linker_factory},${linker_hash},${initial_share_price},${min_reserves},${min_tx_amount},${position_duration},${checkpoint_duration},${time_stretch},${governance},${fee_collector},${swap_collector},(${curve_fee},${flat_fee},${lp_fee},${zombie_fee}))"
  ${targets[*]}
)
constructor_args_encoded=$(cast abi-encode "${constructor_abi}" ${constructor_args_raw[*]})

forge verify-contract \
  ${verify_flags[*]} \
  --constructor-args "${constructor_args_encoded}" \
  --chain-id "${FOUNDRY_CHAIN_ID}" \
  "${POOL_ADDRESS}" \
  "${POOL_TYPE}Hyperdrive"
