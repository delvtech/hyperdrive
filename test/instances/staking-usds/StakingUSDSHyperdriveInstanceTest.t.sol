// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { StakingUSDSHyperdriveCoreDeployer } from "../../../contracts/src/deployers/staking-usds/StakingUSDSHyperdriveCoreDeployer.sol";
import { StakingUSDSHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/staking-usds/StakingUSDSHyperdriveDeployerCoordinator.sol";
import { StakingUSDSTarget0Deployer } from "../../../contracts/src/deployers/staking-usds/StakingUSDSTarget0Deployer.sol";
import { StakingUSDSTarget1Deployer } from "../../../contracts/src/deployers/staking-usds/StakingUSDSTarget1Deployer.sol";
import { StakingUSDSTarget2Deployer } from "../../../contracts/src/deployers/staking-usds/StakingUSDSTarget2Deployer.sol";
import { StakingUSDSTarget3Deployer } from "../../../contracts/src/deployers/staking-usds/StakingUSDSTarget3Deployer.sol";
import { StakingUSDSTarget4Deployer } from "../../../contracts/src/deployers/staking-usds/StakingUSDSTarget4Deployer.sol";
import { StakingUSDSConversions } from "../../../contracts/src/instances/staking-usds/StakingUSDSConversions.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IStakingUSDS } from "../../../contracts/src/interfaces/IStakingUSDS.sol";
import { IStakingUSDSHyperdrive } from "../../../contracts/src/interfaces/IStakingUSDSHyperdrive.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract StakingUSDSHyperdriveInstanceTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The StakingRewards contract.
    IStakingUSDS internal immutable stakingUSDS;

    /// @notice Instantiates the instance testing suite with the configuration.
    /// @param _config The instance test configuration.
    /// @param _stakingUSDS The StakingRewards contract.
    constructor(
        InstanceTestConfig memory _config,
        IStakingUSDS _stakingUSDS
    ) InstanceTest(_config) {
        stakingUSDS = _stakingUSDS;
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy the StakingUSDS instance. This
    ///      includes the StakingRewards vault address.
    /// @return The empty extra data.
    function getExtraData() internal view override returns (bytes memory) {
        return abi.encode(stakingUSDS);
    }

    /// @dev Converts base amount to the equivalent about in shares.
    /// @param baseAmount The base amount.
    /// @return The converted share amount.
    function convertToShares(
        uint256 baseAmount
    ) internal pure override returns (uint256) {
        return StakingUSDSConversions.convertToShares(baseAmount);
    }

    /// @dev Converts share amount to the equivalent amount in base.
    /// @param shareAmount The share amount.
    /// @return The converted base amount.
    function convertToBase(
        uint256 shareAmount
    ) internal pure override returns (uint256) {
        return StakingUSDSConversions.convertToBase(shareAmount);
    }

    /// @dev Deploys the StakingUSDS Hyperdrive deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    /// @return The coordinator address.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new StakingUSDSHyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new StakingUSDSHyperdriveCoreDeployer()),
                    address(new StakingUSDSTarget0Deployer()),
                    address(new StakingUSDSTarget1Deployer()),
                    address(new StakingUSDSTarget2Deployer()),
                    address(new StakingUSDSTarget3Deployer()),
                    address(new StakingUSDSTarget4Deployer())
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply() internal view override returns (uint256, uint256) {
        return (
            config.baseToken.balanceOf(address(stakingUSDS)),
            stakingUSDS.totalSupply()
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
            stakingUSDS.balanceOf(account)
        );
    }

    /// Getters ///

    /// @dev Test the instances getters.
    function test_getters() external view {
        assertEq(
            address(IStakingUSDSHyperdrive(address(hyperdrive)).stakingUSDS()),
            address(stakingUSDS)
        );
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

    /// Rewards ///

    /// @dev A test that ensures that Hyperdrive is set up to claim the staking
    ///      rewards.
    function test__rewards() external {
        // If the rewards token is the zero address, this is a points vault, and
        // we skip this test.
        if (address(stakingUSDS.rewardsToken()) == address(0)) {
            return;
        }

        // Advance time to accrue rewards.
        advanceTime(POSITION_DURATION, 0);

        // Ensure that Hyperdrive has earned staking rewards.
        uint256 earned = stakingUSDS.earned(address(hyperdrive));

        // Claim the staking rewards and ensure that Hyperdrive actually
        // received them.
        IStakingUSDSHyperdrive(address(hyperdrive)).claimRewards();
        assertEq(
            stakingUSDS.rewardsToken().balanceOf(address(hyperdrive)),
            earned
        );

        // Ensure that the staking rewards can be claimed by the sweep collector.
        address sweepCollector = hyperdrive.getPoolConfig().sweepCollector;
        vm.stopPrank();
        vm.startPrank(sweepCollector);
        hyperdrive.sweep(stakingUSDS.rewardsToken());
        assertEq(stakingUSDS.rewardsToken().balanceOf(sweepCollector), earned);
        assertEq(stakingUSDS.rewardsToken().balanceOf(address(hyperdrive)), 0);
    }

    /// Helpers ///

    /// @dev Advance time and accrue interest.
    /// @param timeDelta The time to advance.
    /// @param variableRate The variable rate.
    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Corn doesn't accrue interest, so we revert if the variable rate isn't
        // zero.
        require(
            variableRate == 0,
            "StakingUSDSHyperdriveTest: variableRate isn't 0"
        );

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);
    }
}
