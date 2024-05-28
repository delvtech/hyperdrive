#!/bin/sh

set -e

npx hardhat fork:mint-eth --address ${ADMIN} --amount 1000 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat fork:mint-steth --address ${ADMIN} --amount 1000 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat fork:mint-reth --address ${ADMIN} --amount 1000 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat fork:mint-dai --address ${ADMIN} --amount 20000 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat fork:mint-sdai --address ${ADMIN} --amount 20000 --network mainnet_fork --config hardhat.config.fork.ts

npx hardhat deploy:hyperdrive --network mainnet_fork --config hardhat.config.fork.ts --show-stack-traces

npx hardhat registry:add --name DAI_14_DAY --value 1 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat registry:add --name DAI_30_DAY --value 1 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat registry:add --name STETH_14_DAY --value 1 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat registry:add --name STETH_30_DAY --value 1 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat registry:add --name RETH_14_DAY --value 1 --network mainnet_fork --config hardhat.config.fork.ts
npx hardhat registry:add --name RETH_30_DAY --value 1 --network mainnet_fork --config hardhat.config.fork.ts
