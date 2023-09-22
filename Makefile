.PHONY: build
build: 
	make build-sol && make build-rust

.PHONY: build-sol
build-sol: 
	forge build

.PHONY: build-rust
build-rust: 
	cargo build

.PHONY: test
test: 
	make test-sol && make test-rust

.PHONY: test-sol
test-sol:
	forge test

.PHONY: test-rust
test-rust:
	cargo test --workspace --exclude hyperdrive-math && \
	cargo test --package hyperdrive-math -- --test-threads=1
