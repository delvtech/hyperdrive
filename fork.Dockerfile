# NOTE: The `latest` version of foundry does not include arm64 as a build platform,
#       but tagged versions do. Using an arm64-compatible image enables developers to
#       locally rebuild this image with different arguments for debugging/testing purposes.

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
RUN npx hardhat compile --config hardhat.config.mainnet_fork.ts

FROM base
WORKDIR /src
COPY --from=contracts-builder /src/node_modules/ node_modules/
COPY --from=contracts-builder /src/artifacts/ artifacts/
COPY . .
