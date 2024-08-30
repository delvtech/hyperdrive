// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { LsETHHyperdriveCoreDeployer } from "../../../contracts/src/deployers/lseth/LsETHHyperdriveCoreDeployer.sol";
import { LsETHHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/lseth/LsETHHyperdriveDeployerCoordinator.sol";
import { LsETHTarget0Deployer } from "../../../contracts/src/deployers/lseth/LsETHTarget0Deployer.sol";
import { LsETHTarget1Deployer } from "../../../contracts/src/deployers/lseth/LsETHTarget1Deployer.sol";
import { LsETHTarget2Deployer } from "../../../contracts/src/deployers/lseth/LsETHTarget2Deployer.sol";
import { LsETHTarget3Deployer } from "../../../contracts/src/deployers/lseth/LsETHTarget3Deployer.sol";
import { LsETHTarget4Deployer } from "../../../contracts/src/deployers/lseth/LsETHTarget4Deployer.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IRiverV1 } from "../../../contracts/src/interfaces/IRiverV1.sol";
import { ETH } from "../../../contracts/src/libraries/Constants.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract LsETHHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The LsETH token contract.
    IRiverV1 internal constant RIVER =
        IRiverV1(0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549);

    /// @dev Whale accounts.
    address internal constant LSETH_WHALE =
        0xF047ab4c75cebf0eB9ed34Ae2c186f3611aEAfa6;
    address internal constant LSETH_WHALE_2 =
        0xAe60d8180437b5C34bB956822ac2710972584473;
    address internal constant LSETH_WHALE_3 =
        0xa6941E15B15fF30F2B2d42AE922134A82F6b7189;
    address[] internal whaleAccounts = [
        LSETH_WHALE,
        LSETH_WHALE_2,
        LSETH_WHALE_3
    ];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "LsETHHyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: new address[](0),
                vaultSharesTokenWhaleAccounts: whaleAccounts,
                baseToken: IERC20(ETH),
                vaultSharesToken: IERC20(RIVER),
                shareTolerance: 1e5,
                minimumShareReserves: 1e15,
                minimumTransactionAmount: 1e15,
                positionDuration: POSITION_DURATION,
                fees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                }),
                enableBaseDeposits: false,
                enableShareDeposits: true,
                enableBaseWithdraws: false,
                enableShareWithdraws: true,
                baseWithdrawError: abi.encodeWithSelector(
                    IHyperdrive.UnsupportedToken.selector
                ),
                isRebasing: false,
                shouldAccrueInterest: true,
                // NOTE: Base  withdrawals are disabled, so the tolerances are zero.
                //
                // The base test tolerances.
                closeLongWithBaseTolerance: 20,
                roundTripLpInstantaneousWithBaseTolerance: 0,
                roundTripLpWithdrawalSharesWithBaseTolerance: 0,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 0,
                roundTripLongInstantaneousWithBaseTolerance: 0,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 0,
                roundTripLongMaturityWithBaseTolerance: 0,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 0,
                roundTripShortInstantaneousWithBaseTolerance: 0,
                roundTripShortMaturityWithBaseTolerance: 0,
                // The share test tolerances.
                closeLongWithSharesTolerance: 20,
                closeShortWithSharesTolerance: 100,
                roundTripLpInstantaneousWithSharesTolerance: 1e3,
                roundTripLpWithdrawalSharesWithSharesTolerance: 1e3,
                roundTripLongInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithSharesTolerance: 1e4,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 100,
                roundTripLongMaturityWithSharesTolerance: 3e3,
                roundTripShortInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithSharesTolerance: 1e3,
                roundTripShortMaturityWithSharesTolerance: 1e3,
                // The verification tolerances.
                verifyDepositTolerance: 2,
                verifyWithdrawalTolerance: 2
            })
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(19_429_100) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy Hyperdrive instances.
    /// @return The extra data.
    function getExtraData() internal pure override returns (bytes memory) {
        return new bytes(0);
    }

    /// @dev Deploys the LsETH deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory contract.
    /// @return The coordinator address.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new LsETHHyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new LsETHHyperdriveCoreDeployer()),
                    address(new LsETHTarget0Deployer()),
                    address(new LsETHTarget1Deployer()),
                    address(new LsETHTarget2Deployer()),
                    address(new LsETHTarget3Deployer()),
                    address(new LsETHTarget4Deployer()),
                    RIVER
                )
            );
    }

    /// @dev Converts base amount to the equivalent about in shares.
    /// @param baseAmount The base amount.
    /// @return The converted share amount.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        // River has a built-in function for computing price in terms of shares.
        return RIVER.sharesFromUnderlyingBalance(baseAmount);
    }

    /// @dev Converts share amount to the equivalent amount in base.
    /// @param shareAmount The share amount.
    /// @return The converted base amount.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        // River has a built-in function for computing price in terms of base.
        return RIVER.underlyingBalanceFromShares(shareAmount);
    }

    /// @dev Fetches the total supply of the base and share tokens.
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply() internal view override returns (uint256, uint256) {
        return (address(RIVER).balance, RIVER.totalSupply());
    }

    /// @dev Fetches the token balance information of an account.
    /// @param account The account to query.
    /// @return The balance of base.
    /// @return The balance of vault shares.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (account.balance, RIVER.balanceOf(account));
    }

    /// Getters ///

    /// @dev Test for the additional getters.
    function test_getters() external view {
        (, uint256 totalShares) = getTokenBalances(address(hyperdrive));
        assertEq(hyperdrive.totalShares(), totalShares);
    }

    /// Price Per Share ///

    /// @dev Fuzz test that verifies that the vault share price is the price
    ///      that dictates the conversion between base and shares.
    /// @param basePaid the fuzz parameter for the base paid.
    function test_pricePerVaultShare(uint256 basePaid) external {
        // Ensure the share prices are equal upon market inception.
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, RIVER.underlyingBalanceFromShares(1e18));

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of LsETH.
        vm.startPrank(bob);
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        uint256 hyperdriveSharesBefore = RIVER.balanceOf(address(hyperdrive));
        uint256 sharesPaid = RIVER.sharesFromUnderlyingBalance(basePaid);
        RIVER.approve(address(hyperdrive), sharesPaid);
        openLong(bob, sharesPaid, false);
        assertEq(
            RIVER.balanceOf(address(hyperdrive)),
            hyperdriveSharesBefore + sharesPaid
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
        // Storage slot for LsETH underlying ether balance.
        bytes32 lastConsensusLayerReportSlot = bytes32(
            uint256(keccak256("river.state.lastConsensusLayerReport"))
        );

        // Get the total underlying supply. This is the numerator of the vault
        // share price. We'll modify this value to accrue interest. Since this
        // is broken up over several storage values, we'll modify the largest
        // value, `validatorBalance`.
        uint256 totalUnderlyingSupply = RIVER.totalUnderlyingSupply();

        // Load the validator balance from the last consensus
        // layer report slot.
        uint256 validatorBalance = uint256(
            vm.load(address(RIVER), lastConsensusLayerReportSlot)
        );

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Increase the balance by the variable rate.
        (, int256 interest) = (totalUnderlyingSupply - validatorBalance)
            .calculateInterest(variableRate, timeDelta);
        (validatorBalance, ) = validatorBalance.calculateInterest(
            variableRate,
            timeDelta
        );
        validatorBalance = interest >= 0
            ? validatorBalance + uint256(interest)
            : validatorBalance - uint256(-interest);
        vm.store(
            address(RIVER),
            lastConsensusLayerReportSlot,
            bytes32(validatorBalance)
        );
    }

    /// @dev Test that ensures that advance time works correctly by advancing
    ///      time and ensuring the the ending vault share price was updated
    ///      correctly.
    function test_advanced_time() external {
        vm.stopPrank();

        // Store the old LsETH exchange rate.
        uint256 oldRate = RIVER.underlyingBalanceFromShares(1e18);

        // Advance time and accrue interest.
        advanceTime(POSITION_DURATION, 0.05e18);

        // Ensure the new rate is higher than the old rate.
        assertGt(RIVER.underlyingBalanceFromShares(1e18), oldRate);
    }
}
