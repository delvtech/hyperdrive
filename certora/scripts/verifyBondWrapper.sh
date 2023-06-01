if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG="- $2"
fi

certoraRun contracts/src/BondWrapper.sol \
    contracts/src/instances/DsrHyperdrive.sol \
    \
    certora/helpers/DummyERC20A.sol \
    certora/helpers/DummyERC20B.sol \
    certora/helpers/DummyDsrManager.sol:DummyDsrManager \
    certora/helpers/DummyPot.sol \
    \
    --verify BondWrapper:certora/spec/BondWrapper.spec \
    --link BondWrapper:hyperdrive=DsrHyperdrive \
            BondWrapper:token=DummyERC20B \
            DsrHyperdrive:dsrManager=DummyDsrManager \
            DsrHyperdrive:pot=DummyPot \
            DummyDsrManager:potInstance=DummyPot \
    --solc solc8.18 \
    --loop_iter 3 \
    --staging \
    --optimistic_loop \
    --rule_sanity \
    --send_only \
    $RULE \
    --msg "BondWrapper: $RULE $MSG" 
