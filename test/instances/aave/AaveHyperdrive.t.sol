// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IPool } from "aave/interfaces/IPool.sol";
import { DataTypes } from "aave/protocol/libraries/types/DataTypes.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { AaveHyperdriveCoreDeployer } from "contracts/src/deployers/aave/AaveHyperdriveCoreDeployer.sol";
import { AaveHyperdriveDeployerCoordinator } from "contracts/src/deployers/aave/AaveHyperdriveDeployerCoordinator.sol";
import { AaveTarget0Deployer } from "contracts/src/deployers/aave/AaveTarget0Deployer.sol";
import { AaveTarget1Deployer } from "contracts/src/deployers/aave/AaveTarget1Deployer.sol";
import { AaveTarget2Deployer } from "contracts/src/deployers/aave/AaveTarget2Deployer.sol";
import { AaveTarget3Deployer } from "contracts/src/deployers/aave/AaveTarget3Deployer.sol";
import { AaveTarget4Deployer } from "contracts/src/deployers/aave/AaveTarget4Deployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IAToken } from "contracts/src/interfaces/IAToken.sol";
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

// FIXME: Dig deeper into whether or not we need support for ETH.
contract AaveHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    // The mainnet Aave V3 pool.
    IPool internal constant POOL =
        IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    // The WETH token.
    IERC20 internal constant WETH =
        IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // The aWETH AToken.
    IAToken internal constant AWETH =
        IAToken(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);

    // Whale accounts.
    address internal WETH_WHALE = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
    address internal AWETH_WHALE = 0x4353e2df4E3444e97e20b2bdA165BDd9A23913Ab;
    address[] internal baseTokenWhaleAccounts = [WETH_WHALE];
    address[] internal vaultSharesTokenWhaleAccounts = [AWETH_WHALE];

    // The configuration for the Instance testing suite.
    InstanceTestConfig internal __testConfig =
        InstanceTestConfig({
            name: "Hyperdrive",
            kind: "AaveHyperdrive",
            baseTokenWhaleAccounts: baseTokenWhaleAccounts,
            vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
            baseToken: WETH,
            vaultSharesToken: IERC20(address(AWETH)),
            // FIXME: Can this be lower? Higher?
            shareTolerance: 1e5,
            minTransactionAmount: 1e15,
            positionDuration: POSITION_DURATION,
            enableBaseDeposits: true,
            enableShareDeposits: true,
            enableBaseWithdraws: true,
            enableShareWithdraws: true
        });

    /// @dev Instantiates the Instance testing suite with the configuration.
    constructor() InstanceTest(__testConfig) {}

    /// @dev Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(20_276_503) {
        // Invoke the Instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Converts base amount to the equivalent about in shares.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        return
            baseAmount.mulDivDown(
                1e27,
                POOL.getReserveNormalizedIncome(address(WETH))
            );
    }

    /// @dev Converts share amount to the equivalent amount in base.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        return
            shareAmount.mulDivDown(
                POOL.getReserveNormalizedIncome(address(WETH)),
                1e27
            );
    }

    /// @dev Deploys the Aave deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new AaveHyperdriveDeployerCoordinator(
                    string.concat(__testConfig.name, "DeployerCoordinator"),
                    _factory,
                    address(new AaveHyperdriveCoreDeployer()),
                    address(new AaveTarget0Deployer()),
                    address(new AaveTarget1Deployer()),
                    address(new AaveTarget2Deployer()),
                    address(new AaveTarget3Deployer()),
                    address(new AaveTarget4Deployer())
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    function getSupply() internal view override returns (uint256, uint256) {
        return (AWETH.totalSupply(), AWETH.scaledTotalSupply());
    }

    /// @dev Fetches the token balance information of an account.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (
            WETH.balanceOf(account),
            convertToShares(AWETH.balanceOf(account))
        );
    }

    /// @dev Verifies that deposit accounting is correct when opening positions.
    function verifyDeposit(
        address trader,
        uint256 amountPaid,
        bool asBase,
        uint256 totalBaseBefore,
        uint256, // unused
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view override {
        if (asBase) {
            // Ensure that the total supply increased by the base paid.
            assertApproxEqAbs(
                AWETH.totalSupply(),
                totalBaseBefore + amountPaid,
                1
            );
            assertApproxEqAbs(
                AWETH.scaledTotalSupply(),
                convertToShares(totalBaseBefore + amountPaid),
                1
            );

            // Ensure that the ETH balances didn't change.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(bob.balance, traderBalancesBefore.ETHBalance);

            // Ensure that the base balances Hyperdrive base balance doesn't
            // change and that the trader base balance decreased by the amount
            // paid.
            assertApproxEqAbs(
                WETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.baseBalance,
                1
            );
            assertEq(
                WETH.balanceOf(trader),
                traderBalancesBefore.baseBalance - amountPaid
            );

            // Ensure that the shares balances were updated correctly.
            assertApproxEqAbs(
                convertToShares(AWETH.balanceOf(address(hyperdrive))),
                hyperdriveBalancesBefore.sharesBalance +
                    convertToShares(amountPaid),
                2
            );
            assertApproxEqAbs(
                convertToShares(AWETH.balanceOf(trader)),
                traderBalancesBefore.sharesBalance,
                1
            );
        } else {
            // Ensure that the total supply and scaled total supply stay the same.
            assertEq(AWETH.totalSupply(), totalBaseBefore);
            assertApproxEqAbs(
                AWETH.scaledTotalSupply(),
                convertToShares(totalBaseBefore),
                1
            );

            // Ensure that the ETH balances didn't change.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(bob.balance, traderBalancesBefore.ETHBalance);

            // Ensure that the base balances didn't change.
            assertApproxEqAbs(
                WETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.baseBalance,
                1
            );
            assertApproxEqAbs(
                WETH.balanceOf(trader),
                traderBalancesBefore.baseBalance,
                1
            );

            // Ensure that the shares balances were updated correctly.
            assertApproxEqAbs(
                convertToShares(AWETH.balanceOf(address(hyperdrive))),
                hyperdriveBalancesBefore.sharesBalance +
                    convertToShares(amountPaid),
                2
            );
            assertApproxEqAbs(
                convertToShares(AWETH.balanceOf(trader)),
                traderBalancesBefore.sharesBalance -
                    convertToShares(amountPaid),
                2
            );
        }
    }

    /// @dev Verifies that withdrawal accounting is correct when closing positions.
    function verifyWithdrawal(
        address trader,
        uint256 baseProceeds,
        bool asBase,
        uint256 totalBaseBefore,
        uint256, // unused
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view override {
        if (asBase) {
            // Ensure that the total supply decreased by the base proceeds.
            assertEq(AWETH.totalSupply(), totalBaseBefore - baseProceeds);
            assertApproxEqAbs(
                AWETH.scaledTotalSupply(),
                convertToShares(totalBaseBefore - baseProceeds),
                1
            );

            // Ensure that the ETH balances didn't change.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(bob.balance, traderBalancesBefore.ETHBalance);

            // Ensure that the balances were updated correctly.
            assertApproxEqAbs(
                AWETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.baseBalance - baseProceeds,
                1
            );
            assertEq(
                AWETH.balanceOf(trader),
                traderBalancesBefore.baseBalance + baseProceeds
            );
        } else {
            // Ensure that the total supply and scaled total supply stay the same.
            assertEq(AWETH.totalSupply(), totalBaseBefore);
            assertApproxEqAbs(
                AWETH.scaledTotalSupply(),
                convertToShares(totalBaseBefore),
                1
            );

            // Ensure that the ETH balances didn't change.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(bob.balance, traderBalancesBefore.ETHBalance);

            // Ensure that the balances were updated correctly.
            assertApproxEqAbs(
                AWETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.baseBalance - baseProceeds,
                1
            );
            assertApproxEqAbs(
                AWETH.balanceOf(trader),
                traderBalancesBefore.baseBalance + baseProceeds,
                1
            );
        }
    }

    /// Price Per Share ///

    function test__pricePerVaultShare(uint256 sharesPaid) external {
        // Ensure that the share price is the expected value.
        uint256 totalSupply = AWETH.totalSupply();
        uint256 scaledTotalSupply = AWETH.scaledTotalSupply();
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, totalSupply.divDown(scaledTotalSupply));

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of shares. This will
        // be an approximation.
        sharesPaid = sharesPaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        uint256 hyperdriveBaseBefore = AWETH.balanceOf(address(hyperdrive));
        openLong(bob, sharesPaid, false);
        assertApproxEqAbs(
            AWETH.balanceOf(address(hyperdrive)),
            hyperdriveBaseBefore + sharesPaid.mulDown(vaultSharePrice),
            1e4
        );
    }

    /// Long ///

    // FIXME
    //
    // // FIXME: Ensure that opening a long fails if ETH is passed with asBase as
    // //        true or false.
    // function test_open_long_nonpayable() external {
    //     vm.startPrank(bob);

    //     // FIXME
    //     //
    //     // Ensure that Bob receives a refund on the excess ETH that he sent
    //     // when opening a long with "asBase" set to true.
    //     uint256 ethBalanceBefore = address(bob).balance;
    //     hyperdrive.openLong{ value: 2e18 }(
    //         1e18,
    //         0,
    //         0,
    //         IHyperdrive.Options({
    //             destination: bob,
    //             asBase: true,
    //             extraData: new bytes(0)
    //         })
    //     );
    //     assertEq(address(bob).balance, ethBalanceBefore - 1e18);

    //     // FIXME
    //     //
    //     // Ensure that Bob receives a  refund when he opens a long with "asBase"
    //     // set to false and sends ether to the contract.
    //     ethBalanceBefore = address(bob).balance;
    //     hyperdrive.openLong{ value: 0.5e18 }(
    //         1e18,
    //         0,
    //         0,
    //         IHyperdrive.Options({
    //             destination: bob,
    //             asBase: false,
    //             extraData: new bytes(0)
    //         })
    //     );
    //     assertEq(address(bob).balance, ethBalanceBefore);
    // }

    /// Short ///

    // FIXME
    //
    // // FIXME: Ensure that opening a short fails if ETH is passed with asBase as
    // //        true or false.
    // function test_open_short_nonpayable() external {
    //     vm.startPrank(bob);

    //     // FIXME
    //     //
    //     // Ensure that Bob receives a refund on the excess ETH that he sent
    //     // when opening a short with "asBase" set to true.
    //     uint256 ethBalanceBefore = address(bob).balance;
    //     (, uint256 basePaid) = hyperdrive.openShort{ value: 2e18 }(
    //         1e18,
    //         1e18,
    //         0,
    //         IHyperdrive.Options({
    //             destination: bob,
    //             asBase: true,
    //             extraData: new bytes(0)
    //         })
    //     );
    //     assertEq(address(bob).balance, ethBalanceBefore - basePaid);

    //     // FIXME
    //     //
    //     // Ensure that Bob receives a refund when he opens a short with "asBase"
    //     // set to false and sends ether to the contract.
    //     ethBalanceBefore = address(bob).balance;
    //     hyperdrive.openShort{ value: 0.5e18 }(
    //         1e18,
    //         1e18,
    //         0,
    //         IHyperdrive.Options({
    //             destination: bob,
    //             asBase: false,
    //             extraData: new bytes(0)
    //         })
    //     );
    //     assertEq(address(bob).balance, ethBalanceBefore);
    // }

    // FIXME
    //
    // // FIXME: Add a comment explaining what this test is for.
    // function test_round_trip_long() external {
    //     // FIXME
    //     //
    //     // Get some balance information before the deposit.
    //     LIDO.sharesOf(address(hyperdrive));

    //     // FIXME
    //     //
    //     // Bob opens a long by depositing ETH.
    //     uint256 basePaid = HyperdriveUtils.calculateMaxLong(hyperdrive);
    //     (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

    //     // FIXME
    //     //
    //     // Get some balance information before the withdrawal.
    //     uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
    //     uint256 totalSharesBefore = LIDO.getTotalShares();
    //     AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
    //     AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
    //         address(hyperdrive)
    //     );

    //     // FIXME
    //     //
    //     // Bob closes his long with stETH as the target asset.
    //     uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
    //     uint256 baseProceeds = shareProceeds.mulDivDown(
    //         LIDO.getTotalPooledEther(),
    //         LIDO.getTotalShares()
    //     );

    //     // FIXME
    //     //
    //     // Ensure that Lido's aggregates and the token balances were updated
    //     // correctly during the trade.
    //     verifyWithdrawal(
    //         bob,
    //         baseProceeds,
    //         false,
    //         totalPooledEtherBefore,
    //         totalSharesBefore,
    //         bobBalancesBefore,
    //         hyperdriveBalancesBefore
    //     );
    // }

    /// Helpers ///

    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in the Aave pool. Since the vault share price is
        // given by `getReserveNormalizedIncome()`, we can simulate the accrual
        // of interest by multiplying the total pooled ether by the variable
        // rate plus one.
        uint256 reserveNormalizedIncome = POOL.getReserveNormalizedIncome(
            address(WETH)
        );
        reserveNormalizedIncome = variableRate >= 0
            ? reserveNormalizedIncome +
                reserveNormalizedIncome.mulDivDown(uint256(variableRate), 1e27)
            : reserveNormalizedIncome -
                reserveNormalizedIncome.mulDivDown(
                    uint256(-variableRate),
                    1e27
                );
        bytes32 reserveDataLocation = keccak256(abi.encode(address(WETH), 52));
        DataTypes.ReserveData memory data = POOL.getReserveData(address(WETH));
        vm.store(
            address(POOL),
            bytes32(uint256(reserveDataLocation) + 1),
            bytes32(
                (uint256(data.currentLiquidityRate) << 128) |
                    uint256(reserveNormalizedIncome)
            )
        );
        vm.store(
            address(POOL),
            bytes32(uint256(reserveDataLocation) + 3),
            bytes32(
                (data.id << 192) |
                    (block.timestamp << 128) |
                    data.currentStableBorrowRate
            )
        );
    }
}
