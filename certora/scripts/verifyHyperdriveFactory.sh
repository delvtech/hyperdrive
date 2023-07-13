if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG="- $2"
fi

certoraRun contracts/src/factory/HyperdriveFactory.sol \
    contracts/src/factory/MakerDsrHyperdriveDeployer.sol \
    contracts/src/instances/MakerDsrHyperdrive.sol \
    contracts/src/libraries/HyperdriveMath.sol \
    certora/helpers/DummyERC20A.sol \
    certora/helpers/DummyERC20B.sol \
    certora/helpers/DummyDsrManager.sol:DummyDsrManager \
    --verify HyperdriveFactory:certora/spec/HyperdriveFactory.spec \
    --link HyperdriveFactory:hyperdriveDeployer=MakerDsrHyperdriveDeployer \
    --solc solc8.18 \
    --loop_iter 3 \
    --staging \
    --optimistic_loop \
    --rule_sanity \
    --send_only \
    --packages @openzeppelin=node_modules/@openzeppelin \
    $RULE \
    --msg "HyperdriveFactory: $RULE $MSG"
