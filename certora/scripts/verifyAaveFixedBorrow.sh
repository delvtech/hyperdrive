if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG="- $2"
fi

certoraRun contracts/src/actions/AaveFixedBorrow.sol:AaveFixedBorrowAction \
    --verify AaveFixedBorrowAction:certora/spec/AaveFixedBorrow.spec \
    --solc solc8.18 \
    --loop_iter 3 \
    --staging \
    --optimistic_loop \
    --rule_sanity \
    --send_only \
    --packages @aave=lib/aave-v3-core/contracts @openzeppelin=node_modules/@openzeppelin \
    $RULE \
    --msg "AaveFixedBorrow: $RULE $MSG" 
