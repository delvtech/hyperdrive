if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG="- $2"
fi

certoraRun contracts/src/BondWrapper.sol \
    contracts/src/instances/MakerDsrHyperdrive.sol \
    \
    contracts/src/libraries/HyperdriveMath.sol \
    \
    certora/helpers/DummyERC20A.sol \
    certora/helpers/DummyERC20B.sol \
    certora/helpers/DummyDsrManager.sol:DummyDsrManager \
    \
    --verify BondWrapper:certora/spec/BondWrapper.spec \
    --link BondWrapper:hyperdrive=MakerDsrHyperdrive \
            BondWrapper:token=DummyERC20B \
            MakerDsrHyperdrive:dsrManager=DummyDsrManager \
    --solc solc8.18 \
    --loop_iter 3 \
    --staging \
    --optimistic_loop \
    --rule_sanity \
    --send_only \
    $RULE \
    --msg "BondWrapper: $RULE $MSG" 
