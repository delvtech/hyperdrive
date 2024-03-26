
hyperdrive-codegen --config codegen/test/test_payable_and_as_base_allowed.yaml --out contracts/src
make build-sol

hyperdrive-codegen --config codegen/test/test_not_payable_and_as_base_allowed.yaml --out contracts/src
make build-sol

hyperdrive-codegen --config codegen/test/test_not_payable_and_not_as_base_allowed.yaml --out contracts/src
make build-sol