# WARN: Version pinned to avoid https://github.com/foundry-rs/foundry/issues/7502

ARG MAINNET_RPC_URL=http://mainnet-rpc-url
ARG DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ARG NETWORK=mainnet_fork
ARG HYPERDRIVE_ETHEREUM_URL=http://127.0.0.1:8545
ARG ADMIN=0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266


FROM ghcr.io/foundry-rs/foundry:nightly-5b7e4cb3c882b28f3c32ba580de27ce7381f415a AS base
RUN apk add --no-cache npm jq make && \
  npm install -g yarn
WORKDIR /src


# Use a dedicated stage to generate node_modules.
# Since only package.json and yarn.lock are copied, it's likely this layer will stay cached.
FROM base as node-modules-builder
WORKDIR /src
COPY ./package.json ./package.json
COPY ./yarn.lock ./yarn.lock
RUN yarn install --immutable && yarn cache clean

# Use a dedicated stage for contract compilation
FROM node-modules-builder as contracts-builder
WORKDIR /src
COPY --from=node-modules-builder /src/node_modules/ /src/node_modules/
COPY . .
ARG MAINNET_RPC_URL
ARG DEPLOYER_PRIVATE_KEY
ARG NETWORK
ARG HYPERDRIVE_ETHEREUM_URL
ARG ADMIN
RUN npx hardhat compile --config hardhat.config.fork.ts

# Deploy the contracts to an Anvil node and save the node's state to a file.
# By storing the freshly-deployed state, resetting the chain to that point is
# far simpler and faster.
#
# Build args are used to define the parameters for the deployment.
# These can be overridden at build time to debug generate different hyperdrive configurations.
FROM ghcr.io/foundry-rs/foundry:nightly-5b7e4cb3c882b28f3c32ba580de27ce7381f415a as deployer
RUN apk add --no-cache npm jq make && \
  npm install -g yarn
WORKDIR /src
COPY --from=contracts-builder /src/node_modules/ node_modules/
COPY --from=contracts-builder /src/artifacts/ artifacts/
COPY . .
ARG MAINNET_RPC_URL
ARG DEPLOYER_PRIVATE_KEY
ARG NETWORK
ARG HYPERDRIVE_ETHEREUM_URL
ARG ADMIN
RUN anvil --fork-url ${MAINNET_RPC_URL} --dump-state ./data & ANVIL="$!" && \
  sleep 5 && \
  # PERF: The deploy step comprises ~90% of cached build time due to a solc download
  # on the first compiler run. Running `npx hardhat compile` in the node-builder stage
  # would fix the issue, but also require defining all build args in that stage
  # as well as defining them without defaults in this stage 🤮.
  scripts/deploy-fork.sh && \
  cat ./deployments.local.json | jq '.mainnet_fork | { \
  dai14Day: .DAI_14_DAY.address, \
  dai30Day: .DAI_30_DAY.address, \
  steth14Day: .STETH_14_DAY.address, \
  steth30Day: .STETH_30_DAY.address, \
  reth14Day: .RETH_14_DAY.address, \
  reth30Day: .RETH_30_DAY.address, \
  factory: .FACTORY.address, \
  hyperdriveRegistry: .MAINNET_FORK_REGISTRY.address, \
  }' >./artifacts/addresses.json && \
  kill $ANVIL && sleep 5

# Copy over only the stored chain data and list of contract addresses to minimize image size.
FROM ghcr.io/foundry-rs/foundry:nightly-5b7e4cb3c882b28f3c32ba580de27ce7381f415a
WORKDIR /src
RUN apk add --no-cache npm jq make && \
  npm install -g yarn
COPY --from=deployer /src/data /src/data
COPY --from=deployer /src/artifacts /src/artifacts
COPY --from=deployer /src/deployments.local.json /src/deployments.local.json
COPY --from=deployer /src/node_modules /src/node_modules
COPY --from=deployer /src/tasks /src/tasks
COPY --from=deployer /src/package.json /src/package.json
COPY --from=deployer /src/yarn.lock /src/yarn.lock
COPY --from=deployer /src/hardhat.config.fork.ts /src/hardhat.config.ts
COPY --from=deployer /src/tsconfig.json /src/tsconfig.json
