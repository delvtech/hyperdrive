FROM ghcr.io/foundry-rs/foundry:master as builder

# Install the Rust toolchain.
RUN apk add clang lld curl build-base linux-headers git pkgconfig libressl-dev \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > rustup.sh \
    && chmod +x ./rustup.sh \
    && ./rustup.sh -y --default-toolchain nightly

# Set the working directory to where the source code will live.
WORKDIR /src

# Use the production foundry profile.
ENV FOUNDRY_PROFILE="production"

# Copy the dependencies required to run the migration script.
COPY ./.git/ ./.git/
COPY ./contracts/ ./contracts/
COPY ./crates/ ./crates/
COPY ./lib/ ./lib/
COPY ./test/ ./test/
COPY ./Cargo.toml ./Cargo.toml
COPY ./Cargo.lock ./Cargo.lock
COPY ./foundry.toml ./foundry.toml

# Install the dependencies and compile the contracts.
RUN forge install && forge build

# Compile the migration script.
Run source $HOME/.profile && cargo build -Z sparse-registry --bin migrate

# Load the environment variables used in the migration script.
ENV HYPERDRIVE_ETHEREUM_URL=http://localhost:8545
ARG ADMIN
ARG IS_COMPETITION_MODE
ARG BASE_TOKEN_NAME
ARG BASE_TOKEN_SYMBOL
ARG VAULT_NAME
ARG VAULT_SYMBOL
ARG VAULT_STARTING_RATE
ARG LIDO_STARTING_RATE
ARG ERC4626_HYPERDRIVE_CONTRIBUTION
ARG ERC4626_HYPERDRIVE_FIXED_RATE
ARG ERC4626_HYPERDRIVE_INITIAL_SHARE_PRICE
ARG ERC4626_HYPERDRIVE_MINIMUM_SHARE_RESERVES
ARG ERC4626_HYPERDRIVE_MINIMUM_TRANSACTION_AMOUNT
ARG ERC4626_HYPERDRIVE_POSITION_DURATION
ARG ERC4626_HYPERDRIVE_CHECKPOINT_DURATION
ARG ERC4626_HYPERDRIVE_TIME_STRETCH_APR
ARG STETH_HYPERDRIVE_CONTRIBUTION
ARG STETH_HYPERDRIVE_FIXED_RATE
ARG STETH_HYPERDRIVE_INITIAL_SHARE_PRICE
ARG STETH_HYPERDRIVE_MINIMUM_SHARE_RESERVES
ARG STETH_HYPERDRIVE_MINIMUM_TRANSACTION_AMOUNT
ARG STETH_HYPERDRIVE_POSITION_DURATION
ARG STETH_HYPERDRIVE_CHECKPOINT_DURATION
ARG STETH_HYPERDRIVE_TIME_STRETCH_APR

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
