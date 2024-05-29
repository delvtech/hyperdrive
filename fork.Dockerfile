# NOTE: The `latest` version of foundry does not include arm64 as a build platform,
#       but tagged versions do. Using an arm64-compatible image enables developers to
#       locally rebuild this image with different arguments for debugging/testing purposes.
#
# Use a dedicated stage to generate node_modules.
# Since only package.json and yarn.lock are copied, it's likely this layer will stay cached.
FROM ghcr.io/foundry-rs/foundry@sha256:4606590c8f3cef6a8cba4bdf30226cedcdbd9f1b891e2bde17b7cf66c363b2b3 AS node-builder
RUN apk add --no-cache npm && \
  npm install -g yarn
WORKDIR /app
COPY ./package.json ./package.json
COPY ./yarn.lock ./yarn.lock
RUN yarn install --immutable

# Deploy the contracts to an Anvil node and save the node's state to a file.
# By storing the freshly-deployed state, resetting the chain to that point is
# far simpler and faster.
#
# Build args are used to define the parameters for the deployment.
# These can be overridden at build time to debug generate different hyperdrive configurations.
FROM ghcr.io/foundry-rs/foundry@sha256:4606590c8f3cef6a8cba4bdf30226cedcdbd9f1b891e2bde17b7cf66c363b2b3 as builder
RUN apk add --no-cache npm jq make && \
  npm install -g yarn
WORKDIR /src
COPY --from=node-builder /app/node_modules/ node_modules/
COPY . .
ARG MAINNET_RPC_URL=http://mainnet-rpc-url
ARG DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ARG NETWORK=mainnet_fork
ARG HYPERDRIVE_ETHEREUM_URL=http://127.0.0.1:8545
ARG ADMIN=0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
RUN anvil --fork-url ${MAINNET_RPC_URL} --dump-state ./data & ANVIL="$!" && \
  sleep 2 && \
  # PERF: The deploy step comprises ~90% of cached build time due to a solc download
  # on the first compiler run. Running `npx hardhat compile` in the node-builder stage
  # would fix the issue, but also require defining all build args in that stage
  # as well as defining them without defaults in this stage 🤮.
  npx hardhat compile --config hardhat.config.fork.ts && \
  scripts/deploy-fork.sh && \
  cat ./deployments.local.json | jq '.mainnet_fork | { \
  dai_14_day: .DAI_14_DAY.address, \
  dai_30_day: .DAI_30_DAY.address, \
  steth_14_day: .STETH_14_DAY.address, \
  steth_30_day: .STETH_30_DAY.address, \
  reth_14_day: .RETH_14_DAY.address, \
  reth_30_day: .RETH_30_DAY.address, \
  factory: .FACTORY.address, \
  hyperdriveRegistry: .MAINNET_FORK_REGISTRY.address, \
  }' >./artifacts/addresses.json && \
  kill $ANVIL && sleep 1s

# Copy over only the stored chain data and list of contract addresses to minimize image size.
FROM ghcr.io/foundry-rs/foundry@sha256:4606590c8f3cef6a8cba4bdf30226cedcdbd9f1b891e2bde17b7cf66c363b2b3
WORKDIR /src
RUN apk add --no-cache npm jq make && \
  npm install -g yarn
COPY --from=builder /src/data /src/data
COPY --from=builder /src/artifacts/addresses.json /src/artifacts/addresses.json
COPY --from=builder /src/deployments.local.json /src/deployments.local.json
COPY --from=builder /src/node_modules /src/node_modules
COPY --from=builder /src/tasks /src/tasks
COPY --from=builder /src/package.json /src/package.json
COPY --from=builder /src/yarn.lock /src/yarn.lock
COPY --from=builder /src/hardhat.config.fork.ts /src/hardhat.config.ts
COPY --from=builder /src/tsconfig.json /src/tsconfig.json
