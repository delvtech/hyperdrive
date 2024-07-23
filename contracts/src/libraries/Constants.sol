// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

/// @dev The placeholder address for ETH.
address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

/// @dev The version of the contracts.
string constant VERSION = "v1.0.15";

/// @dev The number of targets that must be deployed for a full deployment.
uint256 constant NUM_TARGETS = 5;

/// @dev The kind of the ERC20 Forwarder.
string constant ERC20_FORWARDER_KIND = "ERC20Forwarder";

/// @dev The kind of the ERC20 Forwarder Factory.
string constant ERC20_FORWARDER_FACTORY_KIND = "ERC20ForwarderFactory";

/// @dev The kind of the Hyperdrive checkpoint rewarder.
string constant HYPERDRIVE_CHECKPOINT_REWARDER_KIND = "HyperdriveCheckpointRewarder";

/// @dev The kind of the Hyperdrive checkpoint subrewarder.
string constant HYPERDRIVE_CHECKPOINT_SUBREWARDER_KIND = "HyperdriveCheckpointSubrewarder";

/// @dev The kind of the Hyperdrive factory.
string constant HYPERDRIVE_FACTORY_KIND = "HyperdriveFactory";

/// @dev The kind of the Hyperdrive registry.
string constant HYPERDRIVE_REGISTRY_KIND = "HyperdriveRegistry";

/// @dev The kind of the AaveHyperdrive deployer coordinator factory.
string constant AAVE_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND = "AaveHyperdriveDeployerCoordinator";

/// @dev The kind of the ChainlinkHyperdrive deployer coordinator factory.
string constant CHAINLINK_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND = "ChainlinkHyperdriveDeployerCoordinator";

/// @dev The kind of the ERC4626Hyperdrive deployer coordinator factory.
string constant ERC4626_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND = "ERC4626HyperdriveDeployerCoordinator";

/// @dev The kind of the EzETHHyperdrive deployer coordinator factory.
string constant EZETH_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND = "EzETHHyperdriveDeployerCoordinator";

/// @dev The kind of the MorphoBlueHyperdrive deployer coordinator factory.
string constant MORPHO_BLUE_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND = "MorphoBlueHyperdriveDeployerCoordinator";

/// @dev The kind of the LsETHHyperdrive deployer coordinator factory.
string constant LSETH_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND = "LsETHHyperdriveDeployerCoordinator";

/// @dev The kind of the RETHHyperdrive deployer coordinator factory.
string constant RETH_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND = "RETHHyperdriveDeployerCoordinator";

/// @dev The kind of the StETHHyperdrive deployer coordinator factory.
string constant STETH_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND = "StETHHyperdriveDeployerCoordinator";

/// @dev The kind of AaveHyperdrive.
string constant AAVE_HYPERDRIVE_KIND = "AaveHyperdrive";

/// @dev The kind of ChainlinkHyperdrive.
string constant CHAINLINK_HYPERDRIVE_KIND = "ChainlinkHyperdrive";

/// @dev The kind of ERC4626Hyperdrive.
string constant ERC4626_HYPERDRIVE_KIND = "ERC4626Hyperdrive";

/// @dev The kind of EzETHHyperdrive.
string constant EZETH_HYPERDRIVE_KIND = "EzETHHyperdrive";

/// @dev The kind of LsETHHyperdrive.
string constant LSETH_HYPERDRIVE_KIND = "LsETHHyperdrive";

/// @dev The kind of MorphoBlueHyperdrive.
string constant MORPHO_BLUE_HYPERDRIVE_KIND = "MorphoBlueHyperdrive";

/// @dev The kind of RETHHyperdrive.
string constant RETH_HYPERDRIVE_KIND = "RETHHyperdrive";

/// @dev The kind of StETHHyperdrive.
string constant STETH_HYPERDRIVE_KIND = "StETHHyperdrive";
