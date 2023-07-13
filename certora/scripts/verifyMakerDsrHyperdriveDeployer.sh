if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG="- $2"
fi

certoraRun contracts/src/factory/MakerDsrHyperdriveDeployer.sol \
    --verify MakerDsrHyperdriveDeployer:certora/spec/MakerDsrHyperdriveDeployer.spec \
    --solc solc8.18 \
    --loop_iter 3 \
    --staging \
    --optimistic_loop \
    --rule_sanity \
    --send_only \
    --packages @openzeppelin=node_modules/@openzeppelin \
    $RULE \
    --msg "MakerDsrHyperdriveDeployer: $RULE $MSG" 
