FROM ghcr.io/foundry-rs/foundry:master as builder

# Set the working directory to where the source code will live.
WORKDIR /src

# Use the production foundry profile.
ENV FOUNDRY_PROFILE="production"

# Copy the dependencies required to run the migration script.
COPY ./.git/ ./.git/
COPY ./contracts/ ./contracts/
COPY ./lib/ ./lib/
COPY ./test/ ./test/
COPY ./foundry.toml ./foundry.toml

# Install the dependencies and compile the contracts.
RUN forge install && forge build

# Compile the migration script.
Run source $HOME/.profile && cargo build -Z sparse-registry --bin migrate

# Load the environment variables used in the migration script.
ENV HYPERDRIVE_ETHEREUM_URL=http://localhost:8545
ENV DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ARG ADMIN
ARG IS_COMPETITION_MODE
ARG BASE_TOKEN_NAME
ARG BASE_TOKEN_SYMBOL
ARG BASE_TOKEN_DECIMALS
ARG VAULT_NAME
ARG VAULT_SYMBOL
ARG VAULT_STARTING_RATE
ARG LIDO_STARTING_RATE
ARG FACTORY_CHECKPOINT_DURATION
ARG FACTORY_MIN_CHECKPOINT_DURATION
ARG FACTORY_MAX_CHECKPOINT_DURATION
ARG FACTORY_MIN_POSITION_DURATION
ARG FACTORY_MAX_POSITION_DURATION
ARG FACTORY_MIN_FIXED_APR
ARG FACTORY_MAX_FIXED_APR
ARG FACTORY_MIN_TIME_STRETCH_APR
ARG FACTORY_MAX_TIME_STRETCH_APR
ARG FACTORY_MIN_CURVE_FEE
ARG FACTORY_MIN_FLAT_FEE
ARG FACTORY_MIN_GOVERNANCE_LP_FEE
ARG FACTORY_MIN_GOVERNANCE_ZOMBIE_FEE
ARG FACTORY_MAX_CURVE_FEE
ARG FACTORY_MAX_FLAT_FEE
ARG FACTORY_MAX_GOVERNANCE_LP_FEE
ARG FACTORY_MAX_GOVERNANCE_ZOMBIE_FEE
ARG ERC4626_HYPERDRIVE_CONTRIBUTION
ARG ERC4626_HYPERDRIVE_FIXED_APR
ARG ERC4626_HYPERDRIVE_TIME_STRETCH_APR
ARG ERC4626_HYPERDRIVE_MINIMUM_SHARE_RESERVES
ARG ERC4626_HYPERDRIVE_MINIMUM_TRANSACTION_AMOUNT
ARG ERC4626_HYPERDRIVE_POSITION_DURATION
ARG ERC4626_HYPERDRIVE_CHECKPOINT_DURATION
ARG ERC4626_HYPERDRIVE_CURVE_FEE
ARG ERC4626_HYPERDRIVE_FLAT_FEE
ARG ERC4626_HYPERDRIVE_GOVERNANCE_LP_FEE
ARG ERC4626_HYPERDRIVE_GOVERNANCE_ZOMBIE_FEE
ARG STETH_HYPERDRIVE_CONTRIBUTION
ARG STETH_HYPERDRIVE_FIXED_APR
ARG STETH_HYPERDRIVE_TIME_STRETCH_APR
ARG STETH_HYPERDRIVE_MINIMUM_SHARE_RESERVES
ARG STETH_HYPERDRIVE_MINIMUM_TRANSACTION_AMOUNT
ARG STETH_HYPERDRIVE_POSITION_DURATION
ARG STETH_HYPERDRIVE_CHECKPOINT_DURATION
ARG STETH_HYPERDRIVE_CURVE_FEE
ARG STETH_HYPERDRIVE_FLAT_FEE
ARG STETH_HYPERDRIVE_GOVERNANCE_LP_FEE
ARG STETH_HYPERDRIVE_GOVERNANCE_ZOMBIE_FEE

# Run anvil as a background process. We run the migrations against this anvil
# node and dump the state into the "./data" directory. At runtime, the consumer
# can start anvil with the "--load-state ./data" flag to start up anvil with
# the post-migrations state.
RUN anvil --dump-state ./data & \
    ANVIL="$!" && \
    sleep 2 && \
    ./target/debug/migrate && \
    kill $ANVIL && \
    sleep 1s # HACK(jalextowle): Ensure that "./data" is written before exiting.

FROM ghcr.io/foundry-rs/foundry:master

# Set the working directory to where the source code will live.
WORKDIR /src

# Copy the data and artifacts from the builder stage.
COPY --from=builder /src/data /src/data
COPY --from=builder /src/artifacts /src/artifacts
