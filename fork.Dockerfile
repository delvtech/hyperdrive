# WARN: Version pinned to avoid https://github.com/foundry-rs/foundry/issues/7502


FROM ghcr.io/foundry-rs/foundry@sha256:4606590c8f3cef6a8cba4bdf30226cedcdbd9f1b891e2bde17b7cf66c363b2b3 AS base
RUN apk add --no-cache npm jq make && \
  npm install -g yarn


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
# ARG MAINNET_RPC_URL=http://mainnet-rpc-url
# ARG DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
# ARG HYPERDRIVE_ETHEREUM_URL=http://127.0.0.1:8545
# ARG ADMIN=0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
# ARG NETWORK=mainnet_fork
RUN npx hardhat compile --config hardhat.config.mainnet_fork.ts

FROM base
WORKDIR /src
COPY --from=contracts-builder /src/node_modules/ node_modules/
COPY --from=contracts-builder /src/artifacts/ artifacts/
COPY . .
