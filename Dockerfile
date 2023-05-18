### Yarn Image ###

FROM node:lts AS yarn-builder

WORKDIR /src

COPY ./package.json ./package.json
COPY ./yarn.lock ./yarn.lock

RUN yarn install

### Foundry Image ###

FROM ghcr.io/foundry-rs/foundry:master

WORKDIR /src

# Load the ethereum environment variables.
ENV ETH_FROM=${ETH_FROM}
ENV PRIVATE_KEY=${PRIVATE_KEY}
ENV RPC_URL=${RPC_URL}

# Copy the contract dependencies required to run the migration script.
COPY --from=yarn-builder /src/node_modules/@openzeppelin/ ./node_modules/@openzeppelin/
COPY ./contracts/ ./contracts/
COPY ./lib/ ./lib/
COPY ./script/ ./script/
COPY ./test/ ./test/
COPY ./foundry.toml ./foundry.toml

# TODO: Building in the image leads to out of memory errors.
# TODO: Use the production profile.
RUN FOUNDRY_PROFILE="script" forge build

# Copy the script used to run the migrations and set its permissions.
COPY ./run_migrations.sh ./run_migrations.sh
RUN chmod a+x ./run_migrations.sh

# Create the artifacts directory. 
RUN mkdir -p ./artifacts

ENTRYPOINT ./run_migrations.sh
