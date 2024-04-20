# Hyperdrive Deploy Scripts

Hyperdrive contract deployments have three primary steps:

1. Deploy the `HyperdriveFactory`, `HyperdriveRegistry`, and all `HyperdriveDeploymentCoordinator` instances.

2. Governance approves the `HyperdriveDeploymentCoordinator` instances on the `HyperdriveFactory` contract.

3. Hyperdrive instances and their targets are deployed via the `HyperdriveFactory` contract.

## `FactoryDeployer.s.sol`

- Handles part 1
- Reads in a factory configuration file (EX: [./config/sepolia-factory.toml](./config/sepolia-factory.toml)).

- Requires the following variables be set in your `.env` file:

  ```sh
  ETHERSCAN_API_KEY=<...>
  PRIVATE_KEY=<...>
  ```

- Sample call:

  ```sh
  CONFIG_FILENAME=sepolia-factory.toml forge script ./script/deploy/FactoryDeployer.s.sol --broadcast --verify --multi --priority-gas-price 1
  ```

- Outputs a summary to [./summaries](./summaries)

## `PoolDeployer.s.sol`

- Handles part 3
- Reads in a pool configuration file (EX: [./config/sepolia-pool-DAI-SDAI.toml](./config/sepolia-pool-DAI-SDAI.toml)).

- Requires the following variables be set in your `.env` file:

  ```sh
  ETHERSCAN_API_KEY=<...>
  PRIVATE_KEY=<...>
  ```

- Sample call:

  ```sh
  CONFIG_FILENAME=sepolia-pool-DAI-SDAI.toml forge script ./script/deploy/PoolDeployer.s.sol --broadcast --verify --multi --priority-gas-price 1
  ```

- Outputs a summary to [./summaries](./summaries)

- NOTE: The hyperdrive instance and its targets should verify properly. In case they don't, manual verification can be done by using the constructor arguments saved in the summary file for the run and running the following commands:

```sh
# Hyperdrive Instance
forge verify-contract --watch --compiler-version "v0.8.20+commit.a1b79de6" \
	--num-of-optimizations 10000000 \
	--evm-version paris \
	--constructor-args <hyperdrive_constructor_args> \
	--chain-id <your_deployment_chain_id> \
	<deployed pool address> \
	"<hyperdrive_instance_contract_name>"

# Repeat the following for each target
forge verify-contract --watch --compiler-version "v0.8.20+commit.a1b79de6" \
	--num-of-optimizations 10000000 \
	--evm-version paris \
	--constructor-args <target_constructor_args> \
	--chain-id <your_deployment_chain_id> \
	<deployed pool address> \
	"<....Target(n)>"
```