// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { LsETHHyperdriveCoreDeployer } from "contracts/src/deployers/lseth/LsETHHyperdriveCoreDeployer.sol";
import { LsETHHyperdriveDeployerCoordinator } from "contracts/src/deployers/lseth/LsETHHyperdriveDeployerCoordinator.sol";
import { LsETHTarget0Deployer } from "contracts/src/deployers/lseth/LsETHTarget0Deployer.sol";
import { LsETHTarget1Deployer } from "contracts/src/deployers/lseth/LsETHTarget1Deployer.sol";
import { LsETHTarget2Deployer } from "contracts/src/deployers/lseth/LsETHTarget2Deployer.sol";
import { LsETHTarget3Deployer } from "contracts/src/deployers/lseth/LsETHTarget3Deployer.sol";
import { LsETHTarget4Deployer } from "contracts/src/deployers/lseth/LsETHTarget4Deployer.sol";
import { LsETHTarget5Deployer } from "contracts/src/deployers/lseth/LsETHTarget5Deployer.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IRiverV1 } from "contracts/src/interfaces/IRiverV1.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { InstanceTest } from "test/utils/InstanceTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract LsETHHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    // The LsETH token contract.
    IRiverV1 internal constant RIVER =
        IRiverV1(0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549);

    // Whale accounts.
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

    // The configuration for the Instance testing suite.
    InstanceTestConfig internal __testConfig =
        InstanceTestConfig(
            "LsETHHyperdrive",
            whaleAccounts,
            IERC20(ETH),
            IERC20(RIVER),
            1e5,
            1e15,
            POSITION_DURATION,
            false,
            true
        );

    /// @dev Instantiates the Instance testing suite with the configuration.
    constructor() InstanceTest(__testConfig) {}

    /// @dev Forge function that is invoked to setup the testing environment.

    function setUp() public override __mainnet_fork(19_429_100) {
        // Invoke the Instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Deploys the LsETH deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory contract.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new LsETHHyperdriveDeployerCoordinator(
                    _factory,
                    address(new LsETHHyperdriveCoreDeployer()),
                    address(new LsETHTarget0Deployer()),
                    address(new LsETHTarget1Deployer()),
                    address(new LsETHTarget2Deployer()),
                    address(new LsETHTarget3Deployer()),
                    address(new LsETHTarget4Deployer()),
                    address(new LsETHTarget5Deployer()),
                    RIVER
                )
            );
    }

    /// @dev Converts base amount to the equivalent amount in LsETH.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        // River has a built-in function for computing price in terms of shares.
        return RIVER.sharesFromUnderlyingBalance(baseAmount);
    }

    /// @dev Converts base amount to the equivalent amount in ETH.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        // River has a built-in function for computing price in terms of base.
        return RIVER.underlyingBalanceFromShares(shareAmount);
    }

    /// @dev Fetches the token balance information of an account.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (RIVER.balanceOfUnderlying(account), RIVER.balanceOf(account));
    }

    /// @dev Fetches the total supply of the base and share tokens.
    function getSupply() internal view override returns (uint256, uint256) {
        return (RIVER.totalUnderlyingSupply(), RIVER.totalSupply());
    }

    /// @dev Verifies that deposit accounting is correct when opening positions.
    function verifyDeposit(
        address trader,
        uint256 amount,
        bool asBase,
        uint totalBaseBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal override {
        // Deposits as base is not supported for this instance.
        if (asBase) {
            revert IHyperdrive.NotPayable();
        }

        // Convert the amount in terms of shares.
        amount = convertToShares(amount);

        // Ensure that the ETH balances were updated correctly.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(trader.balance, traderBalancesBefore.ETHBalance);

        // Ensure that the LsETH balances were updated correctly.
        assertApproxEqAbs(
            RIVER.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.sharesBalance + amount,
            1
        );
        assertApproxEqAbs(
            RIVER.balanceOf(trader),
            traderBalancesBefore.sharesBalance - amount,
            1
        );

        // Ensure the total base supply was updated correctly.
        assertEq(RIVER.totalUnderlyingSupply(), totalBaseBefore);

        // Ensure the total supply was updated correctly.
        assertEq(RIVER.totalSupply(), totalSharesBefore);
    }

    /// Price Per Share ///

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

    /// Long ///

    function test_open_long_refunds() external {
        vm.startPrank(bob);

        // Ensure that the call fails when he opens a long with "asBase"
        // set to true and sends ether to the contract.
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openLong{ value: 2e18 }(
            1e18,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Ensure that the call fails when he opens a long with "asBase"
        // set to false and sends ether to the contract.
        uint256 sharesPaid = 1e18;
        uint256 ethBalanceBefore = address(bob).balance;
        RIVER.approve(address(hyperdrive), sharesPaid);
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openLong{ value: sharesPaid }(
            sharesPaid,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: false,
                extraData: new bytes(0)
            })
        );
        assertEq(address(bob).balance, ethBalanceBefore);
    }

    function test_close_long_with_eth(
        uint256 basePaid,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION, 0.05e18);
        vm.startPrank(bob);

        // Calculate the maximum amount of basePaid we can test. The limit is
        // either the max long that Hyperdrive can open or the amount of LsETH
        // tokens the trader has.
        uint256 maxLongAmount = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEthAmount = RIVER.underlyingBalanceFromShares(
            RIVER.balanceOf(bob)
        );

        // Bob opens a long, paying with LsETH.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxLongAmount > maxEthAmount ? maxEthAmount : maxLongAmount
        );
        uint256 sharesPaid = RIVER.sharesFromUnderlyingBalance(basePaid);
        RIVER.approve(address(hyperdrive), sharesPaid);
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            sharesPaid,
            false
        );

        // The term passes and some interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Bob closes the long with ETH as the target asset.
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        hyperdrive.closeLong(
            maturityTime,
            longAmount,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_close_long_with_lseth(
        uint256 basePaid,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION, 0.05e18);
        vm.startPrank(bob);

        // Calculate the maximum amount of basePaid we can test. The limit is
        // either the max long that Hyperdrive can open or the amount of LsETH
        // tokens the trader has.
        uint256 maxLongAmount = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEthAmount = RIVER.underlyingBalanceFromShares(
            RIVER.balanceOf(bob)
        );

        // Bob opens a long by depositing LsETH.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxLongAmount > maxEthAmount ? maxEthAmount : maxLongAmount
        );
        uint256 sharesPaid = RIVER.sharesFromUnderlyingBalance(basePaid);
        RIVER.approve(address(hyperdrive), sharesPaid);
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            sharesPaid,
            false
        );

        // The term passes and some interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Get some balance information before the withdrawal.
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );
        uint256 totalLsethSupplyBefore = RIVER.totalSupply();

        // Bob closes his long with LsETH as the target asset.
        uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
        uint256 baseProceeds = RIVER.underlyingBalanceFromShares(shareProceeds);

        // Ensure Bob is credited the correct amount of bonds.
        assertLe(baseProceeds, longAmount);
        assertApproxEqAbs(baseProceeds, longAmount, 10);

        // Ensure that River aggregates and the token balances were updated
        // correctly during the trade.
        verifyLsethWithdrawal(
            bob,
            shareProceeds,
            false,
            totalLsethSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// Short ///

    function test_open_short_refunds() external {
        vm.startPrank(bob);

        // Ensure that the refund fails when he opens a short with "asBase"
        // set to true and sends ether to the contract.
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openShort{ value: 2e18 }(
            1e18,
            1e18,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Ensure that the refund fails when he opens a short with "asBase"
        // set to false and sends ether to the contract.
        uint256 sharesPaid = 1e18;
        uint256 ethBalanceBefore = address(bob).balance;
        RIVER.approve(address(hyperdrive), sharesPaid);
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openShort{ value: sharesPaid }(
            sharesPaid,
            sharesPaid,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: false,
                extraData: new bytes(0)
            })
        );
        assertEq(address(bob).balance, ethBalanceBefore);
    }

    function test_close_short_with_eth(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION, 0.05e18);

        // Bob opens a short by depositing LsETH.
        vm.startPrank(bob);
        shortAmount = shortAmount.normalizeToRange(
            100 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        RIVER.approve(address(hyperdrive), shortAmount);
        (uint256 maturityTime, ) = openShort(bob, shortAmount, false);

        // Bob attempts to close the short after the position
        // duration for ETH. The interest rate range is limited because
        // the test case not fail when there is zero accrued interest.
        variableRate = variableRate.normalizeToRange(0.01e18, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        hyperdrive.closeShort(
            maturityTime,
            shortAmount,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_close_short_with_lseth(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION, 0.05e18);

        // Bob opens a short by depositing LsETH.
        vm.startPrank(bob);
        shortAmount = shortAmount.normalizeToRange(
            100 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        RIVER.approve(address(hyperdrive), shortAmount);
        (uint256 maturityTime, ) = openShort(bob, shortAmount, false);

        // The term passes and interest accrues.
        uint256 startingVaultSharePrice = hyperdrive
            .getPoolInfo()
            .vaultSharePrice;
        variableRate = variableRate.normalizeToRange(0.01e18, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Get some balance information before closing the short.
        uint256 totalLsethSupplyBefore = RIVER.totalSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his short with LsETH as the target asset. Bob's proceeds
        // should be the variable interest that accrued on the shorted bonds.
        uint256 expectedBaseProceeds = shortAmount.mulDivDown(
            hyperdrive.getPoolInfo().vaultSharePrice - startingVaultSharePrice,
            startingVaultSharePrice
        );
        uint256 shareProceeds = closeShort(
            bob,
            maturityTime,
            shortAmount,
            false
        );
        uint256 baseProceeds = RIVER.underlyingBalanceFromShares(shareProceeds);
        assertLe(baseProceeds, expectedBaseProceeds + 10);
        assertApproxEqAbs(baseProceeds, expectedBaseProceeds, 100);

        // Ensure that River aggregates and the token balances were updated
        // correctly during the trade.
        verifyLsethWithdrawal(
            bob,
            shareProceeds,
            false,
            totalLsethSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function verifyLsethWithdrawal(
        address trader,
        uint256 amount,
        bool asBase,
        uint256 totalLsethSupplyBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        if (asBase) {
            revert IHyperdrive.NotPayable();
        }

        // Ensure the total amount of LsETH stays the same.
        assertEq(RIVER.totalSupply(), totalLsethSupplyBefore);

        // Ensure that the ETH balances were updated correctly.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(trader.balance, traderBalancesBefore.ETHBalance);

        // Ensure the LsETH balances were updated correctly.
        assertEq(
            RIVER.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.sharesBalance - amount
        );
        assertEq(
            RIVER.balanceOf(address(trader)),
            traderBalancesBefore.sharesBalance + amount
        );
    }

    /// Helpers ///

    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Storage slot for LsETH underlying ether balance.
        bytes32 lastConsensusLayerReportSlot = bytes32(
            uint256(keccak256("river.state.lastConsensusLayerReport"))
        );

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Load the validator balance from the last consensus
        // layer report slot.
        uint256 validatorBalance = uint256(
            vm.load(address(RIVER), lastConsensusLayerReportSlot)
        );

        // Increase the balance by the variable rate.
        uint256 newValidatorBalance = variableRate >= 0
            ? validatorBalance.mulDown(uint256(variableRate + 1e18))
            : validatorBalance.mulDown(uint256(1e18 - variableRate));
        vm.store(
            address(RIVER),
            lastConsensusLayerReportSlot,
            bytes32(newValidatorBalance)
        );
    }

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
