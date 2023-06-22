if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG="- $2"
fi

certoraRun contracts/src/token/BondWrapper.sol \
    certora/helpers/SymbolicHyperdrive/SymbolicHyperdrive.sol \
    \
    certora/helpers/DummyERC20A.sol \
    certora/helpers/DummyERC20B.sol \
    certora/helpers/SymbolicHyperdrive/DummyERC20Impl.sol:DummyMintableERC20Impl \
    certora/helpers/SymbolicHyperdrive/AssetIdMock.sol \
    contracts/src/libraries/AssetId.sol \
    \
    --verify BondWrapper:certora/spec/BondWrapper.spec \
    --link BondWrapper:hyperdrive=SymbolicHyperdrive \
        BondWrapper:token=DummyMintableERC20Impl \
        SymbolicHyperdrive:_baseToken=DummyMintableERC20Impl \
    --solc solc8.19 \
    --loop_iter 3 \
    --optimistic_loop \
    --rule_sanity \
    --send_only \
    --smt_timeout 500 \
    --prover_args "-dontStopAtFirstSplitTimeout true -depth 15" \
    --packages @aave=lib/aave-v3-core/contracts openzeppelin-contracts=lib/openzeppelin-contracts solmate=lib/solmate/src \
    $RULE \
    --msg "BondWrapper: $RULE $MSG" 
