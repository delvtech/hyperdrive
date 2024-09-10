// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { ChainlinkHyperdriveCoreDeployer } from "../../../contracts/src/deployers/chainlink/ChainlinkHyperdriveCoreDeployer.sol";
import { ChainlinkHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/chainlink/ChainlinkHyperdriveDeployerCoordinator.sol";
import { ChainlinkTarget0Deployer } from "../../../contracts/src/deployers/chainlink/ChainlinkTarget0Deployer.sol";
import { ChainlinkTarget1Deployer } from "../../../contracts/src/deployers/chainlink/ChainlinkTarget1Deployer.sol";
import { ChainlinkTarget2Deployer } from "../../../contracts/src/deployers/chainlink/ChainlinkTarget2Deployer.sol";
import { ChainlinkTarget3Deployer } from "../../../contracts/src/deployers/chainlink/ChainlinkTarget3Deployer.sol";
import { ChainlinkTarget4Deployer } from "../../../contracts/src/deployers/chainlink/ChainlinkTarget4Deployer.sol";
import { ChainlinkConversions } from "../../../contracts/src/instances/chainlink/ChainlinkConversions.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/src/interfaces/IChainlinkAggregatorV3.sol";
import { IChainlinkHyperdrive } from "../../../contracts/src/interfaces/IChainlinkHyperdrive.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

abstract contract ChainlinkHyperdriveInstanceTest is InstanceTest {
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The Chainlink aggregator proxy used by this instance.
    IChainlinkAggregatorV3 internal immutable _chainlinkAggregator;

    /// @notice Instantiates the Instance testing suite with the configuration.
    /// @param _config The instance test configuration.
    /// @param __chainlinkAggregator The chainlink aggregator used by this
    ///        instance.
    constructor(
        InstanceTestConfig memory _config,
        IChainlinkAggregatorV3 __chainlinkAggregator
    ) InstanceTest(_config) {
        _chainlinkAggregator = __chainlinkAggregator;
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy the Chainlink instance.
    /// @return The extra data containing the Chainlink aggregator and the
    ///         decimals that the instance should use.
    function getExtraData() internal view override returns (bytes memory) {
        return abi.encode(_chainlinkAggregator, uint8(18));
    }

    /// @dev Converts base amount to the equivalent about in shares.
    /// @param baseAmount The base amount.
    /// @return The converted share amount.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        return
            ChainlinkConversions.convertToShares(
                _chainlinkAggregator,
                baseAmount
            );
    }

    /// @dev Converts share amount to the equivalent amount in base.
    /// @param shareAmount The share amount.
    /// @return The converted base amount.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        return
            ChainlinkConversions.convertToBase(
                _chainlinkAggregator,
                shareAmount
            );
    }

    /// @dev Deploys the Chainlink deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    /// @return The coordinator address.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new ChainlinkHyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new ChainlinkHyperdriveCoreDeployer()),
                    address(new ChainlinkTarget0Deployer()),
                    address(new ChainlinkTarget1Deployer()),
                    address(new ChainlinkTarget2Deployer()),
                    address(new ChainlinkTarget3Deployer()),
                    address(new ChainlinkTarget4Deployer())
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply() internal view override returns (uint256, uint256) {
        return (0, config.vaultSharesToken.totalSupply());
    }

    /// @dev Fetches the token balance information of an account.
    /// @param account The account to query.
    /// @return The balance of base.
    /// @return The balance of vault shares.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (0, config.vaultSharesToken.balanceOf(account));
    }

    /// Getters ///

    /// @dev Test the instances getters.
    function test_getters() external view {
        assertEq(
            address(IChainlinkHyperdrive(address(hyperdrive)).aggregator()),
            address(_chainlinkAggregator)
        );
        (, uint256 totalShares) = getTokenBalances(address(hyperdrive));
        assertEq(hyperdrive.totalShares(), totalShares);
    }

    /// Helpers ///

    /// @dev Advance time and accrue interest.
    /// @param timeDelta The time to advance.
    /// @param variableRate The variable rate.
    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Get the latest round ID and answer. We'll overwrite this round ID
        // with the updated answer.
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,

        ) = _chainlinkAggregator.latestRoundData();
        uint256 answer_ = uint256(answer);

        // Accrue interest in the Chainlink aggregator. We do this by
        // overwriting the latest round's answer.
        (answer_, ) = uint256(answer_).calculateInterest(
            variableRate,
            timeDelta
        );
        bytes32 latestRoundLocation = keccak256(
            abi.encode(uint32(roundId), 44)
        );
        vm.store(
            address(_chainlinkAggregator.aggregator()),
            latestRoundLocation,
            bytes32((updatedAt << 192) | answer_)
        );
    }
}
