// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { ETH } from "../../../contracts/src/libraries/Constants.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IRocketDepositPool } from "../../../contracts/src/interfaces/IRocketDepositPool.sol";
import { IRocketNetworkBalances } from "../../../contracts/src/interfaces/IRocketNetworkBalances.sol";
import { IRocketStorage } from "../../../contracts/src/interfaces/IRocketStorage.sol";
import { IRocketTokenRETH } from "../../../contracts/src/interfaces/IRocketTokenRETH.sol";
import { RETHHyperdriveCoreDeployer } from "../../../contracts/src/deployers/reth/RETHHyperdriveCoreDeployer.sol";
import { RETHHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/reth/RETHHyperdriveDeployerCoordinator.sol";
import { RETHTarget0Deployer } from "../../../contracts/src/deployers/reth/RETHTarget0Deployer.sol";
import { RETHTarget1Deployer } from "../../../contracts/src/deployers/reth/RETHTarget1Deployer.sol";
import { RETHTarget2Deployer } from "../../../contracts/src/deployers/reth/RETHTarget2Deployer.sol";
import { RETHTarget3Deployer } from "../../../contracts/src/deployers/reth/RETHTarget3Deployer.sol";
import { RETHTarget4Deployer } from "../../../contracts/src/deployers/reth/RETHTarget4Deployer.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract RETHHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    // @dev Rocket Network contracts can be upgraded and addresses changed. We
    ///     can safely assume these addresses are accurate because this testing
    ///     suite is forked from block 19429100.
    IRocketStorage internal constant ROCKET_STORAGE =
        IRocketStorage(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);
    IRocketTokenRETH internal constant rocketTokenRETH =
        IRocketTokenRETH(0xae78736Cd615f374D3085123A210448E74Fc6393);
    IRocketNetworkBalances internal constant rocketNetworkBalances =
        IRocketNetworkBalances(0x07FCaBCbe4ff0d80c2b1eb42855C0131b6cba2F4);
    IRocketDepositPool internal constant rocketDepositPool =
        IRocketDepositPool(0xDD3f50F8A6CafbE9b31a427582963f465E745AF8);
    address internal constant rocketVault =
        address(0x3bDC69C4E5e13E52A65f5583c23EFB9636b469d6);

    /// @dev Whale accounts.
    address internal RETH_WHALE = 0xCc9EE9483f662091a1de4795249E24aC0aC2630f;
    address[] internal whaleAccounts = [RETH_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "RETHHyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: new address[](0),
                vaultSharesTokenWhaleAccounts: whaleAccounts,
                baseToken: IERC20(ETH),
                vaultSharesToken: IERC20(rocketTokenRETH),
                shareTolerance: 1e5,
                minimumShareReserves: 1e15,
                minimumTransactionAmount: 1e15,
                positionDuration: POSITION_DURATION,
                enableBaseDeposits: false,
                enableShareDeposits: true,
                enableBaseWithdraws: true,
                enableShareWithdraws: true,
                baseWithdrawError: new bytes(0),
                isRebasing: false,
                shouldAccrueInterest: true,
                fees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                }),
                // The base test tolerances.
                closeLongWithBaseTolerance: 20,
                roundTripLpInstantaneousWithBaseTolerance: 1e3,
                roundTripLpWithdrawalSharesWithBaseTolerance: 1e3,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithBaseTolerance: 1e3,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithBaseTolerance: 1e3,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithBaseTolerance: 1e3,
                roundTripShortMaturityWithBaseTolerance: 1e3,
                // The share test tolerances.
                closeLongWithSharesTolerance: 20,
                closeShortWithSharesTolerance: 100,
                roundTripLpInstantaneousWithSharesTolerance: 2e3,
                roundTripLpWithdrawalSharesWithSharesTolerance: 2e3,
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
        // Give the rETH contract ETH to mimic adequate withdrawable liquidity.
        vm.deal(address(rocketTokenRETH), 50_000e18);

        // Invoke the instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy Hyperdrive instances.
    /// @return The extra data.
    function getExtraData() internal pure override returns (bytes memory) {
        return new bytes(0);
    }

    /// @dev Converts base amount to the equivalent about in rETH.
    /// @param baseAmount The base amount.
    /// @return The converted share amount.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        // Rocket Pool has a built-in function for computing price in terms of shares.
        return rocketTokenRETH.getRethValue(baseAmount);
    }

    /// @dev Converts share amount to the equivalent amount in ETH.
    /// @param shareAmount The share amount.
    /// @return The converted base amount.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        // Rocket Pool has a built-in function for computing price in terms of base.
        return rocketTokenRETH.getEthValue(shareAmount);
    }

    /// @dev Deploys the rETH deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory contract.
    /// @return The coordinator address.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new RETHHyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new RETHHyperdriveCoreDeployer()),
                    address(new RETHTarget0Deployer()),
                    address(new RETHTarget1Deployer()),
                    address(new RETHTarget2Deployer()),
                    address(new RETHTarget3Deployer()),
                    address(new RETHTarget4Deployer()),
                    rocketTokenRETH
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply() internal view override returns (uint256, uint256) {
        return (
            rocketVault.balance + address(rocketTokenRETH).balance,
            rocketTokenRETH.totalSupply()
        );
    }

    /// @dev Fetches the token balance information of an account.
    /// @param account The account to query.
    /// @return The balance of base.
    /// @return The balance of vault shares.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (account.balance, rocketTokenRETH.balanceOf(account));
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
    /// @param basePaid the fuzz parameter for the base paid.
    function test_pricePerVaultShare(uint256 basePaid) external {
        // Ensure the share prices are equal upon market inception.
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, rocketTokenRETH.getExchangeRate());

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of rETH.
        vm.startPrank(bob);
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        uint256 hyperdriveSharesBefore = rocketTokenRETH.balanceOf(
            address(hyperdrive)
        );
        uint256 sharesPaid = rocketTokenRETH.getRethValue(basePaid);
        rocketTokenRETH.approve(address(hyperdrive), sharesPaid);
        openLong(bob, sharesPaid, false);
        assertEq(
            rocketTokenRETH.balanceOf(address(hyperdrive)),
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
        // Advance the time.
        vm.startPrank(address(rocketNetworkBalances));
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in RocketPool. Since the share price is given by
        // `getTotalETHBalance() / getTotalRETHBalance()`, we can simulate the
        // accrual of interest by multiplying the total pooled ether by the
        // variable rate plus one.
        (uint256 bufferedEther, ) = rocketNetworkBalances
            .getTotalETHBalance()
            .calculateInterest(variableRate, timeDelta);
        ROCKET_STORAGE.setUint(
            keccak256("network.balance.total"),
            bufferedEther
        );
        vm.stopPrank();
    }

    /// @dev Tests that advance time works correctly by advancing the time and
    ///      ensuring that the vault share price was updated correctly.
    function test_advanced_time() external {
        vm.stopPrank();

        // Store the old rETH exchange rate.
        uint256 oldRate = rocketTokenRETH.getExchangeRate();

        // Advance time and accrue interest.
        advanceTime(POSITION_DURATION, 0.05e18);

        // Ensure the new rate is higher than the old rate.
        assertGt(rocketTokenRETH.getExchangeRate(), oldRate);
    }
}
