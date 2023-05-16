# FIXME: Use multi-staged builds to pull in the openzeppelin 
#        dependency. Alternatively, we can add a sub-module 
#        for openzeppelin.
#
# FIXME: Lock this to a version.
#
# FIXME: Comment this Dockerfile.
FROM ghcr.io/foundry-rs/foundry:master

# FIXME: This dockerfile could be improved. We shouldn't have to use
#        the yarn dependencies from the host machine. Furthermore,r
#        we shouldn't need to use forge clean.
WORKDIR /src
COPY . .

COPY ./contracts/ ./contracts/
COPY ./lib/ ./lib/
COPY ./script/ ./script/
COPY ./test/ ./test/
COPY ./foundry.toml ./foundry.toml

# FIXME: Use the production profile.
# 
# FIXME: It would be good to run this when building image so that the command
#        is faster.
RUN forge clean
RUN forge build

ENV ETH_FROM=${ETH_FROM}
ENV PRIVATE_KEY=${PRIVATE_KEY}
ENV RPC_URL=${RPC_URL}

# FIXME: remove -vv
ENTRYPOINT sleep 5s && forge script script/MockHyperdrive.s.sol \
           --sender ${ETH_FROM} \
           --private-key ${PRIVATE_KEY} \
           --rpc-url ${RPC_URL} \
           --broadcast -vvv
