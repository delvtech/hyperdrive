### Foundry Image ###

FROM ghcr.io/foundry-rs/foundry:master

WORKDIR /src

# FIXME: Use the production profile.
# Use the production foundry profile.
# ENV FOUNDRY_PROFILE="production"

# Copy the contract dependencies required to run the migration script.
COPY ./.git/ ./.git/
COPY ./contracts/ ./contracts/
COPY ./lib/ ./lib/
COPY ./script/ ./script/
COPY ./test/ ./test/
COPY ./foundry.toml ./foundry.toml

# Copy the script used to run the migrations and set its permissions.
COPY ./run_migrations.sh ./run_migrations.sh
RUN chmod a+x ./run_migrations.sh

# Install the dependencies and compile the contracts.
RUN forge install && forge build

# Set the environment variables used in the migration script.
ARG ETH_FROM=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
ARG PRIVATE_KEY=ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ARG RPC_URL=http://localhost:8545
ENV ETH_FROM="$ETH_FROM"
ENV PRIVATE_KEY="$PRIVATE_KEY"
ENV RPC_URL="$RPC_URL"

# Run anvil as a background process. We will run the migrations on this anvil
# node at build time and dump the state to the "data/" directory.
RUN anvil --dump-state ./data & ANVIL="$!" && ./run_migrations.sh && kill $ANVIL

ENTRYPOINT anvil --load-state ./data --host 0.0.0.0
