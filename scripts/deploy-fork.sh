#!/bin/sh

set -e

npx hardhat fork:mint-eth --address 0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8 --amount 1000 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat fork:mint-steth --address 0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8 --amount 1000 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat fork:mint-reth --address 0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8 --amount 1000 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat fork:mint-dai --address 0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8 --amount 20000 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat fork:mint-sdai --address 0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8 --amount 20000 --network mainnet_fork --config hardhat.config.fork.ts

npx hardhat deploy:hyperdrive --network mainnet_fork --config hardhat.config.fork.ts --show-stack-traces

npx hardhat registry:add --name DAI_14_DAY --value 1 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat registry:add --name DAI_30_DAY --value 1 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat registry:add --name STETH_14_DAY --value 1 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat registry:add --name STETH_30_DAY --value 1 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat registry:add --name RETH_14_DAY --value 1 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat registry:add --name RETH_30_DAY --value 1 --network mainnet_fork --config hardhat.config.fork.ts
