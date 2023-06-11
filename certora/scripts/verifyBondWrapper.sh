if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG="- $2"
fi

certoraRun contracts/src/BondWrapper.sol \
    certora/helpers/SymbolicHyperdrive/SymbolicHyperdrive.sol \
    \
    certora/helpers/DummyERC20A.sol \
    certora/helpers/DummyERC20B.sol \
    contracts/test/ERC20Mintable.sol \
    \
    --verify BondWrapper:certora/spec/BondWrapper.spec \
    --link BondWrapper:hyperdrive=SymbolicHyperdrive \
        BondWrapper:token=ERC20Mintable \
        SymbolicHyperdrive:_baseToken=ERC20Mintable \
    --solc solc8.18 \
    --loop_iter 3 \
    --optimistic_loop \
    --rule_sanity \
    --send_only \
    --packages @aave=lib/aave-v3-core/contracts openzeppelin-contracts=lib/openzeppelin-contracts \
    $RULE \
    --msg "BondWrapper: $RULE $MSG" 
