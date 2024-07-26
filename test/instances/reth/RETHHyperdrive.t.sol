// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { ERC20ForwarderFactory } from "../../../contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";
import { ETH } from "../../../contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveFactory } from "../../../contracts/src/factory/HyperdriveFactory.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IRocketDepositPool } from "../../../contracts/src/interfaces/IRocketDepositPool.sol";
import { IRocketNetworkBalances } from "../../../contracts/src/interfaces/IRocketNetworkBalances.sol";
import { IRocketPoolDAOProtocolSettingsDeposit } from "../../../contracts/src/interfaces/IRocketPoolDAOProtocolSettingsDeposit.sol";
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
    using Lib for *;
    using stdStorage for StdStorage;

    // Rocket Network contracts can be upgraded and addresses changed.
    // We can safely assume these addresses are accurate because
    // this testing suite is forked from block 19429100.
    IRocketStorage internal constant ROCKET_STORAGE =
        IRocketStorage(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);
    IRocketTokenRETH internal constant rocketTokenRETH =
        IRocketTokenRETH(0xae78736Cd615f374D3085123A210448E74Fc6393);
    IRocketNetworkBalances internal constant rocketNetworkBalances =
        IRocketNetworkBalances(0x07FCaBCbe4ff0d80c2b1eb42855C0131b6cba2F4);
    IRocketDepositPool internal constant rocketDepositPool =
        IRocketDepositPool(0xDD3f50F8A6CafbE9b31a427582963f465E745AF8);

    // Whale accounts.
    address internal RETH_WHALE = 0xCc9EE9483f662091a1de4795249E24aC0aC2630f;
    address[] internal whaleAccounts = [RETH_WHALE];

    // The configuration for the Instance testing suite.
    InstanceTestConfig internal __testConfig =
        InstanceTestConfig(
            "Hyperdrive",
            "RETHHyperdrive",
            new address[](0),
            whaleAccounts,
            IERC20(ETH),
            IERC20(rocketTokenRETH),
            1e5,
            1e15,
            POSITION_DURATION,
            false,
            true,
            true,
            true,
            new bytes(0)
        );

    /// @dev Instantiates the instance testing suite with the configuration.
    constructor() InstanceTest(__testConfig) {}

    /// @dev Forge function that is invoked to setup the testing environment.
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

    /// @dev Converts base amount to the equivalent amount in rETH.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        // Rocket Pool has a built-in function for computing price in terms of shares.
        return rocketTokenRETH.getRethValue(baseAmount);
    }

    /// @dev Converts share amount to the equivalent amount in ETH.
    function convertToBase(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        // Rocket Pool has a built-in function for computing price in terms of base.
        return rocketTokenRETH.getEthValue(baseAmount);
    }

    /// @dev Deploys the rETH deployer coordinator contract.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new RETHHyperdriveDeployerCoordinator(
                    string.concat(__testConfig.name, "DeployerCoordinator"),
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
    function getSupply() internal view override returns (uint256, uint256) {
        return (
            rocketNetworkBalances.getTotalETHBalance(),
            rocketNetworkBalances.getTotalRETHSupply()
        );
    }

    /// @dev Fetches the token balance information of an account.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        uint256 rethBalance = rocketTokenRETH.balanceOf(account);
        return (rocketTokenRETH.getEthValue(rethBalance), rethBalance);
    }

    /// @dev Verifies that deposit accounting is correct when opening positions.
    function verifyDeposit(
        address trader,
        uint256 amount,
        bool asBase,
        uint256 totalBaseBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view override {
        // Deposits as base is not supported for this instance.
        if (asBase) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Convert the amount in terms of shares.
        amount = convertToShares(amount);

        // Ensure that the ETH balances were updated correctly.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(trader.balance, traderBalancesBefore.ETHBalance);

        // Ensure that the rETH balances were updated correctly.
        assertApproxEqAbs(
            rocketTokenRETH.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.sharesBalance + amount,
            1
        );
        assertApproxEqAbs(
            rocketTokenRETH.balanceOf(trader),
            traderBalancesBefore.sharesBalance - amount,
            1
        );

        // Ensure the total base supply was updated correctly.
        assertEq(rocketNetworkBalances.getTotalETHBalance(), totalBaseBefore);

        // Ensure the total supply was updated correctly.
        assertEq(rocketTokenRETH.totalSupply(), totalSharesBefore);
    }

    /// @dev Verifies that withdrawal accounting is correct when closing positions.
    function verifyWithdrawal(
        address trader,
        uint256 baseProceeds,
        bool asBase,
        uint256 totalBaseBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view override {
        // Convert baseProceeds to shares to verify accounting.
        uint256 shareProceeds = rocketTokenRETH.getRethValue(baseProceeds);

        if (asBase) {
            // Ensure the total amount of rETH were updated correctly.
            assertApproxEqAbs(
                rocketTokenRETH.totalSupply(),
                totalSharesBefore - shareProceeds,
                1
            );

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(
                trader.balance,
                traderBalancesBefore.ETHBalance + baseProceeds
            );

            // Ensure the rETH balances were updated correctly.
            assertApproxEqAbs(
                rocketTokenRETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.sharesBalance - shareProceeds,
                1
            );
            assertEq(
                rocketTokenRETH.balanceOf(address(trader)),
                traderBalancesBefore.sharesBalance
            );

            // Ensure the total base supply was updated correctly.
            assertEq(
                rocketNetworkBalances.getTotalETHBalance(),
                totalBaseBefore
            );

            // Ensure the total supply was updated correctly.
            assertApproxEqAbs(
                rocketTokenRETH.totalSupply(),
                totalSharesBefore - shareProceeds,
                1
            );
        } else {
            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(trader.balance, traderBalancesBefore.ETHBalance);

            // Ensure the rETH balances were updated correctly.
            assertApproxEqAbs(
                rocketTokenRETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.sharesBalance - shareProceeds,
                1
            );
            assertApproxEqAbs(
                rocketTokenRETH.balanceOf(address(trader)),
                traderBalancesBefore.sharesBalance + shareProceeds,
                1
            );

            // Ensure the total base supply was updated correctly.
            assertEq(
                rocketNetworkBalances.getTotalETHBalance(),
                totalBaseBefore
            );

            // Ensure the total supply was updated correctly.
            assertEq(rocketTokenRETH.totalSupply(), totalSharesBefore);
        }
    }

    /// Getters ///

    function test_getters() external view {
        (, uint256 totalShares) = getTokenBalances(address(hyperdrive));
        assertEq(hyperdrive.totalShares(), totalShares);
    }

    /// Price Per Share ///

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

    /// Long ///

    function test_open_long_refunds() external {
        vm.startPrank(bob);

        // Ensure that the refund fails when Bob sends excess ETH
        // when opening a long with "asBase" set to true.
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

        // Ensure that the refund fails when he opens a long with "asBase"
        // set to false and sends ETH to the contract.
        uint256 sharesPaid = 1e18;
        uint256 ethBalanceBefore = address(bob).balance;
        rocketTokenRETH.approve(address(hyperdrive), sharesPaid);
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openLong{ value: 0.5e18 }(
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

    // /// Short ///

    function test_open_short_refunds() external {
        vm.startPrank(bob);

        // Ensure that the refund fails when Bob sends excess ETH
        // when opening a short with "asBase" set to true.
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
        rocketTokenRETH.approve(address(hyperdrive), sharesPaid);
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openShort{ value: 1e18 }(
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

    /// Helpers ///

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
        uint256 bufferedEther = variableRate >= 0
            ? rocketNetworkBalances.getTotalETHBalance().mulDown(
                uint256(variableRate + 1e18)
            )
            : rocketNetworkBalances.getTotalETHBalance().mulDown(
                uint256(1e18 - variableRate)
            );
        ROCKET_STORAGE.setUint(
            keccak256("network.balance.total"),
            bufferedEther
        );
        vm.stopPrank();
    }

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
