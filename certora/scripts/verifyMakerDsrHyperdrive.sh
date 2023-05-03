if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG="- $2"
fi

certoraRun contracts/src/instances/MakerDsrHyperdrive.sol \
    certora/helpers/DummyERC20A.sol \
    certora/helpers/DummyERC20B.sol \
    --verify MakerDsrHyperdrive:certora/spec/MakerDsrHyperdrive.spec \
    --solc solc8.18 \
    --loop_iter 3 \
    --staging \
    --optimistic_loop \
    --rule_sanity \
    --send_only \
    $RULE \
    --msg "MakerDsrHyperdrive: $RULE $MSG" 
