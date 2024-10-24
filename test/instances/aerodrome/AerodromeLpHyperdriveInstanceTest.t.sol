// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IGauge } from "aerodrome/interfaces/IGauge.sol";
import { AerodromeLpHyperdriveCoreDeployer } from "../../../contracts/src/deployers/aerodrome-lp/AerodromeLpHyperdriveCoreDeployer.sol";
import { AerodromeLpHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/aerodrome-lp/AerodromeLpHyperdriveDeployerCoordinator.sol";
import { AerodromeLpTarget0Deployer } from "../../../contracts/src/deployers/aerodrome-lp/AerodromeLpTarget0Deployer.sol";
import { AerodromeLpTarget1Deployer } from "../../../contracts/src/deployers/aerodrome-lp/AerodromeLpTarget1Deployer.sol";
import { AerodromeLpTarget2Deployer } from "../../../contracts/src/deployers/aerodrome-lp/AerodromeLpTarget2Deployer.sol";
import { AerodromeLpTarget3Deployer } from "../../../contracts/src/deployers/aerodrome-lp/AerodromeLpTarget3Deployer.sol";
import { AerodromeLpTarget4Deployer } from "../../../contracts/src/deployers/aerodrome-lp/AerodromeLpTarget4Deployer.sol";
import { AerodromeLpConversions } from "../../../contracts/src/instances/aerodrome-lp/AerodromeLpConversions.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IAerodromeLpHyperdrive } from "../../../contracts/src/interfaces/IAerodromeLpHyperdrive.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract AerodromeLpHyperdriveInstanceTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The Aerodrome Gauage contract.
    IGauge internal immutable gauge;

    /// @notice Instantiates the instance testing suite with the configuration.
    /// @param _config The instance test configuration.
    constructor(
        InstanceTestConfig memory _config,
        IGauge _gauge
    ) InstanceTest(_config) {
        gauge = _gauge;
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy the Aerodrome LP instance. This
    ///      is empty.
    /// @return The empty extra data.
    function getExtraData() internal pure override returns (bytes memory) {
        return new bytes(0);
    }

    /// @dev Converts base amount to the equivalent about in shares.
    /// @param baseAmount The base amount.
    /// @return The converted share amount.
    function convertToShares(
        uint256 baseAmount
    ) internal pure override returns (uint256) {
        return AerodromeLpConversions.convertToShares(baseAmount);
    }

    /// @dev Converts share amount to the equivalent amount in base.
    /// @param shareAmount The share amount.
    /// @return The converted base amount.
    function convertToBase(
        uint256 shareAmount
    ) internal pure override returns (uint256) {
        return AerodromeLpConversions.convertToBase(shareAmount);
    }

    /// @dev Deploys the AerodromeLp Hyperdrive deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    /// @return The coordinator address.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new AerodromeLpHyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new AerodromeLpHyperdriveCoreDeployer(gauge)),
                    address(new AerodromeLpTarget0Deployer(gauge)),
                    address(new AerodromeLpTarget1Deployer(gauge)),
                    address(new AerodromeLpTarget2Deployer(gauge)),
                    address(new AerodromeLpTarget3Deployer(gauge)),
                    address(new AerodromeLpTarget4Deployer(gauge))
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply() internal view override returns (uint256, uint256) {
        return (
            config.baseToken.balanceOf(address(gauge)),
            config.baseToken.balanceOf(address(gauge))
            // gauge.totalSupply()
            // config.baseToken.balanceOf(address(hyperdrive))
        );
    }

    /// @dev Fetches the token balance information of an account.
    /// @param account The account to query.
    /// @return The balance of base.
    /// @return The balance of vault shares.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (
            config.baseToken.balanceOf(account),
            gauge.balanceOf(address(account))
        );
    }

    /// Getters ///

    /// @dev Test the instances getters.
    function test_getters() external view {
        (, uint256 totalShares) = getTokenBalances(address(hyperdrive));
        assertEq(hyperdrive.totalShares(), totalShares);
    }

    /// Price Per Share ///

    /// @dev Fuzz test that verifies that the vault share price is the price
    ///      that dictates the conversion between base and shares.
    /// @param basePaid The fuzz parameter for the base paid.
    function test__pricePerVaultShare(uint256 basePaid) external {
        // Ensure that the share price is the expected value.
        (uint256 totalBase, uint256 totalShares) = getSupply();
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, totalBase.divDown(totalShares));

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of shares. This will
        // be an approximation.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxLong()
        );
        (, uint256 hyperdriveSharesBefore) = getTokenBalances(
            address(hyperdrive)
        );
        openLong(bob, basePaid);
        (, uint256 hyperdriveSharesAfter) = getTokenBalances(
            address(hyperdrive)
        );
        assertApproxEqAbs(
            hyperdriveSharesAfter,
            hyperdriveSharesBefore + basePaid.divDown(vaultSharePrice),
            config.shareTolerance
        );
    }

    /// Helpers ///

    /// @dev Advance time and accrue interest.
    /// @param timeDelta The time to advance.
    /// @param variableRate The variable rate.
    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // AerodromeLp doesn't accrue interest, so we revert if the variable
        // rate isn't zero.
        require(
            variableRate == 0,
            "AerodromeLpHyperdriveTest: variableRate isn't 0"
        );

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);
    }
}
