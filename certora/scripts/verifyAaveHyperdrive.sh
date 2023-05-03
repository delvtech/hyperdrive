if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG="- $2"
fi

certoraRun contracts/src/instances/AaveHyperdrive.sol \
    --verify AaveHyperdrive:certora/spec/AaveHyperdrive.spec \
    --solc solc8.18 \
    --loop_iter 3 \
    --staging \
    --optimistic_loop \
    --rule_sanity \
    --send_only \
    --packages @aave=lib/aave-v3-core/contracts @openzeppelin=node_modules/@openzeppelin \
    $RULE \
    --msg "AaveHyperdrive: $RULE $MSG" 
