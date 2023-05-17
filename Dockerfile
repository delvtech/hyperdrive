# FIXME: Use multi-staged builds to pull in the openzeppelin 
#        dependency. Alternatively, we can add a sub-module 
#        for openzeppelin.
FROM ghcr.io/foundry-rs/foundry:master

# FIXME: This dockerfile could be improved. We shouldn't have to use
#        the yarn dependencies from the host machine.
WORKDIR /src

COPY ./contracts/ ./contracts/
COPY ./lib/ ./lib/
COPY ./script/ ./script/
COPY ./test/ ./test/
COPY ./node_modules/ ./node_modules/
COPY ./foundry.toml ./foundry.toml
COPY ./remappings.txt ./remappings.txt

# FIXME: Building in the image leads to out of memory errors.
# FIXME: Use the production profile.
# RUN FOUNDRY_PROFILE="script" forge build
RUN mkdir -p ./addresses

ENV ETH_FROM=${ETH_FROM}
ENV PRIVATE_KEY=${PRIVATE_KEY}
ENV RPC_URL=${RPC_URL}

# FIXME: This should be put into it's own bash script.
ENTRYPOINT sleep 5 && \ 
           FOUNDRY_PROFILE="script" forge script script/MockHyperdrive.s.sol \
           --sender "${ETH_FROM}" \
           --private-key "${PRIVATE_KEY}" \
           --rpc-url "${RPC_URL}" \
           --broadcast && \
           mv ./addresses/script_addresses.json ./addresses/addresses.json
