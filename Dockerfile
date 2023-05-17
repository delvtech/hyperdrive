# FIXME: Use multi-staged builds to pull in the openzeppelin 
#        dependency. Alternatively, we can add a sub-module 
#        for openzeppelin.
FROM ghcr.io/foundry-rs/foundry:master

# Add curl so that we can poll Ethereum on startup.
RUN apk add curl curl-dev

# FIXME: This dockerfile could be improved. We shouldn't have to use
#        the yarn dependencies from the host machine. Furthermore,r
#        we shouldn't need to use forge clean.
WORKDIR /src

COPY ./contracts/ ./contracts/
COPY ./lib/ ./lib/
COPY ./script/ ./script/
COPY ./test/ ./test/
COPY ./node_modules/ ./node_modules/
COPY ./foundry.toml ./foundry.toml
COPY ./remappings.txt ./remappings.txt

# FIXME: Use the production profile.
# FIXME: forge script intermittently fails when it doesn't build the contracts.
# RUN forge build

ENV ETH_FROM=${ETH_FROM}
ENV PRIVATE_KEY=${PRIVATE_KEY}
ENV RPC_URL=${RPC_URL}

ENTRYPOINT sleep 2 && \ 
           forge script script/MockHyperdrive.s.sol \
           --sender "${ETH_FROM}" \
           --private-key "${PRIVATE_KEY}" \
           --rpc-url "${RPC_URL}" \
           --slow \
           --broadcast -vvv
