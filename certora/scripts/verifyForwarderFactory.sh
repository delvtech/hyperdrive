if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG="- $2"
fi

certoraRun certora/munged/ForwarderFactory.sol \
    --verify ForwarderFactory:certora/spec/ForwarderFactory.spec \
    --solc solc8.18 \
    --loop_iter 3 \
    --staging \
    --optimistic_loop \
    --optimistic_hashing \
    --hashing_length_bound 1000 \
    --rule_sanity \
    --send_only \
    $RULE \
    --msg "ForwarderFactory: $RULE $MSG"
