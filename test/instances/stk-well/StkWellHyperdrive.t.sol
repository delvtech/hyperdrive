// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { StkWellHyperdriveCoreDeployer } from "../../../contracts/src/deployers/stk-well/StkWellHyperdriveCoreDeployer.sol";
import { StkWellHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/stk-well/StkWellHyperdriveDeployerCoordinator.sol";
import { StkWellTarget0Deployer } from "../../../contracts/src/deployers/stk-well/StkWellTarget0Deployer.sol";
import { StkWellTarget1Deployer } from "../../../contracts/src/deployers/stk-well/StkWellTarget1Deployer.sol";
import { StkWellTarget2Deployer } from "../../../contracts/src/deployers/stk-well/StkWellTarget2Deployer.sol";
import { StkWellTarget3Deployer } from "../../../contracts/src/deployers/stk-well/StkWellTarget3Deployer.sol";
import { StkWellTarget4Deployer } from "../../../contracts/src/deployers/stk-well/StkWellTarget4Deployer.sol";
import { StkWellConversions } from "../../../contracts/src/instances/stk-well/StkWellConversions.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IStakedToken } from "../../../contracts/src/interfaces/IStakedToken.sol";
import { IStkWellHyperdrive } from "../../../contracts/src/interfaces/IStkWellHyperdrive.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract StkWellHyperdriveInstanceTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The WELL token.
    IERC20 internal constant WELL =
        IERC20(0xA88594D404727625A9437C3f886C7643872296AE);

    /// @dev The Moonwell staking vault.
    IStakedToken internal constant STK_WELL =
        IStakedToken(0xe66E3A37C3274Ac24FE8590f7D84A2427194DC17);

    /// @dev Whale accounts.
    address internal BASE_TOKEN_WHALE =
        0x89D0F320ac73dd7d9513FFC5bc58D1161452a657;
    address[] internal baseTokenWhaleAccounts = [BASE_TOKEN_WHALE];
    address internal VAULT_SHARES_TOKEN_WHALE =
        0x5E564c1905fFF9724621542f58d61BE0405C4879;
    address[] internal vaultSharesTokenWhaleAccounts = [
        VAULT_SHARES_TOKEN_WHALE
    ];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "StkWellHyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: WELL,
                vaultSharesToken: IERC20(address(STK_WELL)),
                shareTolerance: 0,
                minimumShareReserves: 1e15,
                minimumTransactionAmount: 1e15,
                positionDuration: POSITION_DURATION,
                fees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                }),
                enableBaseDeposits: true,
                enableShareDeposits: true,
                enableBaseWithdraws: false,
                enableShareWithdraws: true,
                baseWithdrawError: abi.encodeWithSelector(
                    IHyperdrive.UnsupportedToken.selector
                ),
                isRebasing: false,
                shouldAccrueInterest: false,
                // The base test tolerances.
                closeLongWithBaseTolerance: 2,
                roundTripLpInstantaneousWithBaseTolerance: 1e3,
                roundTripLpWithdrawalSharesWithBaseTolerance: 1e7,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithBaseTolerance: 1e4,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 100,
                roundTripLongMaturityWithBaseTolerance: 1e3,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithBaseTolerance: 1e3,
                roundTripShortMaturityWithBaseTolerance: 1e3,
                // The share test tolerances.
                closeLongWithSharesTolerance: 2,
                closeShortWithSharesTolerance: 2,
                roundTripLpInstantaneousWithSharesTolerance: 1e3,
                roundTripLpWithdrawalSharesWithSharesTolerance: 1e7,
                roundTripLongInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithSharesTolerance: 1e4,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 100,
                roundTripLongMaturityWithSharesTolerance: 1e3,
                roundTripShortInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithSharesTolerance: 1e3,
                roundTripShortMaturityWithSharesTolerance: 1e3,
                // The verification tolerances.
                verifyDepositTolerance: 2,
                verifyWithdrawalTolerance: 3
            })
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __base_fork(20_821_395) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy the StkWell instance. This is
    ///      just empty data.
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
        return StkWellConversions.convertToShares(baseAmount);
    }

    /// @dev Converts share amount to the equivalent amount in base.
    /// @param shareAmount The share amount.
    /// @return The converted base amount.
    function convertToBase(
        uint256 shareAmount
    ) internal pure override returns (uint256) {
        return StkWellConversions.convertToBase(shareAmount);
    }

    /// @dev Deploys the StkWell Hyperdrive deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    /// @return The coordinator address.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new StkWellHyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new StkWellHyperdriveCoreDeployer()),
                    address(new StkWellTarget0Deployer()),
                    address(new StkWellTarget1Deployer()),
                    address(new StkWellTarget2Deployer()),
                    address(new StkWellTarget3Deployer()),
                    address(new StkWellTarget4Deployer())
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply() internal view override returns (uint256, uint256) {
        return (
            config.baseToken.balanceOf(address(STK_WELL)),
            STK_WELL.totalSupply()
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
            STK_WELL.balanceOf(account)
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

    /// Rewards ///

    /// @dev A test that ensures that Hyperdrive is set up to claim the staking
    ///      rewards.
    function test__rewards() external {
        // If the rewards token is the zero address, this is a points vault, and
        // we skip this test.
        IERC20 rewardsToken = STK_WELL.REWARD_TOKEN();
        if (address(rewardsToken) == address(0)) {
            return;
        }

        // Advance time to accrue rewards.
        advanceTime(POSITION_DURATION, 0);

        // Ensure that Hyperdrive has earned staking rewards.
        uint256 rewards = STK_WELL.stakerRewardsToClaim(address(hyperdrive));

        // Claim the staking rewards and ensure that Hyperdrive actually
        // received them.
        IStkWellHyperdrive(address(hyperdrive)).claimRewards();
        assertEq(rewardsToken.balanceOf(address(hyperdrive)), rewards);

        // Ensure that the staking rewards can be claimed by the sweep collector.
        address sweepCollector = hyperdrive.getPoolConfig().sweepCollector;
        vm.stopPrank();
        vm.startPrank(sweepCollector);
        hyperdrive.sweep(rewardsToken);
        assertEq(rewardsToken.balanceOf(sweepCollector), rewards);
        assertEq(rewardsToken.balanceOf(address(hyperdrive)), 0);
    }

    /// Helpers ///

    /// @dev Advance time and accrue interest.
    /// @param timeDelta The time to advance.
    /// @param variableRate The variable rate.
    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Staked Well doesn't accrue interest, so we revert if the variable
        // rate isn't zero.
        require(
            variableRate == 0,
            "StkWellHyperdriveTest: variableRate isn't 0"
        );

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);
    }
}
