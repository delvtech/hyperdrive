if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG="- $2"
fi

certoraRun contracts/src/factory/AaveHyperdriveDeployer.sol \
    --verify AaveHyperdriveDeployer:certora/spec/AaveHyperdriveDeployer.spec \
    --solc solc8.18 \
    --loop_iter 3 \
    --staging \
    --optimistic_loop \
    --rule_sanity \
    --send_only \
    --packages @aave=lib/aave-v3-core/contracts @openzeppelin=node_modules/@openzeppelin \
    $RULE \
    --msg "AaveHyperdriveDeployer: $RULE $MSG" 
