.PHONY: build build-sol test test-sol lint \
	lint-sol code-size-check solhint style-check spell-check warnings-check \
	prettier

### Build ###

# hyperdrivetypes build must be done after sol build
build:
	make build-sol
	make build-hyperdrivetypes

build-sol:
	forge build

# forge build will do nothing if build-sol was previously run,
# but we put it here so this can be called individually
build-hyperdrivetypes:
	forge build && pypechain --output-dir python/hyperdrivetypes/hyperdrivetypes/types --line-length 80 --parallel out/ && . scripts/set-hyperdrivetypes-version.sh

### Test ###

SOLIDITY_LP_WITHDRAWAL_TESTS = LPWithdrawalTest
SOLIDITY_NETTING_TESTS = IntraCheckpointNettingTest
SOLIDITY_ZOMBIE_TESTS = ZombieInterestTest

test:
	make test-sol

test-sol: test-sol-core test-sol-instances test-sol-lp-withdrawal test-sol-netting test-sol-zombie


test-sol-core:
	forge test -vv \
		--no-match-contract "$(SOLIDITY_LP_WITHDRAWAL_TESTS)|$(SOLIDITY_NETTING_TESTS)|$(SOLIDITY_ZOMBIE_TESTS)" \
		--no-match-path "test/combinatorial/*.t.sol test/instances/*.t.sol"

test-sol-combinatorial:
	forge test -vv --match-path "test/combinatorial/*.t.sol"

test-sol-instances:
	forge test -vv --match-path test/instances/*.t.sol

# NOTE: Breaking these out onto a separate machine speeds up CI execution.
test-sol-lp-withdrawal:
	forge test -vv --match-contract "$(SOLIDITY_LP_WITHDRAWAL_TESTS)"

# NOTE: Breaking these out onto a separate machine speeds up CI execution.
test-sol-netting:
	forge test -vv --match-contract "$(SOLIDITY_NETTING_TESTS)"

# NOTE: Breaking these out onto a separate machine speeds up CI execution.
test-sol-zombie:
	forge test -vv --match-contract "$(SOLIDITY_ZOMBIE_TESTS)"

test-python:
	pytest python/
	
### Lint ###

lint:
	make lint-sol

lint-sol:
	make solhint && make style-check && make spell-check && make warnings-check && make code-size-check

code-size-check:
	FOUNDRY_PROFILE=production forge build && python3 python/contract_size.py out

solhint:
	npx solhint -f table 'contracts/src/**/*.sol'

spell-check:
	npx cspell ./**/**/**.sol --gitignore

style-check:
	npx prettier --check .

warnings-check:
	FOUNDRY_PROFILE=production forge build --deny-warnings --force

### Prettier ###

prettier:
	npx prettier --write .

### Deploy ###

deploy:
	./scripts/deploy.sh

generate-deploy:
	./scripts/generate-deploy-config.sh

deploy-fork:
	./scripts/deploy-fork.sh
