// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IPool } from "aave/interfaces/IPool.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { AaveHyperdriveCoreDeployer } from "contracts/src/deployers/aave/AaveHyperdriveCoreDeployer.sol";
import { AaveHyperdriveDeployerCoordinator } from "contracts/src/deployers/aave/AaveHyperdriveDeployerCoordinator.sol";
import { AaveTarget0Deployer } from "contracts/src/deployers/aave/AaveTarget0Deployer.sol";
import { AaveTarget1Deployer } from "contracts/src/deployers/aave/AaveTarget1Deployer.sol";
import { AaveTarget2Deployer } from "contracts/src/deployers/aave/AaveTarget2Deployer.sol";
import { AaveTarget3Deployer } from "contracts/src/deployers/aave/AaveTarget3Deployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { InstanceTest } from "test/utils/InstanceTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

// FIXME
//
// contract AaveHyperdriveTest is InstanceTest {
//     using FixedPointMath for uint256;
//     using Lib for *;
//     using stdStorage for StdStorage;
//
//     // FIXME: Update this address and comment which Aave pool we're using.
//     IPool internal constant POOL =
//         IPool(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
//
//     // FIXME: Find an Aave whale for the pool that I choose to use.
//     //
//     // Whale accounts.
//     address internal STETH_WHALE = 0x1982b2F5814301d4e9a8b0201555376e62F82428;
//     address[] internal whaleAccounts = [STETH_WHALE];
//
//     // FIXME: Update this.
//     //
//     // The configuration for the Instance testing suite.
//     InstanceTestConfig internal __testConfig =
//         InstanceTestConfig(
//             "Hyperdrive",
//             "AaveHyperdrive",
//             whaleAccounts,
//             // FIXME: What is the base token?
//             IERC20(ETH),
//             // FIXME: What is the AToken address?
//             IERC20(LIDO),
//             // FIXME: Update this.
//             1e5,
//             // FIXME: Update this.
//             1e15,
//             POSITION_DURATION,
//             true,
//             true,
//             true,
//             true
//         );
//
//     /// @dev Instantiates the Instance testing suite with the configuration.
//     constructor() InstanceTest(__testConfig) {}
//
//     // FIXME: Update this.
//     //
//     /// @dev Forge function that is invoked to setup the testing environment.
//     function setUp() public override __mainnet_fork(17_376_154) {
//         // Invoke the Instance testing suite setup.
//         super.setUp();
//     }
//
//     /// Overrides ///
//
//     // FIXME: Update this.
//     //
//     /// @dev Converts base amount to the equivalent about in stETH.
//     function convertToShares(
//         uint256 baseAmount
//     ) internal view override returns (uint256) {
//         // Get protocol state information used for calculating shares.
//         uint256 totalPooledEther = LIDO.getTotalPooledEther();
//         uint256 totalShares = LIDO.getTotalShares();
//         return baseAmount.mulDivDown(totalShares, totalPooledEther);
//     }
//
//     // FIXME: Update this.
//     //
//     /// @dev Converts share amount to the equivalent amount in ETH.
//     function convertToBase(
//         uint256 shareAmount
//     ) internal view override returns (uint256) {
//         // Lido has a built-in function for computing price in terms of base.
//         return LIDO.getPooledEthByShares(shareAmount);
//     }
//
//     /// @dev Deploys the Aave deployer coordinator contract.
//     /// @param _factory The address of the Hyperdrive factory.
//     function deployCoordinator(
//         address _factory
//     ) internal override returns (address) {
//         vm.startPrank(alice);
//         return
//             address(
//                 new AaveHyperdriveDeployerCoordinator(
//                     string.concat(__testConfig.name, "DeployerCoordinator"),
//                     _factory,
//                     address(new AaveHyperdriveCoreDeployer()),
//                     address(new AaveTarget0Deployer()),
//                     address(new AaveTarget1Deployer()),
//                     address(new AaveTarget2Deployer()),
//                     address(new AaveTarget3Deployer())
//                 )
//             );
//     }
//
//     // FIXME: Update this.
//     //
//     /// @dev Fetches the total supply of the base and share tokens.
//     function getSupply() internal view override returns (uint256, uint256) {
//         return (LIDO.getTotalPooledEther(), LIDO.getTotalShares());
//     }
//
//     // FIXME: Update this.
//     //
//     /// @dev Fetches the token balance information of an account.
//     function getTokenBalances(
//         address account
//     ) internal view override returns (uint256, uint256) {
//         return (LIDO.balanceOf(account), LIDO.sharesOf(account));
//     }
//
//     // FIXME: Update this.
//     //
//     /// @dev Verifies that deposit accounting is correct when opening positions.
//     function verifyDeposit(
//         address trader,
//         uint256 amountPaid,
//         bool asBase,
//         uint256 totalBaseBefore,
//         uint256 totalSharesBefore,
//         AccountBalances memory traderBalancesBefore,
//         AccountBalances memory hyperdriveBalancesBefore
//     ) internal view override {
//         if (asBase) {
//             // Ensure that the amount of pooled ether increased by the base paid.
//             assertEq(LIDO.getTotalPooledEther(), totalBaseBefore + amountPaid);
//
//             // Ensure that the ETH balances were updated correctly.
//             assertEq(
//                 address(hyperdrive).balance,
//                 hyperdriveBalancesBefore.ETHBalance
//             );
//             assertEq(bob.balance, traderBalancesBefore.ETHBalance - amountPaid);
//
//             // Ensure that the stETH balances were updated correctly.
//             assertApproxEqAbs(
//                 LIDO.balanceOf(address(hyperdrive)),
//                 hyperdriveBalancesBefore.baseBalance + amountPaid,
//                 1
//             );
//             assertEq(LIDO.balanceOf(trader), traderBalancesBefore.baseBalance);
//
//             // Ensure that the stETH shares were updated correctly.
//             uint256 expectedShares = amountPaid.mulDivDown(
//                 totalSharesBefore,
//                 totalBaseBefore
//             );
//             assertEq(LIDO.getTotalShares(), totalSharesBefore + expectedShares);
//             assertEq(
//                 LIDO.sharesOf(address(hyperdrive)),
//                 hyperdriveBalancesBefore.sharesBalance + expectedShares
//             );
//             assertEq(LIDO.sharesOf(bob), traderBalancesBefore.sharesBalance);
//         } else {
//             // Ensure that the amount of pooled ether stays the same.
//             assertEq(LIDO.getTotalPooledEther(), totalBaseBefore);
//
//             // Ensure that the ETH balances were updated correctly.
//             assertEq(
//                 address(hyperdrive).balance,
//                 hyperdriveBalancesBefore.ETHBalance
//             );
//             assertEq(trader.balance, traderBalancesBefore.ETHBalance);
//
//             // Ensure that the stETH balances were updated correctly.
//             assertApproxEqAbs(
//                 LIDO.balanceOf(address(hyperdrive)),
//                 hyperdriveBalancesBefore.baseBalance + amountPaid,
//                 1
//             );
//             assertApproxEqAbs(
//                 LIDO.balanceOf(trader),
//                 traderBalancesBefore.baseBalance - amountPaid,
//                 1
//             );
//
//             // Ensure that the stETH shares were updated correctly.
//             uint256 expectedShares = amountPaid.mulDivDown(
//                 totalSharesBefore,
//                 totalBaseBefore
//             );
//             assertEq(LIDO.getTotalShares(), totalSharesBefore);
//             assertApproxEqAbs(
//                 LIDO.sharesOf(address(hyperdrive)),
//                 hyperdriveBalancesBefore.sharesBalance + expectedShares,
//                 1
//             );
//             assertApproxEqAbs(
//                 LIDO.sharesOf(trader),
//                 traderBalancesBefore.sharesBalance - expectedShares,
//                 1
//             );
//         }
//     }
//
//     // FIXME: Update this.
//     //
//     /// @dev Verifies that withdrawal accounting is correct when closing positions.
//     function verifyWithdrawal(
//         address trader,
//         uint256 baseProceeds,
//         bool asBase,
//         uint256 totalPooledEtherBefore,
//         uint256 totalSharesBefore,
//         AccountBalances memory traderBalancesBefore,
//         AccountBalances memory hyperdriveBalancesBefore
//     ) internal view override {
//         // Base withdraws are not supported for this instance.
//         if (asBase) {
//             revert IHyperdrive.UnsupportedToken();
//         }
//
//         // Ensure that the total pooled ether and shares stays the same.
//         assertEq(LIDO.getTotalPooledEther(), totalPooledEtherBefore);
//         assertApproxEqAbs(LIDO.getTotalShares(), totalSharesBefore, 1);
//
//         // Ensure that the ETH balances were updated correctly.
//         assertEq(
//             address(hyperdrive).balance,
//             hyperdriveBalancesBefore.ETHBalance
//         );
//         assertEq(trader.balance, traderBalancesBefore.ETHBalance);
//
//         // Ensure that the stETH balances were updated correctly.
//         assertApproxEqAbs(
//             LIDO.balanceOf(address(hyperdrive)),
//             hyperdriveBalancesBefore.baseBalance - baseProceeds,
//             1
//         );
//         assertApproxEqAbs(
//             LIDO.balanceOf(trader),
//             traderBalancesBefore.baseBalance + baseProceeds,
//             1
//         );
//
//         // Ensure that the stETH shares were updated correctly.
//         uint256 expectedShares = baseProceeds.mulDivDown(
//             totalSharesBefore,
//             totalPooledEtherBefore
//         );
//         assertApproxEqAbs(
//             LIDO.sharesOf(address(hyperdrive)),
//             hyperdriveBalancesBefore.sharesBalance - expectedShares,
//             1
//         );
//         assertApproxEqAbs(
//             LIDO.sharesOf(trader),
//             traderBalancesBefore.sharesBalance + expectedShares,
//             1
//         );
//     }
//
//     /// Price Per Share ///
//
//     // FIXME: Update this.
//     //
//     function test__pricePerVaultShare(uint256 basePaid) external {
//         // Ensure that the share price is the expected value.
//         uint256 totalPooledEther = LIDO.getTotalPooledEther();
//         uint256 totalShares = LIDO.getTotalShares();
//         uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
//         assertEq(vaultSharePrice, totalPooledEther.divDown(totalShares));
//
//         // Ensure that the share price accurately predicts the amount of shares
//         // that will be minted for depositing a given amount of ETH. This will
//         // be an approximation since Lido uses `mulDivDown` whereas this test
//         // pre-computes the share price.
//         basePaid = basePaid.normalizeToRange(
//             2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
//             HyperdriveUtils.calculateMaxLong(hyperdrive)
//         );
//         uint256 hyperdriveSharesBefore = LIDO.sharesOf(address(hyperdrive));
//         openLong(bob, basePaid);
//         assertApproxEqAbs(
//             LIDO.sharesOf(address(hyperdrive)),
//             hyperdriveSharesBefore + basePaid.divDown(vaultSharePrice),
//             1e4
//         );
//     }
//
//     /// Long ///
//
//     // FIXME: Ensure that opening a long fails if ETH is passed with asBase as
//     //        true or false.
//     function test_open_long_nonpayable() external {
//         vm.startPrank(bob);
//
//         // Ensure that Bob receives a refund on the excess ETH that he sent
//         // when opening a long with "asBase" set to true.
//         uint256 ethBalanceBefore = address(bob).balance;
//         hyperdrive.openLong{ value: 2e18 }(
//             1e18,
//             0,
//             0,
//             IHyperdrive.Options({
//                 destination: bob,
//                 asBase: true,
//                 extraData: new bytes(0)
//             })
//         );
//         assertEq(address(bob).balance, ethBalanceBefore - 1e18);
//
//         // Ensure that Bob receives a  refund when he opens a long with "asBase"
//         // set to false and sends ether to the contract.
//         ethBalanceBefore = address(bob).balance;
//         hyperdrive.openLong{ value: 0.5e18 }(
//             1e18,
//             0,
//             0,
//             IHyperdrive.Options({
//                 destination: bob,
//                 asBase: false,
//                 extraData: new bytes(0)
//             })
//         );
//         assertEq(address(bob).balance, ethBalanceBefore);
//     }
//
//     /// Short ///
//
//     // FIXME: Ensure that opening a short fails if ETH is passed with asBase as
//     //        true or false.
//     function test_open_short_nonpayable() external {
//         vm.startPrank(bob);
//
//         // Ensure that Bob receives a refund on the excess ETH that he sent
//         // when opening a short with "asBase" set to true.
//         uint256 ethBalanceBefore = address(bob).balance;
//         (, uint256 basePaid) = hyperdrive.openShort{ value: 2e18 }(
//             1e18,
//             1e18,
//             0,
//             IHyperdrive.Options({
//                 destination: bob,
//                 asBase: true,
//                 extraData: new bytes(0)
//             })
//         );
//         assertEq(address(bob).balance, ethBalanceBefore - basePaid);
//
//         // Ensure that Bob receives a refund when he opens a short with "asBase"
//         // set to false and sends ether to the contract.
//         ethBalanceBefore = address(bob).balance;
//         hyperdrive.openShort{ value: 0.5e18 }(
//             1e18,
//             1e18,
//             0,
//             IHyperdrive.Options({
//                 destination: bob,
//                 asBase: false,
//                 extraData: new bytes(0)
//             })
//         );
//         assertEq(address(bob).balance, ethBalanceBefore);
//     }
//
//     // FIXME: Add a comment explaining what this test is for.
//     function test_round_trip_long() external {
//         // Get some balance information before the deposit.
//         LIDO.sharesOf(address(hyperdrive));
//
//         // Bob opens a long by depositing ETH.
//         uint256 basePaid = HyperdriveUtils.calculateMaxLong(hyperdrive);
//         (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);
//
//         // Get some balance information before the withdrawal.
//         uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
//         uint256 totalSharesBefore = LIDO.getTotalShares();
//         AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
//         AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
//             address(hyperdrive)
//         );
//
//         // Bob closes his long with stETH as the target asset.
//         uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
//         uint256 baseProceeds = shareProceeds.mulDivDown(
//             LIDO.getTotalPooledEther(),
//             LIDO.getTotalShares()
//         );
//
//         // Ensure that Lido's aggregates and the token balances were updated
//         // correctly during the trade.
//         verifyWithdrawal(
//             bob,
//             baseProceeds,
//             false,
//             totalPooledEtherBefore,
//             totalSharesBefore,
//             bobBalancesBefore,
//             hyperdriveBalancesBefore
//         );
//     }
//
//     /// Helpers ///
//
//     // FIXME: Update this.
//     //
//     function advanceTime(
//         uint256 timeDelta,
//         int256 variableRate
//     ) internal override {
//         // Advance the time.
//         vm.warp(block.timestamp + timeDelta);
//
//         // Accrue interest in Lido. Since the share price is given by
//         // `getTotalPooledEther() / getTotalShares()`, we can simulate the
//         // accrual of interest by multiplying the total pooled ether by the
//         // variable rate plus one.
//         uint256 bufferedEther = variableRate >= 0
//             ? LIDO.getBufferedEther() +
//                 LIDO.getTotalPooledEther().mulDown(uint256(variableRate))
//             : LIDO.getBufferedEther() -
//                 LIDO.getTotalPooledEther().mulDown(uint256(variableRate));
//         vm.store(
//             address(LIDO),
//             BUFFERED_ETHER_POSITION,
//             bytes32(bufferedEther)
//         );
//     }
// }
