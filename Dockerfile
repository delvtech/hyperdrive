### Foundry Image ###

FROM ghcr.io/foundry-rs/foundry:master

WORKDIR /src

# Use the production foundry profile.
ENV FOUNDRY_PROFILE="production"

# Copy the contract dependencies required to run the migration script.
COPY ./.git/ ./.git/
COPY ./contracts/ ./contracts/
COPY ./lib/ ./lib/
COPY ./script/ ./script/
COPY ./test/ ./test/
COPY ./foundry.toml ./foundry.toml

# Copy the script used to run the migrations and set its permissions.
COPY ./migrate.sh ./migrate.sh
RUN chmod a+x ./migrate.sh

# Install the dependencies and compile the contracts.
RUN forge install && forge build

# Load the build-time arguments used in the migration script.
ARG ADMIN
ARG IS_COMPETITION_MODE
ARG BASE_TOKEN_NAME
ARG BASE_TOKEN_SYMBOL
ARG VAULT_STARTING_RATE
ARG HYPERDRIVE_CONTRIBUTION
ARG HYPERDRIVE_FIXED_RATE
ARG HYPERDRIVE_INITIAL_SHARE_PRICE
ARG HYPERDRIVE_MINIMUM_SHARE_RESERVES
ARG HYPERDRIVE_MINIMUM_TRANSACTION_AMOUNT
ARG HYPERDRIVE_POSITION_DURATION
ARG HYPERDRIVE_CHECKPOINT_DURATION
ARG HYPERDRIVE_TIME_STRETCH_APR
ARG HYPERDRIVE_ORACLE_SIZE
ARG HYPERDRIVE_UPDATE_GAP

# Load the environment variables used in the migration script.
ENV ETH_FROM=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
ENV PRIVATE_KEY=ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ENV RPC_URL=http://localhost:8545

# Run anvil as a background process. We run the migrations against this anvil 
# node and dump the state into the "./data" directory. At runtime, the consumer
# can start anvil with the "--load-state ./data" flag to start up anvil with 
# the post-migrations state.
RUN anvil --dump-state ./data --code-size-limit 9999999999 & \
    ANVIL="$!" && \ 
    sleep 2 && \
    ./migrate.sh && \
    kill $ANVIL && \
    sleep 1s # HACK(jalextowle): Ensure that "./data" is written before exiting.
