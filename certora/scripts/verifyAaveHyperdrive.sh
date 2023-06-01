if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG="- $2"
fi

certoraRun certora/munged/AaveHyperdrive.sol \
    contracts/src/libraries/HyperdriveMath.sol \
    certora/helpers/DummyERC20A.sol \
    certora/helpers/DummyERC20B.sol \
    certora/helpers/DummyATokenA.sol \
    certora/helpers/Aave/Pool.sol \
    ./test/mocks/MockAssetId.sol \
    --verify AaveHyperdrive:certora/spec/AaveHyperdriveSasha.spec \
    --link DummyATokenA:underlyingAsset=DummyERC20A \
            DummyATokenA:POOL=Pool \
            AaveHyperdrive:aToken=DummyATokenA \
            AaveHyperdrive:_baseToken=DummyERC20A \
            AaveHyperdrive:pool=Pool \
    --solc solc8.18 \
    --loop_iter 1 \
    --staging \
    --optimistic_loop \
    --rule_sanity \
    --send_only \
    --settings -t=500,-dontStopAtFirstSplitTimeout=true,-depth=15 \
    --packages @aave=lib/aave-v3-core/contracts @openzeppelin=node_modules/@openzeppelin \
    $RULE \
    --msg "AaveHyperdrive: $RULE $MSG" 
