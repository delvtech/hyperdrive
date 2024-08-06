// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { ChainlinkHyperdriveCoreDeployer } from "contracts/src/deployers/chainlink/ChainlinkHyperdriveCoreDeployer.sol";
import { ChainlinkHyperdriveDeployerCoordinator } from "contracts/src/deployers/chainlink/ChainlinkHyperdriveDeployerCoordinator.sol";
import { ChainlinkTarget0Deployer } from "contracts/src/deployers/chainlink/ChainlinkTarget0Deployer.sol";
import { ChainlinkTarget1Deployer } from "contracts/src/deployers/chainlink/ChainlinkTarget1Deployer.sol";
import { ChainlinkTarget2Deployer } from "contracts/src/deployers/chainlink/ChainlinkTarget2Deployer.sol";
import { ChainlinkTarget3Deployer } from "contracts/src/deployers/chainlink/ChainlinkTarget3Deployer.sol";
import { ChainlinkTarget4Deployer } from "contracts/src/deployers/chainlink/ChainlinkTarget4Deployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { ChainlinkConversions } from "contracts/src/instances/chainlink/ChainlinkConversions.sol";
import { IChainlinkAggregatorV3 } from "contracts/src/interfaces/IChainlinkAggregatorV3.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IMorphoBlueHyperdrive } from "contracts/src/interfaces/IMorphoBlueHyperdrive.sol";
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
contract ChainlinkHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    // Chainlink's wstETH-ETH reference rate aggregator on Gnosis Chain.
    IChainlinkAggregatorV3 internal constant CHAINLINK_AGGREGATOR =
        IChainlinkAggregatorV3(0x0064AC007fF665CF8D0D3Af5E0AD1c26a3f853eA);

    // The address of the wstETH token on Gnosis Chain.
    IERC20 internal constant WSTETH =
        IERC20(0x6C76971f98945AE98dD7d4DFcA8711ebea946eA6);

    // The wstETH Whale accounts.
    address internal WSTETH_WHALE =
        address(0x458cD345B4C05e8DF39d0A07220feb4Ec19F5e6f);
    address[] internal vaultSharesTokenWhaleAccounts = [WSTETH_WHALE];

    // The configuration for the Instance testing suite.
    InstanceTestConfig internal __testConfig =
        InstanceTestConfig({
            name: "Hyperdrive",
            kind: "ChainlinkHyperdrive",
            baseTokenWhaleAccounts: new address[](0),
            vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
            baseToken: IERC20(address(0)),
            vaultSharesToken: WSTETH,
            // FIXME
            shareTolerance: 0,
            minTransactionAmount: 1e15,
            positionDuration: POSITION_DURATION,
            enableBaseDeposits: false,
            enableShareDeposits: true,
            enableBaseWithdraws: false,
            enableShareWithdraws: true
        });

    /// @dev Instantiates the Instance testing suite with the configuration.
    constructor() InstanceTest(__testConfig) {}

    // FIXME: If the Gnosis Chain provider is too unreliable, we should use the
    // Optimism or Arbitrum networks instead for the purpose of our testing.
    //
    /// @dev Forge function that is invoked to setup the testing environment.
    function setUp() public override __gnosis_chain_fork(35336446) {
        // Invoke the Instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy the Chainlink instance.
    /// @return The extra data containing the Chainlink aggregator and the
    ///         decimals that the instance should use.
    function getExtraData() internal pure override returns (bytes memory) {
        return abi.encode(CHAINLINK_AGGREGATOR, uint8(18));
    }

    /// @dev Converts base amount to the equivalent about in shares.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        return
            ChainlinkConversions.convertToShares(
                CHAINLINK_AGGREGATOR,
                baseAmount
            );
    }

    /// @dev Converts share amount to the equivalent amount in base.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        return
            ChainlinkConversions.convertToBase(
                CHAINLINK_AGGREGATOR,
                shareAmount
            );
    }

    /// @dev Deploys the Chainlink deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new ChainlinkHyperdriveDeployerCoordinator(
                    string.concat(__testConfig.name, "DeployerCoordinator"),
                    _factory,
                    address(new ChainlinkHyperdriveCoreDeployer()),
                    address(new ChainlinkTarget0Deployer()),
                    address(new ChainlinkTarget1Deployer()),
                    address(new ChainlinkTarget2Deployer()),
                    address(new ChainlinkTarget3Deployer()),
                    address(new ChainlinkTarget4Deployer())
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    function getSupply() internal view override returns (uint256, uint256) {
        return (0, WSTETH.totalSupply());
    }

    /// @dev Fetches the token balance information of an account.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (0, WSTETH.balanceOf(account));
    }

    /// @dev Verifies that deposit accounting is correct when opening positions.
    function verifyDeposit(
        address trader,
        uint256 amountPaid,
        bool asBase,
        uint256 totalBaseBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view override {
        // Base deposits are not supported for this instance.
        if (asBase) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Ensure that the total supply increased by the vault shares paid.
        (uint256 totalBaseAfter, uint256 totalSharesAfter) = getSupply();
        assertEq(totalBaseAfter, totalBaseBefore);
        assertEq(totalSharesAfter, totalSharesBefore + amountPaid);

        // Ensure that the ETH balances didn't change.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(bob.balance, traderBalancesBefore.ETHBalance);

        // Ensure that none of the base balances changed.
        (
            uint256 hyperdriveBaseAfter,
            uint256 hyperdriveSharesAfter
        ) = getTokenBalances(address(hyperdrive));
        (uint256 traderBaseAfter, uint256 traderSharesAfter) = getTokenBalances(
            trader
        );
        assertEq(hyperdriveBaseAfter, hyperdriveBalancesBefore.baseBalance);
        assertEq(traderBaseAfter, traderBalancesBefore.baseBalance);

        // Ensure that the shares balances were updated correctly.
        assertEq(
            hyperdriveSharesAfter,
            hyperdriveBalancesBefore.sharesBalance + amountPaid
        );
        assertEq(
            traderSharesAfter,
            traderBalancesBefore.sharesBalance - amountPaid
        );
    }

    // FIXME
    //
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
        // Base withdrawals are not supported for this instance.
        if (asBase) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Ensure that the total supplies didn't change.
        (uint256 totalBaseAfter, uint256 totalSharesAfter) = getSupply();
        assertEq(totalBaseAfter, totalBaseBefore);
        assertEq(totalSharesAfter, totalSharesBefore);

        // Ensure that the ETH balances didn't change.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(bob.balance, traderBalancesBefore.ETHBalance);

        // Ensure that the base balances do not change.
        (
            uint256 hyperdriveBaseAfter,
            uint256 hyperdriveSharesAfter
        ) = getTokenBalances(address(hyperdrive));
        (uint256 traderBaseAfter, uint256 traderSharesAfter) = getTokenBalances(
            trader
        );
        assertEq(hyperdriveBaseAfter, hyperdriveBalancesBefore.baseBalance);
        assertEq(traderBaseAfter, traderBalancesBefore.baseBalance);

        // Ensure that the shares balances were updated correctly.
        assertEq(
            hyperdriveSharesAfter,
            hyperdriveBalancesBefore.sharesBalance -
                hyperdrive.convertToShares(baseProceeds)
        );
        assertEq(
            traderSharesAfter,
            traderBalancesBefore.sharesBalance +
                hyperdrive.convertToShares(baseProceeds)
        );
    }

    /// Price Per Share ///

    // FIXME: Is there a way to properly test this? There isn't a conversion
    // that is happening.
    //
    // function test__pricePerVaultShare(uint256 basePaid) external {
    //     // Ensure that the share price is the expected value.
    //     (uint256 totalSupplyAssets, uint256 totalSupplyShares, , ) = MORPHO
    //         .expectedMarketBalances(
    //             MarketParams({
    //                 loanToken: LOAN_TOKEN,
    //                 collateralToken: COLLATERAL_TOKEN,
    //                 oracle: ORACLE,
    //                 irm: IRM,
    //                 lltv: LLTV
    //             })
    //         );
    //     uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
    //     assertEq(vaultSharePrice, totalSupplyAssets.divDown(totalSupplyShares));

    //     // Ensure that the share price accurately predicts the amount of shares
    //     // that will be minted for depositing a given amount of shares. This will
    //     // be an approximation.
    //     basePaid = basePaid.normalizeToRange(
    //         2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
    //         hyperdrive.calculateMaxLong()
    //     );
    //     (, uint256 hyperdriveSharesBefore) = getTokenBalances(
    //         address(hyperdrive)
    //     );
    //     openLong(bob, basePaid);
    //     (, uint256 hyperdriveSharesAfter) = getTokenBalances(
    //         address(hyperdrive)
    //     );
    //     assertApproxEqAbs(
    //         hyperdriveSharesAfter,
    //         hyperdriveSharesBefore + basePaid.divDown(vaultSharePrice),
    //         __testConfig.shareTolerance
    //     );
    // }

    /// LP ///

    // FIXME: Make this a fuzz test
    function test_round_trip_lp_instantaneous() external {
        // Bob adds liquidity with base.
        uint256 contribution = 2_500e18;
        IERC20(hyperdrive.vaultSharesToken()).approve(
            address(hyperdrive),
            contribution
        );
        uint256 lpShares = addLiquidity(bob, contribution, false);

        // Get some balance information before the withdrawal.
        (uint256 totalBaseBefore, uint256 totalSharesBefore) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob removes his liquidity with base as the target asset.
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            bob,
            lpShares,
            false
        );
        assertEq(withdrawalShares, 0);

        // Bob should receive approximately as much base as he contributed since
        // no time as passed and the fees are zero.
        assertApproxEqAbs(baseProceeds, contribution, 1e10);

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            false,
            totalBaseBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    // FIXME
    //
    // FIXME: Make this a fuzz test
    function test_round_trip_lp_withdrawal_shares() external {
        // Bob adds liquidity with base.
        uint256 contribution = 2_500e18;
        IERC20(hyperdrive.vaultSharesToken()).approve(
            address(hyperdrive),
            contribution
        );
        uint256 lpShares = addLiquidity(bob, contribution, false);

        // Alice opens a large short.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 shortAmount = hyperdrive.calculateMaxShort();
        IERC20(hyperdrive.vaultSharesToken()).approve(
            address(hyperdrive),
            shortAmount
        );
        openShort(alice, shortAmount, false);

        // Bob removes his liquidity with base as the target asset.
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            bob,
            lpShares,
            false
        );
        assertEq(baseProceeds, 0);
        assertGt(withdrawalShares, 0);

        // The term passes and interest accrues.
        advanceTime(POSITION_DURATION, 1.421e18);

        // Bob should be able to redeem all of his withdrawal shares for
        // approximately the LP share price.
        uint256 lpSharePrice = hyperdrive.getPoolInfo().lpSharePrice;
        uint256 withdrawalSharesRedeemed;
        (baseProceeds, withdrawalSharesRedeemed) = redeemWithdrawalShares(
            bob,
            withdrawalShares
        );
        assertEq(withdrawalSharesRedeemed, withdrawalShares);

        // Bob should receive base approximately equal in value to his present
        // value.
        assertApproxEqAbs(
            baseProceeds,
            withdrawalShares.mulDown(lpSharePrice),
            // FIXME
            1e9
        );
    }

    /// Long ///

    function test_open_long_nonpayable() external {
        vm.startPrank(bob);

        // Ensure that sending ETH to `openLong` fails when `asBase` is true.
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

        // Ensure that sending ETH to `openLong` fails when `asBase` is false.
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openLong{ value: 0.5e18 }(
            1e18,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: false,
                extraData: new bytes(0)
            })
        );
    }

    // FIXME: Make this a fuzz test
    function test_round_trip_long_instantaneous() external {
        // Bob opens a long with vault shares.
        uint256 vaultSharesPaid = hyperdrive.convertToShares(
            hyperdrive.calculateMaxLong()
        );
        IERC20(hyperdrive.vaultSharesToken()).approve(
            address(hyperdrive),
            vaultSharesPaid
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            vaultSharesPaid,
            false
        );

        // Get some balance information before the withdrawal.
        (uint256 totalBaseBefore, uint256 totalSharesBefore) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with vault shares as the target asset.
        uint256 vaultSharesProceeds = closeLong(
            bob,
            maturityTime,
            longAmount,
            false
        );

        // Bob should receive approximately as many vault shares as he paid
        // since no time as passed and the fees are zero.
        assertApproxEqAbs(vaultSharesProceeds, vaultSharesPaid, 1e9);

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            hyperdrive.convertToBase(vaultSharesProceeds),
            false,
            totalBaseBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    // FIXME: Make this a fuzz test
    function test_round_trip_long_maturity() external {
        // Bob opens a long with vault shares.
        uint256 vaultSharesPaid = hyperdrive.convertToShares(
            hyperdrive.calculateMaxLong()
        );
        IERC20(hyperdrive.vaultSharesToken()).approve(
            address(hyperdrive),
            vaultSharesPaid
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            vaultSharesPaid,
            false
        );

        // Advance the time and accrue a large amount of interest.
        advanceTime(POSITION_DURATION, 137.123423e18);

        // Get some balance information before the withdrawal.
        (uint256 totalBaseBefore, uint256 totalSharesBefore) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with vault shares as the target asset.
        uint256 vaultSharesProceeds = closeLong(
            bob,
            maturityTime,
            longAmount,
            false
        );
        uint256 baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

        // FIXME: Evaluate tolerance.
        //
        // Bob should receive almost exactly his bond amount.
        assertApproxEqAbs(baseProceeds, longAmount, 2);

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            false,
            totalBaseBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// Short ///

    function test_open_short_nonpayable() external {
        vm.startPrank(bob);

        // Ensure that sending ETH to `openShort` fails when `asBase` is true.
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

        // Ensure that sending ETH to `openShort` fails when `asBase` is false.
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openShort{ value: 0.5e18 }(
            1e18,
            1e18,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: false,
                extraData: new bytes(0)
            })
        );
    }

    // FIXME: Make this a fuzz test
    function test_round_trip_short_instantaneous() external {
        // Bob opens a short with vault shares.
        uint256 shortAmount = hyperdrive.calculateMaxShort();
        IERC20(hyperdrive.vaultSharesToken()).approve(
            address(hyperdrive),
            shortAmount
        );
        (uint256 maturityTime, uint256 vaultSharesPaid) = openShort(
            bob,
            shortAmount,
            false
        );

        // Get some balance information before the withdrawal.
        (uint256 totalBaseBefore, uint256 totalSharesBefore) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with vault shares as the target asset.
        uint256 vaultSharesProceeds = closeShort(
            bob,
            maturityTime,
            shortAmount,
            false
        );
        uint256 baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

        // FIXME: Re-evaluate tolerance.
        //
        // Bob should receive approximately as many vault shares as he paid
        // since no time as passed and the fees are zero.
        assertApproxEqAbs(vaultSharesProceeds, vaultSharesPaid, 1e9);

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            false,
            totalBaseBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    // FIXME
    //
    // FIXME: Make this a fuzz test
    function test_round_trip_short_maturity() external {
        // Bob opens a short with vault shares.
        uint256 shortAmount = hyperdrive.calculateMaxShort();
        IERC20(hyperdrive.vaultSharesToken()).approve(
            address(hyperdrive),
            shortAmount
        );
        (uint256 maturityTime, ) = openShort(bob, shortAmount, false);

        // The term passes and some interest accrues.
        int256 variableAPR = 0.57e18;
        advanceTime(POSITION_DURATION, variableAPR);

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with vault shares as the target asset.
        uint256 vaultSharesProceeds = closeShort(
            bob,
            maturityTime,
            shortAmount,
            false
        );
        uint256 baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

        // Bob should receive almost exactly the interest that accrued on the
        // bonds that were shorted.
        assertApproxEqAbs(
            baseProceeds,
            shortAmount.mulDown(uint256(variableAPR)),
            1e9
        );

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            false,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// Helpers ///

    // FIXME
    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // FIXME
        //
        // Accrue interest in the Chainlink wstETH market. This amounts to
        // manually updating the Chainlink oracle.
    }
}
