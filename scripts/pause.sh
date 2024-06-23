#!/bin/bash

# This script will pause all instances that have data = 1.
# NOTE: User must have MAINNET_RPC_URL, PAUSER_ADDRESS, and PAUSER_KEY set in .env file.
#
# Example usage: bash scripts/pause.sh <REGISTRY_ADDRESS>

source .env

# Set the network
RPC_URL=$MAINNET_RPC_URL

# Hyperdrive Registry contract address
HYPERDRIVE_REGISTRY_ADDRESS=$1

# Get the total number of instances
total_instances=$(cast call $HYPERDRIVE_REGISTRY_ADDRESS "getNumberOfInstances()(uint256)" --rpc-url $RPC_URL)

# Fetch all instance addresses
instance_addresses=$(cast call $HYPERDRIVE_REGISTRY_ADDRESS "getInstancesInRange(uint256,uint256)(address[])" 0 $total_instances --rpc-url $RPC_URL)

# Remove the square brackets and split by comma
instance_addresses=${instance_addresses:1:-1}
IFS=', ' read -r -a instance_address_array <<< "$instance_addresses"

echo "Filter instances with data = 1."
filtered_instance_addresses=()
for instance in ${instance_address_array[@]}; do
    # cast is returning the result in two lines so we use: sed '1p;d' to get the first line
    data=$(cast call $HYPERDRIVE_REGISTRY_ADDRESS "getInstanceInfo(address)(uint256,address)" $instance --rpc-url $RPC_URL| sed '1p;d')
    if [ $data -eq 1 ]; then
        filtered_instance_addresses+=($instance)
    fi
done

echo "Pausing the filtered instances."
for instance in ${filtered_instance_addresses[@]}; do
    cast send --unlocked --from $PAUSER_ADDRESS --private-key $PAUSER_KEY $instance "pause(bool)" 1 --rpc-url $RPC_URL
    if [ $? -eq 0 ]; then
        echo "Instance $instance paused successfully"
    else
        echo "Failed to pause instance $instance"
    fi
done
