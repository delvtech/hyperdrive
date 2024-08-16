// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

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
import { IChainlinkHyperdrive } from "contracts/src/interfaces/IChainlinkHyperdrive.sol";
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

contract ChainlinkHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    // Chainlink's proxy for the wstETH-ETH reference rate on Gnosis Chain.
    IChainlinkAggregatorV3 internal constant CHAINLINK_AGGREGATOR_PROXY =
        IChainlinkAggregatorV3(0x0064AC007fF665CF8D0D3Af5E0AD1c26a3f853eA);

    // The underlying aggregator used Chainlink's by Chainlink's proxy on Gnosis
    // chain.
    address internal constant CHAINLINK_AGGREGATOR =
        address(0x6dcF8CE1982Fc71E7128407c7c6Ce4B0C1722F55);

    // The address of the wstETH token on Gnosis Chain.
    IERC20 internal constant WSTETH =
        IERC20(0x6C76971f98945AE98dD7d4DFcA8711ebea946eA6);

    // The wstETH Whale accounts.
    address internal constant WSTETH_WHALE =
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
            enableShareWithdraws: true,
            baseWithdrawError: abi.encodeWithSelector(
                IHyperdrive.UnsupportedToken.selector
            )
        });

    /// @dev Instantiates the Instance testing suite with the configuration.
    constructor() InstanceTest(__testConfig) {}

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
        return abi.encode(CHAINLINK_AGGREGATOR_PROXY, uint8(18));
    }

    /// @dev Converts base amount to the equivalent about in shares.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        return
            ChainlinkConversions.convertToShares(
                CHAINLINK_AGGREGATOR_PROXY,
                baseAmount
            );
    }

    /// @dev Converts share amount to the equivalent amount in base.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        return
            ChainlinkConversions.convertToBase(
                CHAINLINK_AGGREGATOR_PROXY,
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

        // Ensure that the total shares amount stayed the same.
        (uint256 totalBaseAfter, uint256 totalSharesAfter) = getSupply();
        assertEq(totalBaseAfter, totalBaseBefore);
        assertEq(totalSharesAfter, totalSharesBefore);

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
        assertApproxEqAbs(
            hyperdriveSharesAfter,
            hyperdriveBalancesBefore.sharesBalance +
                hyperdrive.convertToShares(amountPaid),
            1
        );
        assertApproxEqAbs(
            traderSharesAfter,
            traderBalancesBefore.sharesBalance -
                hyperdrive.convertToShares(amountPaid),
            1
        );
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
        assertApproxEqAbs(
            hyperdriveSharesAfter,
            hyperdriveBalancesBefore.sharesBalance -
                hyperdrive.convertToShares(baseProceeds),
            1
        );
        assertApproxEqAbs(
            traderSharesAfter,
            traderBalancesBefore.sharesBalance +
                hyperdrive.convertToShares(baseProceeds),
            1
        );
    }

    /// Getters ///

    function test_getters() external view {
        assertEq(
            address(IChainlinkHyperdrive(address(hyperdrive)).aggregator()),
            address(CHAINLINK_AGGREGATOR_PROXY)
        );
        (, uint256 totalShares) = getTokenBalances(address(hyperdrive));
        assertEq(hyperdrive.totalShares(), totalShares);
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

    function test_round_trip_lp_instantaneous(uint256 _contribution) external {
        // Bob adds liquidity with vault shares.
        _contribution = _contribution.normalizeToRange(0.1e18, 5_000e18);
        IERC20(hyperdrive.vaultSharesToken()).approve(
            address(hyperdrive),
            _contribution
        );
        uint256 lpShares = addLiquidity(bob, _contribution, false);

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob removes his liquidity with vault shares as the target asset.
        (
            uint256 vaultSharesProceeds,
            uint256 withdrawalShares
        ) = removeLiquidity(bob, lpShares, false);
        uint256 baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);
        assertEq(withdrawalShares, 0);

        // Bob should receive approximately as many vault shares as he
        // contributed since no time as passed and the fees are zero.
        assertApproxEqAbs(vaultSharesProceeds, _contribution, 1);

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

    function test_round_trip_lp_withdrawal_shares(
        uint256 _contribution,
        uint256 _variableRate
    ) external {
        // Bob adds liquidity with base.
        _contribution = _contribution.normalizeToRange(500e18, 5_000e18);
        IERC20(hyperdrive.vaultSharesToken()).approve(
            address(hyperdrive),
            _contribution
        );
        uint256 lpShares = addLiquidity(bob, _contribution, false);

        // Alice opens a large short.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 shortAmount = hyperdrive.convertToShares(
            hyperdrive.calculateMaxShort()
        );
        IERC20(hyperdrive.vaultSharesToken()).approve(
            address(hyperdrive),
            shortAmount
        );
        openShort(alice, shortAmount, false);

        // Bob removes his liquidity with base as the target asset.
        (
            uint256 vaultShareProceeds,
            uint256 withdrawalShares
        ) = removeLiquidity(bob, lpShares, false);
        if (withdrawalShares == 0) {
            return;
        }

        // The term passes and interest accrues.
        _variableRate = _variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, int256(_variableRate));

        // Bob should be able to redeem all of his withdrawal shares for
        // approximately the LP share price.
        uint256 lpSharePrice = hyperdrive.getPoolInfo().lpSharePrice;
        uint256 withdrawalSharesRedeemed;
        (vaultShareProceeds, withdrawalSharesRedeemed) = redeemWithdrawalShares(
            bob,
            withdrawalShares,
            false
        );
        uint256 baseProceeds = hyperdrive.convertToBase(vaultShareProceeds);
        assertEq(withdrawalSharesRedeemed, withdrawalShares);

        // Bob should receive vault shares approximately equal in value to his
        // present value.
        assertApproxEqAbs(
            baseProceeds,
            withdrawalShares.mulDown(lpSharePrice),
            1e5
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

    function test_round_trip_long_instantaneous(
        uint256 _vaultSharesPaid
    ) external {
        // Bob opens a long with vault shares.
        _vaultSharesPaid = hyperdrive.convertToShares(
            _vaultSharesPaid.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                hyperdrive.calculateMaxLong()
            )
        );
        IERC20(hyperdrive.vaultSharesToken()).approve(
            address(hyperdrive),
            _vaultSharesPaid
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            _vaultSharesPaid,
            false
        );

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
        uint256 vaultSharesProceeds = closeLong(
            bob,
            maturityTime,
            longAmount,
            false
        );
        uint256 baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

        // Bob should receive approximately as many vault shares as he paid
        // since no time as passed and the fees are zero.
        assertApproxEqAbs(vaultSharesProceeds, _vaultSharesPaid, 1e5);

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

    function test_round_trip_long_maturity(
        uint256 _vaultSharesPaid,
        uint256 _variableRate
    ) external {
        // Bob opens a long with base.
        _vaultSharesPaid = hyperdrive.convertToShares(
            _vaultSharesPaid.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                hyperdrive.calculateMaxLong()
            )
        );
        IERC20(hyperdrive.vaultSharesToken()).approve(
            address(hyperdrive),
            _vaultSharesPaid
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            _vaultSharesPaid,
            false
        );

        // Advance the time and accrue a large amount of interest.
        _variableRate = _variableRate.normalizeToRange(0, 1000e18);
        advanceTime(POSITION_DURATION, int256(_variableRate));

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with vault share as the target asset.
        uint256 vaultSharesProceeds = closeLong(
            bob,
            maturityTime,
            longAmount,
            false
        );
        uint256 baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

        // Bob should receive almost exactly his bond amount.
        assertLe(baseProceeds, longAmount);
        assertApproxEqAbs(baseProceeds, longAmount, 1e5);

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

    function test_round_trip_short_instantaneous(
        uint256 _shortAmount
    ) external {
        // Bob opens a short with vault shares.
        _shortAmount = _shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        IERC20(hyperdrive.vaultSharesToken()).approve(
            address(hyperdrive),
            _shortAmount
        );
        (uint256 maturityTime, uint256 vaultSharesPaid) = openShort(
            bob,
            _shortAmount,
            false
        );

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
            _shortAmount,
            false
        );
        uint256 baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

        // Bob should receive approximately as many vault shares as he paid
        // since no time as passed and the fees are zero.
        assertApproxEqAbs(vaultSharesProceeds, vaultSharesPaid, 1e9);

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

    function test_round_trip_short_maturity(
        uint256 _shortAmount,
        uint256 _variableRate
    ) external {
        // Bob opens a short with vault shares.
        _shortAmount = _shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        IERC20(hyperdrive.vaultSharesToken()).approve(
            address(hyperdrive),
            _shortAmount
        );
        (uint256 maturityTime, ) = openShort(bob, _shortAmount, false);

        // The term passes and some interest accrues.
        _variableRate = _variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, int256(_variableRate));

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
            _shortAmount,
            false
        );
        uint256 baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

        // Bob should receive almost exactly the interest that accrued on the
        // bonds that were shorted.
        assertApproxEqAbs(
            baseProceeds,
            _shortAmount.mulDown(_variableRate),
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

    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Get the latest round ID and answer. We'll overwrite this round ID
        // with the updated answer.
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,

        ) = CHAINLINK_AGGREGATOR_PROXY.latestRoundData();

        // Accrue interest in the Chainlink wstETH market. We do this by
        // overwriting the latest round's answer.
        answer = variableRate >= 0
            ? answer + int256(uint256(answer).mulDown(uint256(variableRate)))
            : answer - int256(uint256(answer).mulDown(uint256(-variableRate)));
        bytes32 latestRoundLocation = keccak256(
            abi.encode(uint32(roundId), 44)
        );
        vm.store(
            CHAINLINK_AGGREGATOR,
            latestRoundLocation,
            bytes32((updatedAt << 192) | uint256(answer))
        );
    }
}
