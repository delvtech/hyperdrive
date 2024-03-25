// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { EzETHHyperdriveCoreDeployer } from "contracts/src/deployers/ezeth/EzETHHyperdriveCoreDeployer.sol";
import { EzETHHyperdriveDeployerCoordinator } from "contracts/src/deployers/ezeth/EzETHHyperdriveDeployerCoordinator.sol";
import { EzETHTarget0Deployer } from "contracts/src/deployers/ezeth/EzETHTarget0Deployer.sol";
import { EzETHTarget1Deployer } from "contracts/src/deployers/ezeth/EzETHTarget1Deployer.sol";
import { EzETHTarget2Deployer } from "contracts/src/deployers/ezeth/EzETHTarget2Deployer.sol";
import { EzETHTarget3Deployer } from "contracts/src/deployers/ezeth/EzETHTarget3Deployer.sol";
import { EzETHTarget4Deployer } from "contracts/src/deployers/ezeth/EzETHTarget4Deployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IEzETHHyperdriveRead } from "contracts/src/interfaces/IEzETHHyperdriveRead.sol";
import { IRestakeManager } from "contracts/src/interfaces/IRenzo.sol";
import { IRenzoOracle, IDepositQueue } from "contracts/src/interfaces/IRenzo.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { InstanceTest } from "test/utils/InstanceTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract EzETHHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    // The Renzo main entrypoint contract to stake ETH and receive ezETH.
    IRestakeManager internal constant RESTAKE_MANAGER =
        IRestakeManager(0x74a09653A083691711cF8215a6ab074BB4e99ef5);

    // The Renzo Oracle contract.
    IRenzoOracle internal constant RENZO_ORACLE =
        IRenzoOracle(0x5a12796f7e7EBbbc8a402667d266d2e65A814042);

    // The ezETH token contract.
    IERC20 internal constant EZETH =
        IERC20(0xbf5495Efe5DB9ce00f80364C8B423567e58d2110);

    // Renzo's DepositQueue contract called from RestakeManager.  Used to
    // simulate interest.
    IDepositQueue DEPOSIT_QUEUE =
        IDepositQueue(0xf2F305D14DCD8aaef887E0428B3c9534795D0d60);

    // Renzo's restaking protocol was launch Dec, 2023 and their use of
    // oracles makes it difficult to test on a mainnet fork without heavy
    // mocking.  To test with their deployed code we use a shorter position
    // duration.
    uint256 internal constant POSITION_DURATION_15_DAYS = 15 days;
    uint256 internal constant STARTING_BLOCK = 19119544;

    // Whale accounts.
    address internal EZETH_WHALE = 0x40C0d1fbcB0A43A62ca7A241E7A42ca58EeF96eb;
    address[] internal whaleAccounts = [EZETH_WHALE];

    // The configuration for the Instance testing suite.
    InstanceTestConfig internal __testConfig =
        InstanceTestConfig(
            whaleAccounts,
            IERC20(EZETH),
            IERC20(ETH),
            1e6,
            1e15,
            POSITION_DURATION_15_DAYS,
            false,
            true
        );

    /// @dev Instantiates the Instance testing suite with the configuration.
    constructor() InstanceTest(__testConfig) {}

    /// @dev Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(STARTING_BLOCK) {
        // Giving the EzETH whale account more EzETH before the instance setup.
        vm.startPrank(EZETH_WHALE);
        vm.deal(EZETH_WHALE, 50_000e18);
        RESTAKE_MANAGER.depositETH{ value: 50_000e18 }();
        vm.stopPrank();

        // Invoke the Instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Converts base amount to the equivalent about in EzETH.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256 shareAmount) {
        // Get protocol state information used for calculating shares.
        (uint256 sharePrice, , ) = getSharePrice();
        return baseAmount.divDown(sharePrice);
    }

    /// @dev Deploys the EzETH deployer coordinator contract.
    function deployCoordinator() internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new EzETHHyperdriveDeployerCoordinator(
                    address(new EzETHHyperdriveCoreDeployer(RESTAKE_MANAGER)),
                    address(new EzETHTarget0Deployer(RESTAKE_MANAGER)),
                    address(new EzETHTarget1Deployer(RESTAKE_MANAGER)),
                    address(new EzETHTarget2Deployer(RESTAKE_MANAGER)),
                    address(new EzETHTarget3Deployer(RESTAKE_MANAGER)),
                    address(new EzETHTarget4Deployer(RESTAKE_MANAGER)),
                    RESTAKE_MANAGER
                )
            );
    }

    /// Getters ///

    function test_getters() external {
        assertEq(
            address(IEzETHHyperdriveRead(address(hyperdrive)).renzo()),
            address(RESTAKE_MANAGER)
        );
        assertEq(
            address(IEzETHHyperdriveRead(address(hyperdrive)).ezETH()),
            address(EZETH)
        );
        assertEq(
            address(IEzETHHyperdriveRead(address(hyperdrive)).renzoOracle()),
            address(RENZO_ORACLE)
        );
    }

    function test__ezeth_interest_and_advance_time() external {
        // hand calculated value sanity check
        uint256 positionAdjustedInterestRate = uint256(0.05e18).mulDivDown(
            POSITION_DURATION_15_DAYS,
            365 days
        );

        // Ensure that advancing time accrues interest like we expect.
        (uint256 sharePriceBefore, , ) = getSharePrice();
        advanceTime(POSITION_DURATION_15_DAYS, 0.05e18);
        (uint256 sharePriceAfter, , ) = getSharePrice();
        assertEq(positionAdjustedInterestRate, 0.002054794520547945e18);
        assertEq(
            sharePriceBefore.mulDown(1e18 + positionAdjustedInterestRate),
            sharePriceAfter
        );
    }

    /// Price Per Share ///

    function test__pricePerVaultShare(uint256 basePaid) external {
        // Ensure that the share price is the expected value.

        // Price in ETH / ezETH, does not include eigenlayer points.
        (uint256 sharePrice, , ) = getSharePrice();
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, sharePrice);

        // Calculate the maximum amount of basePaid we can test.
        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEzEth = EZETH.balanceOf(address(bob));
        uint256 maxRange = maxLong > maxEzEth ? maxEzEth : maxLong;
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxRange
        );

        // Convert to shares and approve hyperdrive.
        vm.startPrank(bob);
        uint256 sharesPaid = getAndApproveShares(basePaid);

        // Collect balance information.
        uint256 hyperdriveSharesBefore = EZETH.balanceOf(address(hyperdrive));

        // Open the position.
        openLong(bob, sharesPaid, false);

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of ETH.
        assertEq(
            EZETH.balanceOf(address(hyperdrive)),
            hyperdriveSharesBefore + sharesPaid
        );
    }

    /// Long ///

    function test_open_long_with_eth(uint256 basePaid) external {
        // Bob opens a long by depositing ETH.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );

        // Ensure that we get an UnsupportedToken error.  Opening positions
        // with ETH are not allowed right now.  There is a great enough
        // precision loss when minting ezeth that warrants some investigation
        // before we can turn this on.  Until then, we can zap ezeth into the
        // pool.
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openLong{ value: basePaid }(
            basePaid,
            0, // min bond proceeds
            0, // min vault share price
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_open_long_with_ezeth(uint256 basePaid) external {
        vm.stopPrank();
        vm.startPrank(bob);

        // Get some balance information before the deposit.
        (
            ,
            uint256 totalPooledEtherBefore,
            uint256 totalSharesBefore
        ) = getSharePrice();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Calculate the maximum amount of basePaid we can test.
        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEzEth = EZETH.balanceOf(address(bob));
        uint256 maxRange = maxLong > maxEzEth ? maxEzEth : maxLong;
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxRange
        );

        // Convert to shares and approve hyperdrive.
        uint256 sharesPaid = getAndApproveShares(basePaid);

        // Open the position.
        openLong(bob, sharesPaid, false);

        // Ensure that Renzo's aggregates and the token balances were updated
        // correctly during the trade.
        verifyDeposit(
            bob,
            basePaid,
            false,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_close_long_with_eth(uint256 basePaid) external {
        vm.stopPrank();
        vm.startPrank(bob);

        // Calculate the maximum amount of basePaid we can test.
        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEzEth = EZETH.balanceOf(address(bob));
        uint256 maxRange = maxLong > maxEzEth ? maxEzEth : maxLong;
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxRange
        );

        // Convert to shares and approve hyperdrive.
        uint256 sharesPaid = getAndApproveShares(basePaid);

        // Bob opens a long.
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            sharesPaid,
            false
        );

        // Bob attempts to close his long with ETH as the target asset. This
        // fails since ETH isn't supported as a withdrawal asset.
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

    function test_close_long_with_ezeth(
        uint256 basePaid,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION_15_DAYS, 0.05e18);
        vm.startPrank(bob);

        // Calculate the maximum amount of basePaid we can test.
        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEzEth = EZETH.balanceOf(address(bob));
        uint256 maxRange = maxLong > maxEzEth ? maxEzEth : maxLong;
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxRange
        );

        // Convert to shares and approve hyperdrive.
        uint256 sharesPaid = getAndApproveShares(basePaid);

        // Bob opens a long.
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            sharesPaid,
            false
        );

        // The term passes and some interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION_15_DAYS, variableRate);

        // Get some balance information before the withdrawal.
        (
            ,
            uint256 totalPooledEtherBefore,
            uint256 totalSharesBefore
        ) = getSharePrice();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with ezETH as the target asset.
        uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
        (
            ,
            uint256 totalPooledEtherAfter,
            uint256 totalSharesAfter
        ) = getSharePrice();
        uint256 baseProceeds = shareProceeds.mulDivDown(
            totalPooledEtherAfter,
            totalSharesAfter
        );

        // Ensuse that Bob received approximately the bond amount but wasn't
        // overpaid.
        assertLe(baseProceeds, longAmount);
        assertApproxEqAbs(baseProceeds, longAmount, 1e6);

        // Ensure that Renzo's aggregates and the token balances were updated
        // correctly during the trade.
        verifyEzethWithdrawal(
            bob,
            baseProceeds,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    // /// Short ///

    function test_open_short_with_eth(uint256 shortAmount) external {
        vm.stopPrank();
        vm.startPrank(bob);

        // Bob opens a short by depositing ETH.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );

        // Ensure that we get an UnsupportedToken error.  Opening positions
        // with ETH are not allowed right now.  There is a great enough
        // precision loss when minting ezeth that warrants some investigation
        // before we can turn this on.  Until then, we can zap ezeth into the
        // pool.
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openShort{ value: shortAmount }(
            shortAmount,
            shortAmount,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_open_short_with_ezeth(uint256 shortAmount) external {
        vm.stopPrank();
        vm.startPrank(bob);

        // Get some balance information before the deposit.
        (
            ,
            uint256 totalPooledEtherBefore,
            uint256 totalSharesBefore
        ) = getSharePrice();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Calculate the maximum amount we can short.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );

        // Bob opens a short by depositing ezETH.
        EZETH.approve(address(hyperdrive), shortAmount);
        (, uint256 sharesPaid) = openShort(bob, shortAmount, false);

        // Get the base Bob paid for the short.
        (, uint256 totalPooledEther, uint256 totalShares) = getSharePrice();
        uint256 basePaid = sharesPaid.mulDivDown(totalPooledEther, totalShares);

        // Ensure that the amount of base paid by the short is reasonable.
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            1e18
        );
        assertGt(basePaid, 0);
        assertGe(
            realizedRate,
            FIXED_RATE.mulDown(POSITION_DURATION_15_DAYS.divDown(365 days))
        );

        // Ensure that Renzo's aggregates and the token balances were updated
        // correctly during the trade.
        verifyDeposit(
            bob,
            basePaid,
            false,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_open_short_refunds() external {
        vm.startPrank(bob);

        // Collect some balance information.
        uint256 ethBalanceBefore = address(bob).balance;

        // Ensure that the transaction fails when any asBase is true.
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

        // Ensure that the transaction fails when any eth is supplied, even if
        // asBase is false.
        ethBalanceBefore = address(bob).balance;
        EZETH.approve(address(hyperdrive), 1e18);
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openShort{ value: 1e18 }(
            1e18,
            1e18,
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

        // Calculate the maximum amount we can short.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );

        // Approve hyperdrive to use bob's ezEth.
        vm.stopPrank();
        vm.startPrank(bob);
        EZETH.approve(address(hyperdrive), shortAmount);

        // Bob opens a short.
        (uint256 maturityTime, ) = openShort(bob, shortAmount, false);

        // NOTE: The variable rate must be greater than 0 since the unsupported
        // check is only triggered if the shares amount is non-zero.
        //
        // The term passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0.01e18, 2.5e18);
        advanceTime(POSITION_DURATION_15_DAYS, variableRate);

        // Bob attempts to close his short with ETH as the target asset. This
        // fails since ETH isn't supported as a withdrawal asset.
        vm.stopPrank();
        vm.startPrank(bob);
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

    function test_close_short_with_ezeth(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        // Accrue interest for a term to ensure that the share price is greater
        // than one.
        advanceTime(POSITION_DURATION_15_DAYS, 0.05e18);

        // Calculate the maximum amount we can short.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );

        // Approve hyperdrive to use bob's ezEth.
        vm.stopPrank();
        vm.startPrank(bob);
        EZETH.approve(address(hyperdrive), shortAmount);

        // Bob opens a short.
        (uint256 maturityTime, ) = openShort(bob, shortAmount, false);

        // The term passes and interest accrues.
        uint256 startingVaultSharePrice = hyperdrive
            .getPoolInfo()
            .vaultSharePrice;
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION_15_DAYS, variableRate);

        // Get some balance information before closing the short.
        (
            ,
            uint256 totalPooledEtherBefore,
            uint256 totalSharesBefore
        ) = getSharePrice();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his short with ezETH as the target asset. Bob's proceeds
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
        (, uint256 totalPooledEther, uint256 totalShares) = getSharePrice();
        uint256 baseProceeds = shareProceeds.mulDivDown(
            totalPooledEther,
            totalShares
        );
        assertLe(baseProceeds, expectedBaseProceeds + 1e4);
        assertApproxEqAbs(baseProceeds, expectedBaseProceeds, 1e6);

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyEzethWithdrawal(
            bob,
            baseProceeds,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_attack_long_ezeth() external {
        // Get some balance information before the deposit.
        EZETH.balanceOf(address(hyperdrive));

        vm.startPrank(bob);

        // Figure out the max shares
        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxEzEth = EZETH.balanceOf(address(bob));
        uint256 basePaid = maxLong > maxEzEth ? maxEzEth : maxLong;
        uint256 sharesPaid = getAndApproveShares(basePaid);

        // Bob opens a long by depositing ezETH.
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            sharesPaid,
            false
        );

        // Get some balance information before the withdrawal.
        (
            ,
            uint256 totalPooledEtherBefore,
            uint256 totalSharesBefore
        ) = getSharePrice();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with ezETH as the target asset.
        uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
        (, uint256 totalPooledEther, uint256 totalShares) = getSharePrice();
        uint256 baseProceeds = shareProceeds.mulDivDown(
            totalPooledEther,
            totalShares
        );

        // Ensure that Renzo's aggregates and the token balances were updated
        // correctly during the trade.
        verifyEzethWithdrawal(
            bob,
            baseProceeds,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function verifyDeposit(
        address trader,
        uint256 basePaid,
        bool asBase,
        uint256 totalPooledEtherBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        if (asBase) {
            // Ensure that the amount of pooled ether increased by the base paid.
            (, uint256 totalPooledEther, ) = getSharePrice();
            assertEq(totalPooledEther, totalPooledEtherBefore + basePaid);

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(bob.balance, traderBalancesBefore.ETHBalance - basePaid);

            // Ensure ezETH shares were updated correctly.
            assertEq(
                EZETH.balanceOf(trader),
                traderBalancesBefore.ezethBalance
            );

            // Ensure that the ezETH shares were updated correctly.
            uint256 expectedShares = RENZO_ORACLE.calculateMintAmount(
                totalPooledEtherBefore,
                basePaid,
                totalSharesBefore
            );
            assertEq(EZETH.totalSupply(), totalSharesBefore + expectedShares);
            assertEq(
                EZETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.ezethBalance + expectedShares
            );
            assertEq(EZETH.balanceOf(bob), traderBalancesBefore.ezethBalance);
        } else {
            // Ensure that the amount of pooled ether stays the same.
            (, uint256 totalPooledEther, ) = getSharePrice();
            assertEq(totalPooledEther, totalPooledEtherBefore);

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(trader.balance, traderBalancesBefore.ETHBalance);

            // Ensure that the ezETH shares were updated correctly.
            uint256 expectedShares = basePaid.mulDivDown(
                totalSharesBefore,
                totalPooledEtherBefore
            );
            assertEq(EZETH.totalSupply(), totalSharesBefore);
            assertApproxEqAbs(
                EZETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.ezethBalance + expectedShares,
                1
            );
            assertApproxEqAbs(
                EZETH.balanceOf(trader),
                traderBalancesBefore.ezethBalance - expectedShares,
                1
            );
        }
    }

    function verifyEzethWithdrawal(
        address trader,
        uint256 baseProceeds,
        uint256 totalPooledEtherBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        // Ensure that the total pooled ether and shares stays the same.
        (, uint256 totalPooledEther, ) = getSharePrice();
        assertEq(totalPooledEther, totalPooledEtherBefore);
        assertApproxEqAbs(EZETH.totalSupply(), totalSharesBefore, 1);

        // Ensure that the ETH balances were updated correctly.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(trader.balance, traderBalancesBefore.ETHBalance);

        // Ensure that the ezETH shares were updated correctly.
        uint256 expectedShares = baseProceeds.mulDivDown(
            totalSharesBefore,
            totalPooledEtherBefore
        );
        assertApproxEqAbs(
            EZETH.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.ezethBalance - expectedShares,
            1
        );
        assertApproxEqAbs(
            EZETH.balanceOf(trader),
            traderBalancesBefore.ezethBalance + expectedShares,
            1
        );
    }

    /// Helpers ///

    function advanceTime(
        uint256 timeDelta, // assume a position duration jump
        int256 variableRate // annual variable rate
    ) internal override {
        // Advance the time by a position duration and accrue interest.  We
        // adjust the variable rate to the position duration and multiply the
        // TVL to get interest:
        //
        //  sharePriceBefore * adjustedVariableRate = sharePriceAfter
        //
        //  becomes:
        //
        //  (tvlBefore / ezETHSupply) * adjustedVariableRate = tvlAfter / ezETHSuuply
        //
        //  tvlBefore * adjustedVariableRate = tvlAfter
        //
        //  Since the ezETHSupply is held constant when we advanceTime.

        (, uint256 totalTVLBefore, ) = getSharePrice();
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in Renzo. Since the share price is given by
        // `RESTAKE_MANAGER.calculateTVLs() / EZETH.totalSupply()`, we can simulate the
        // accrual of interest by adding to the balance of the DepositQueue contract.
        // RestakeManager adds the balance of the DepositQueue to totalTVL in calculateTVLs()
        uint256 adjustedVariableRate = uint256(variableRate).mulDivDown(
            POSITION_DURATION_15_DAYS,
            365 days
        );
        uint256 ethToAdd = totalTVLBefore.mulDown(adjustedVariableRate);
        if (variableRate >= 0) {
            vm.startPrank(address(RESTAKE_MANAGER));
            vm.deal(address(RESTAKE_MANAGER), ethToAdd);
            // use this method because no fees are taken
            DEPOSIT_QUEUE.depositETHFromProtocol{ value: ethToAdd }();
        } else {
            // NOTE: can't support subtracting eth when depositQueue has a zero balance.
            vm.deal(
                address(DEPOSIT_QUEUE),
                address(DEPOSIT_QUEUE).balance - ethToAdd
            );
        }
    }

    struct AccountBalances {
        uint256 ezethBalance;
        uint256 ETHBalance;
    }

    function getAccountBalances(
        address account
    ) internal view returns (AccountBalances memory) {
        return
            AccountBalances({
                ezethBalance: EZETH.balanceOf(account),
                ETHBalance: account.balance
            });
    }

    // returns share price information.
    function getSharePrice()
        internal
        view
        returns (
            uint256 sharePrice,
            uint256 totalPooledEther,
            uint256 totalShares
        )
    {
        // Get the total TVL priced in ETH from restakeManager.
        (, , uint256 totalTVL) = RESTAKE_MANAGER.calculateTVLs();

        // Get the total supply of the ezETH token.
        uint256 totalSupply = EZETH.totalSupply();

        // Calculate the share price.
        sharePrice = RENZO_ORACLE.calculateRedeemAmount(
            ONE,
            totalSupply,
            totalTVL
        );

        return (sharePrice, totalTVL, totalSupply);
    }

    function getAndApproveShares(
        uint256 basePaid
    ) internal returns (uint256 sharesPaid) {
        // Get the share amount.
        (, uint256 totalPooledEther, uint256 totalShares) = getSharePrice();
        sharesPaid = basePaid.mulDivDown(totalShares, totalPooledEther);

        // Approve hyperdrive to use the shares.
        EZETH.approve(address(hyperdrive), sharesPaid);
    }
}
