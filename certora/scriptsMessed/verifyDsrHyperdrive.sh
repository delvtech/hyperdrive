if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG="- $2"
fi

certoraRun contracts/src/instances/DsrHyperdrive.sol \
    certora/helpers/DummyERC20A.sol \
    certora/helpers/DummyERC20B.sol \
    certora/helpers/DummyDsrManager.sol:DummyDsrManager \
    certora/helpers/DummyPot.sol \
    contracts/src/libraries/HyperdriveMath.sol \
    --verify DsrHyperdrive:certora/spec/DsrHyperdrive.spec \
    --link DsrHyperdrive:dsrManager=DummyDsrManager \
            DsrHyperdrive:pot=DummyPot \
            DummyDsrManager:potInstance=DummyPot \
    --solc solc8.18 \
    --loop_iter 3 \
    --staging \
    --optimistic_loop \
    --rule_sanity \
    --send_only \
    --settings -t=1000,-mediumTimeout=1000,-depth=50 \
    $RULE \
    --msg "DsrHyperdrive: $RULE $MSG" 
