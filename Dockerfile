# NOTE: The `latest` version of foundry does not include arm64 as a build platform, 
#       but tagged versions do. Using an arm64-compatible image enables developers to 
#       locally rebuild this image with different arguments for debugging/testing purposes.
FROM ghcr.io/foundry-rs/foundry@sha256:4606590c8f3cef6a8cba4bdf30226cedcdbd9f1b891e2bde17b7cf66c363b2b3 AS node-builder
# Copy only package.json and yarn.lock to nearly guarantee using a cached layer for node_modules.
RUN apk add --no-cache npm && \
  npm install -g yarn
WORKDIR /app
COPY ./package.json ./package.json
COPY ./yarn.lock ./yarn.lock
RUN yarn install --immutable 

FROM ghcr.io/foundry-rs/foundry@sha256:4606590c8f3cef6a8cba4bdf30226cedcdbd9f1b891e2bde17b7cf66c363b2b3 as builder
# Install node related depencies. The `npm` apk package includes node 18 as a dependency.
RUN apk add --no-cache npm jq make && \
  npm install -g yarn 
# Set the working directory to where the source code will live.
WORKDIR /src
# Copy node_modules from the prior stage.
COPY --from=node-builder /app/node_modules/ node_modules/
# Copy repository contents. Excluded items are defined in .dockerignore.
COPY . .
# Load the environment variables used in the migration script.
# The values provided below are defaults and can be overridden
# via --build-args at image build time.
ENV NETWORK=anvil
ENV HYPERDRIVE_ETHEREUM_URL=http://127.0.0.1:8545
ENV PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ARG ADMIN=0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
ARG IS_COMPETITION_MODE=false
ARG BASE_TOKEN_NAME=Base
ARG BASE_TOKEN_SYMBOL=BASE
ARG BASE_TOKEN_DECIMALS=18
ARG VAULT_NAME='Delvnet Yield Source'
ARG VAULT_SYMBOL=DELV
ARG VAULT_STARTING_RATE=0.05
ARG LIDO_STARTING_RATE=0.035
ARG FACTORY_CHECKPOINT_DURATION=1
ARG FACTORY_MIN_CHECKPOINT_DURATION=1
ARG FACTORY_MAX_CHECKPOINT_DURATION=24
ARG FACTORY_MIN_POSITION_DURATION=7
ARG FACTORY_MAX_POSITION_DURATION=36500
ARG FACTORY_MIN_CIRCUIT_BREAKER_DELTA=0.15
ARG FACTORY_MAX_CIRCUIT_BREAKER_DELTA=2
ARG FACTORY_MIN_FIXED_APR=0.01
ARG FACTORY_MAX_FIXED_APR=0.5
ARG FACTORY_MIN_TIME_STRETCH_APR=0.01
ARG FACTORY_MAX_TIME_STRETCH_APR=0.5
ARG FACTORY_MIN_CURVE_FEE=0.0001
ARG FACTORY_MIN_FLAT_FEE=0.0001
ARG FACTORY_MIN_GOVERNANCE_LP_FEE=0.15
ARG FACTORY_MIN_GOVERNANCE_ZOMBIE_FEE=0.03
ARG FACTORY_MAX_CURVE_FEE=0.1
ARG FACTORY_MAX_FLAT_FEE=0.001
ARG FACTORY_MAX_GOVERNANCE_LP_FEE=0.15
ARG FACTORY_MAX_GOVERNANCE_ZOMBIE_FEE=0.03
ARG ERC4626_HYPERDRIVE_CONTRIBUTION=1000000000
ARG ERC4626_HYPERDRIVE_FIXED_APR=0.05
ARG ERC4626_HYPERDRIVE_TIME_STRETCH_APR=0.05
ARG ERC4626_HYPERDRIVE_MINIMUM_SHARE_RESERVES=10
ARG ERC4626_HYPERDRIVE_MINIMUM_TRANSACTION_AMOUNT=0.001
ARG ERC4626_HYPERDRIVE_CIRCUIT_BREAKER_DELTA=2
ARG ERC4626_HYPERDRIVE_POSITION_DURATION=7
ARG ERC4626_HYPERDRIVE_CHECKPOINT_DURATION=1
ARG ERC4626_HYPERDRIVE_CURVE_FEE=0.01
ARG ERC4626_HYPERDRIVE_FLAT_FEE=0.0005
ARG ERC4626_HYPERDRIVE_GOVERNANCE_LP_FEE=0.15
ARG ERC4626_HYPERDRIVE_GOVERNANCE_ZOMBIE_FEE=0.03
ARG STETH_HYPERDRIVE_CONTRIBUTION=50000
ARG STETH_HYPERDRIVE_FIXED_APR=0.035
ARG STETH_HYPERDRIVE_TIME_STRETCH_APR=0.035
ARG STETH_HYPERDRIVE_MINIMUM_SHARE_RESERVES=0.001
ARG STETH_HYPERDRIVE_MINIMUM_TRANSACTION_AMOUNT=0.001
ARG STETH_HYPERDRIVE_CIRCUIT_BREAKER_DELTA=2
ARG STETH_HYPERDRIVE_POSITION_DURATION=7
ARG STETH_HYPERDRIVE_CHECKPOINT_DURATION=1
ARG STETH_HYPERDRIVE_CURVE_FEE=0.01
ARG STETH_HYPERDRIVE_FLAT_FEE=0.0005
ARG STETH_HYPERDRIVE_GOVERNANCE_LP_FEE=0.15
ARG STETH_HYPERDRIVE_GOVERNANCE_ZOMBIE_FEE=0.03
# Run anvil as a background process. We run the migrations against this anvil
# node and dump the state into the "./data" directory. At runtime, the consumer
# can start anvil with the "--load-state ./data" flag to start up anvil with
# the post-migrations state.
RUN anvil --dump-state ./data & ANVIL="$!" && \
  sleep 2 && \
  # Deploy ERC4626_HYPERDRIVE, STETH_HYPERDRIVE, their coordinators, a factory, and a registry.
  # PERF: The deploy step comprises ~90% of cached build time due to a solc download
  # on the first compiler run. Running `npx hardhat compile` in the node-builder stage
  # would fix the issue, but also require defining all build args in that stage 
  # as well as defining them without defaults in this stage 🤮.
  make deploy && \
  # Add ERC4626_HYPERDRIVE to the registry.
  npx hardhat registry:add --name ERC4626_HYPERDRIVE --value 1 --network anvil && \
  # Add STETH_HYPERDRIVE to the registry.
  npx hardhat registry:add --name STETH_HYPERDRIVE --value 1 --network anvil && \
  # Generate an `artifacts/addresses.json` file using the outputted addressed from the deploy.
  ./scripts/format-devnet-addresses.sh && \
  # Kill the running anvil process and give it time to write the contents to `./data` before continuing.
  kill $ANVIL && sleep 1s

FROM ghcr.io/foundry-rs/foundry@sha256:4606590c8f3cef6a8cba4bdf30226cedcdbd9f1b891e2bde17b7cf66c363b2b3
# Set the working directory to where the source code will live.
WORKDIR /src
# Copy the data and artifacts from the builder stage.
COPY --from=builder /src/data /src/data
COPY --from=builder /src/artifacts /src/artifacts
