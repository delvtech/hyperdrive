.PHONY: build build-sol build-rust test test-sol test-rust lint lint-rust \
	lint-sol code-size-check solhint style-check spell-check warnings-check \
	prettier

### Build ###

build: 
	make build-sol && make build-rust

build-sol: 
	forge build

build-rust: 
	cargo build

### Test ###

SOLIDITY_HEAVY_TESTS = LPWithdrawalTest|ZombieInterestTest
SOLIDITY_NETTING_TESTS = IntraCheckpointNettingTest

test: 
	make test-sol && make test-rust

test-sol-core:
	forge test -vv --no-match-contract "$(SOLIDITY_HEAVY_TESTS)|$(SOLIDITY_NETTING_TESTS)"

# This job runs the heavier fuzz tests. Breaking these out onto a separate 
# machine speeds up CI execution.
test-sol-heavy:
	forge test -vv --match-contract "$(SOLIDITY_HEAVY_TESTS)"

# This job runs the netting tests.
test-sol-netting:
	forge test -vv --match-contract "$(SOLIDITY_NETTING_TESTS)"

test-rust:
	cargo test --workspace --exclude hyperdrive-math && \
	cargo test --package hyperdrive-math -- --test-threads=1

### Lint ###

lint:
	make lint-sol && make lint-rust

lint-sol:
	make solhint && make style-check && make spell-check && make warnings-check && make code-size-check

code-size-check:
	FOUNDRY_PROFILE=production forge build && python3 python/contract_size.py out

solhint:
	npx solhint -f table contracts/src/*.sol contracts/src/**/*.sol

spell-check:
	npx cspell ./**/**/**.sol --gitignore

style-check:
	npx prettier --check .

warnings-check:
	FOUNDRY_PROFILE=production forge build --deny-warnings --force

lint-rust:
	cargo check && cargo clippy && cargo fmt --check

### Prettier ###

prettier:
	npx prettier --write .
