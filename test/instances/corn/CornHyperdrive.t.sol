// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { CornHyperdriveCoreDeployer } from "../../../contracts/src/deployers/corn/CornHyperdriveCoreDeployer.sol";
import { CornHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/corn/CornHyperdriveDeployerCoordinator.sol";
import { CornTarget0Deployer } from "../../../contracts/src/deployers/corn/CornTarget0Deployer.sol";
import { CornTarget1Deployer } from "../../../contracts/src/deployers/corn/CornTarget1Deployer.sol";
import { CornTarget2Deployer } from "../../../contracts/src/deployers/corn/CornTarget2Deployer.sol";
import { CornTarget3Deployer } from "../../../contracts/src/deployers/corn/CornTarget3Deployer.sol";
import { CornTarget4Deployer } from "../../../contracts/src/deployers/corn/CornTarget4Deployer.sol";
import { CornConversions } from "../../../contracts/src/instances/corn/CornConversions.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { ICornHyperdrive } from "../../../contracts/src/interfaces/ICornHyperdrive.sol";
import { ICornSilo } from "../../../contracts/src/interfaces/ICornSilo.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract CornHyperdriveInstanceTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The mainnet Corn Silo.
    ICornSilo internal constant CORN_SILO =
        ICornSilo(0x8bc93498b861fd98277c3b51d240e7E56E48F23c);

    /// @dev The mainnet LBTC token.
    IERC20 internal constant LBTC =
        IERC20(0x8236a87084f8B84306f72007F36F2618A5634494);

    /// @dev Whale accounts.
    address internal BASE_TOKEN_WHALE =
        0x208567a5FF415f1081fa0f47d3A1bD60b8B03199;
    address[] internal baseTokenWhaleAccounts = [BASE_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "CornHyperdrive",
                decimals: 8,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: new address[](0),
                baseToken: LBTC,
                vaultSharesToken: IERC20(address(0)),
                shareTolerance: 0,
                minimumShareReserves: 1e5,
                minimumTransactionAmount: 1e5,
                positionDuration: POSITION_DURATION,
                fees: IHyperdrive.Fees({
                    curve: 0.001e18,
                    flat: 0.0001e18,
                    governanceLP: 0,
                    governanceZombie: 0
                }),
                enableBaseDeposits: true,
                enableShareDeposits: false,
                enableBaseWithdraws: true,
                enableShareWithdraws: false,
                baseWithdrawError: abi.encodeWithSelector(
                    IHyperdrive.UnsupportedToken.selector
                ),
                isRebasing: false,
                shouldAccrueInterest: false,
                // The base test tolerances.
                roundTripLpInstantaneousWithBaseTolerance: 1e3,
                roundTripLpWithdrawalSharesWithBaseTolerance: 1e5,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 100,
                // NOTE: Since the curve fee isn't zero, this check is ignored.
                roundTripLongInstantaneousWithBaseTolerance: 0,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 100,
                roundTripLongMaturityWithBaseTolerance: 1e3,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 100,
                // NOTE: Since the curve fee isn't zero, this check is ignored.
                roundTripShortInstantaneousWithBaseTolerance: 0,
                roundTripShortMaturityWithBaseTolerance: 1e3,
                // NOTE: Share deposits and withdrawals are disabled, so these are
                // 0.
                //
                // The share test tolerances.
                closeLongWithSharesTolerance: 0,
                closeShortWithSharesTolerance: 0,
                roundTripLpInstantaneousWithSharesTolerance: 0,
                roundTripLpWithdrawalSharesWithSharesTolerance: 0,
                roundTripLongInstantaneousWithSharesUpperBoundTolerance: 0,
                roundTripLongInstantaneousWithSharesTolerance: 0,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 0,
                roundTripLongMaturityWithSharesTolerance: 0,
                roundTripShortInstantaneousWithSharesUpperBoundTolerance: 0,
                roundTripShortInstantaneousWithSharesTolerance: 0,
                roundTripShortMaturityWithSharesTolerance: 0,
                // The verification tolerances.
                verifyDepositTolerance: 2,
                verifyWithdrawalTolerance: 3
            })
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(20_744_342) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy the Corn instance. This is empty.
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
        return CornConversions.convertToShares(baseAmount);
    }

    /// @dev Converts share amount to the equivalent amount in base.
    /// @param shareAmount The share amount.
    /// @return The converted base amount.
    function convertToBase(
        uint256 shareAmount
    ) internal pure override returns (uint256) {
        return CornConversions.convertToBase(shareAmount);
    }

    /// @dev Deploys the rsETH Linea deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    /// @return The coordinator address.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new CornHyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new CornHyperdriveCoreDeployer(CORN_SILO)),
                    address(new CornTarget0Deployer(CORN_SILO)),
                    address(new CornTarget1Deployer(CORN_SILO)),
                    address(new CornTarget2Deployer(CORN_SILO)),
                    address(new CornTarget3Deployer(CORN_SILO)),
                    address(new CornTarget4Deployer(CORN_SILO))
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply() internal view override returns (uint256, uint256) {
        return (
            LBTC.balanceOf(address(CORN_SILO)),
            CORN_SILO.totalShares(address(LBTC))
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
            LBTC.balanceOf(account),
            CORN_SILO.sharesOf(account, address(LBTC))
        );
    }

    /// Getters ///

    /// @dev Test the instances getters.
    function test_getters() external view {
        assertEq(
            address(ICornHyperdrive(address(hyperdrive)).cornSilo()),
            address(CORN_SILO)
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
        require(variableRate == 0, "CornHyperdriveTest: variableRate isn't 0");

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);
    }
}
