// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { Id, IMorpho, Market, MarketParams } from "morpho-blue/src/interfaces/IMorpho.sol";
import { MarketParamsLib } from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { MorphoBalancesLib } from "morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { MorphoBlueHyperdriveCoreDeployer } from "../../../contracts/src/deployers/morpho-blue/MorphoBlueHyperdriveCoreDeployer.sol";
import { MorphoBlueHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/morpho-blue/MorphoBlueHyperdriveDeployerCoordinator.sol";
import { MorphoBlueTarget0Deployer } from "../../../contracts/src/deployers/morpho-blue/MorphoBlueTarget0Deployer.sol";
import { MorphoBlueTarget1Deployer } from "../../../contracts/src/deployers/morpho-blue/MorphoBlueTarget1Deployer.sol";
import { MorphoBlueTarget2Deployer } from "../../../contracts/src/deployers/morpho-blue/MorphoBlueTarget2Deployer.sol";
import { MorphoBlueTarget3Deployer } from "../../../contracts/src/deployers/morpho-blue/MorphoBlueTarget3Deployer.sol";
import { MorphoBlueTarget4Deployer } from "../../../contracts/src/deployers/morpho-blue/MorphoBlueTarget4Deployer.sol";
import { HyperdriveFactory } from "../../../contracts/src/factory/HyperdriveFactory.sol";
import { MorphoBlueConversions } from "../../../contracts/src/instances/morpho-blue/MorphoBlueConversions.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IMorphoBlueHyperdrive } from "../../../contracts/src/interfaces/IMorphoBlueHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { ETH } from "../../../contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { ERC20ForwarderFactory } from "../../../contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract MorphoBlueHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;
    using Lib for *;
    using stdStorage for StdStorage;

    // The mainnet Morpho Blue pool.
    IMorpho internal constant MORPHO =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    // The ID of the SUSDe market.
    bytes32 internal constant MARKET_ID =
        bytes32(
            0x39d11026eae1c6ec02aa4c0910778664089cdd97c3fd23f68f7cd05e2e95af48
        );

    // The address of the loan token. This is just the DAI token.
    address internal constant LOAN_TOKEN =
        address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    // The address of the collateral token. This is just the SUSDe token.
    address internal constant COLLATERAL_TOKEN =
        address(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);

    // The address of the oracle.
    address internal constant ORACLE =
        address(0x5D916980D5Ae1737a8330Bf24dF812b2911Aae25);

    // The address of the interest rate model.
    address internal constant IRM =
        address(0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC);

    // The liquidation loan to value ratio of the SUSDe market.
    uint256 internal constant LLTV = 860000000000000000;

    // Whale accounts.
    address internal LOAN_TOKEN_WHALE =
        address(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    address[] internal baseTokenWhaleAccounts = [LOAN_TOKEN_WHALE];

    // The configuration for the instance testing suite.
    InstanceTestConfig internal __testConfig =
        InstanceTestConfig({
            name: "Hyperdrive",
            kind: "MorphoBlueHyperdrive",
            baseTokenWhaleAccounts: baseTokenWhaleAccounts,
            vaultSharesTokenWhaleAccounts: new address[](0),
            baseToken: IERC20(LOAN_TOKEN),
            vaultSharesToken: IERC20(address(0)),
            // NOTE: The share tolerance is quite high for this integration
            // because the vault share price is ~1e12, which means that just
            // multiplying or dividing by the vault is an imprecise way of
            // converting between base and vault shares. We included more
            // assertions than normal to the round trip tests to verify that
            // the calculations satisfy our expectations of accuracy.
            shareTolerance: 1e15,
            minTransactionAmount: 1e15,
            positionDuration: POSITION_DURATION,
            enableBaseDeposits: true,
            enableShareDeposits: false,
            enableBaseWithdraws: true,
            enableShareWithdraws: false,
            baseWithdrawError: abi.encodeWithSelector(
                IHyperdrive.UnsupportedToken.selector
            ),
            minimumShareReserves: MINIMUM_SHARE_RESERVES
        });

    /// @dev Instantiates the instance testing suite with the configuration.
    constructor() InstanceTest(__testConfig) {}

    /// @dev Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(20_276_503) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy Hyperdrive instances.
    /// @return The extra data.
    function getExtraData() internal pure override returns (bytes memory) {
        return
            abi.encode(
                IMorphoBlueHyperdrive.MorphoBlueParams({
                    morpho: MORPHO,
                    collateralToken: COLLATERAL_TOKEN,
                    oracle: ORACLE,
                    irm: IRM,
                    lltv: LLTV
                })
            );
    }

    /// @dev Converts base amount to the equivalent about in shares.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        return
            MorphoBlueConversions.convertToShares(
                MORPHO,
                IERC20(LOAN_TOKEN),
                COLLATERAL_TOKEN,
                ORACLE,
                IRM,
                LLTV,
                baseAmount
            );
    }

    /// @dev Converts share amount to the equivalent amount in base.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        return
            MorphoBlueConversions.convertToBase(
                MORPHO,
                IERC20(LOAN_TOKEN),
                COLLATERAL_TOKEN,
                ORACLE,
                IRM,
                LLTV,
                shareAmount
            );
    }

    /// @dev Deploys the Morpho Blue deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new MorphoBlueHyperdriveDeployerCoordinator(
                    string.concat(__testConfig.name, "DeployerCoordinator"),
                    _factory,
                    address(new MorphoBlueHyperdriveCoreDeployer()),
                    address(new MorphoBlueTarget0Deployer()),
                    address(new MorphoBlueTarget1Deployer()),
                    address(new MorphoBlueTarget2Deployer()),
                    address(new MorphoBlueTarget3Deployer()),
                    address(new MorphoBlueTarget4Deployer())
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    function getSupply() internal view override returns (uint256, uint256) {
        (uint256 totalSupplyAssets, uint256 totalSupplyShares, , ) = MORPHO
            .expectedMarketBalances(
                MarketParams({
                    loanToken: LOAN_TOKEN,
                    collateralToken: COLLATERAL_TOKEN,
                    oracle: ORACLE,
                    irm: IRM,
                    lltv: LLTV
                })
            );
        return (totalSupplyAssets, totalSupplyShares);
    }

    /// @dev Fetches the token balance information of an account.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (
            IERC20(LOAN_TOKEN).balanceOf(account),
            MORPHO
                .position(
                    MarketParams({
                        loanToken: LOAN_TOKEN,
                        collateralToken: COLLATERAL_TOKEN,
                        oracle: ORACLE,
                        irm: IRM,
                        lltv: LLTV
                    }).id(),
                    account
                )
                .supplyShares
        );
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
        // Vault shares deposits are not supported for this instance.
        if (!asBase) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Ensure that the total supply increased by the base paid.
        (uint256 totalSupplyAssets, uint256 totalSupplyShares, , ) = MORPHO
            .expectedMarketBalances(
                MarketParams({
                    loanToken: LOAN_TOKEN,
                    collateralToken: COLLATERAL_TOKEN,
                    oracle: ORACLE,
                    irm: IRM,
                    lltv: LLTV
                })
            );
        assertApproxEqAbs(totalSupplyAssets, totalBaseBefore + amountPaid, 1);
        assertApproxEqAbs(
            totalSupplyShares,
            totalSharesBefore + hyperdrive.convertToShares(amountPaid),
            1
        );

        // Ensure that the ETH balances didn't change.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(bob.balance, traderBalancesBefore.ETHBalance);

        // Ensure that the Hyperdrive instance's base balance doesn't change
        // and that the trader's base balance decreased by the amount paid.
        assertEq(
            IERC20(LOAN_TOKEN).balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.baseBalance
        );
        assertEq(
            IERC20(LOAN_TOKEN).balanceOf(trader),
            traderBalancesBefore.baseBalance - amountPaid
        );

        // Ensure that the shares balances were updated correctly.
        (, uint256 hyperdriveSharesAfter) = getTokenBalances(
            address(hyperdrive)
        );
        (, uint256 traderSharesAfter) = getTokenBalances(address(trader));
        assertApproxEqAbs(
            hyperdriveSharesAfter,
            hyperdriveBalancesBefore.sharesBalance +
                hyperdrive.convertToShares(amountPaid),
            2
        );
        assertEq(traderSharesAfter, traderBalancesBefore.sharesBalance);
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
        // Vault shares withdrawals are not supported for this instance.
        if (!asBase) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Ensure that the total supply decreased by the base proceeds.
        (uint256 totalSupplyAssets, uint256 totalSupplyShares, , ) = MORPHO
            .expectedMarketBalances(
                MarketParams({
                    loanToken: LOAN_TOKEN,
                    collateralToken: COLLATERAL_TOKEN,
                    oracle: ORACLE,
                    irm: IRM,
                    lltv: LLTV
                })
            );
        assertApproxEqAbs(totalSupplyAssets, totalBaseBefore - baseProceeds, 1);
        assertApproxEqAbs(
            totalSupplyShares,
            totalSharesBefore - hyperdrive.convertToShares(baseProceeds),
            1e6
        );

        // Ensure that the ETH balances didn't change.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(bob.balance, traderBalancesBefore.ETHBalance);

        // Ensure that the base balances Hyperdrive base balance doesn't
        // change and that the trader's base balance decreased by the amount
        // paid.
        assertApproxEqAbs(
            IERC20(LOAN_TOKEN).balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.baseBalance,
            1
        );
        assertEq(
            IERC20(LOAN_TOKEN).balanceOf(trader),
            traderBalancesBefore.baseBalance + baseProceeds
        );

        // Ensure that the shares balances were updated correctly.
        (, uint256 hyperdriveSharesAfter) = getTokenBalances(
            address(hyperdrive)
        );
        (, uint256 traderSharesAfter) = getTokenBalances(address(trader));
        assertApproxEqAbs(
            hyperdriveSharesAfter,
            hyperdriveBalancesBefore.sharesBalance -
                hyperdrive.convertToShares(baseProceeds),
            1e6
        );
        assertApproxEqAbs(
            traderSharesAfter,
            traderBalancesBefore.sharesBalance,
            1
        );
    }

    /// Getters ///

    function test_getters() external view {
        assertEq(
            IMorphoBlueHyperdrive(address(hyperdrive)).vault(),
            address(MORPHO)
        );
        assertEq(
            IMorphoBlueHyperdrive(address(hyperdrive)).collateralToken(),
            address(COLLATERAL_TOKEN)
        );
        assertEq(
            IMorphoBlueHyperdrive(address(hyperdrive)).oracle(),
            address(ORACLE)
        );
        assertEq(
            IMorphoBlueHyperdrive(address(hyperdrive)).irm(),
            address(IRM)
        );
        assertEq(IMorphoBlueHyperdrive(address(hyperdrive)).lltv(), LLTV);
        (, uint256 totalShares) = getTokenBalances(address(hyperdrive));
        assertEq(hyperdrive.totalShares(), totalShares);
    }

    /// Price Per Share ///

    function test__pricePerVaultShare(uint256 basePaid) external {
        // Ensure that the share price is the expected value.
        (uint256 totalSupplyAssets, uint256 totalSupplyShares, , ) = MORPHO
            .expectedMarketBalances(
                MarketParams({
                    loanToken: LOAN_TOKEN,
                    collateralToken: COLLATERAL_TOKEN,
                    oracle: ORACLE,
                    irm: IRM,
                    lltv: LLTV
                })
            );
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, totalSupplyAssets.divDown(totalSupplyShares));

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
            __testConfig.shareTolerance
        );
    }

    /// LP ///

    function test_round_trip_lp_instantaneous(uint256 _contribution) external {
        // Bob adds liquidity with base.
        _contribution = _contribution.normalizeToRange(100e18, 100_000e18);
        IERC20(hyperdrive.baseToken()).approve(
            address(hyperdrive),
            _contribution
        );
        uint256 lpShares = addLiquidity(bob, _contribution);

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob removes his liquidity with base as the target asset.
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            bob,
            lpShares
        );
        assertEq(withdrawalShares, 0);

        // Bob should receive approximately as much base as he contributed since
        // no time as passed and the fees are zero.
        assertApproxEqAbs(baseProceeds, _contribution, 1e12);

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            true,
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
        _contribution = _contribution.normalizeToRange(100e18, 100_000e18);
        IERC20(hyperdrive.baseToken()).approve(
            address(hyperdrive),
            _contribution
        );
        uint256 lpShares = addLiquidity(bob, _contribution);

        // Alice opens a large short.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 shortAmount = hyperdrive.calculateMaxShort();
        IERC20(hyperdrive.baseToken()).approve(
            address(hyperdrive),
            shortAmount
        );
        openShort(alice, shortAmount);

        // Bob removes his liquidity with base as the target asset.
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            bob,
            lpShares
        );
        assertGt(withdrawalShares, 0);

        // The term passes and interest accrues.
        _variableRate = _variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, int256(_variableRate));

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
            1e11
        );
    }

    /// Long ///

    function test_open_long_nonpayable() external {
        vm.startPrank(bob);

        // Ensure that sending ETH to `openLong` fails.
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

        // Ensure that sending ETH to `openShort` fails.
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

    function test_round_trip_long_instantaneous(uint256 _basePaid) external {
        // Bob opens a long with base.
        _basePaid = _basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxLong()
        );
        IERC20(hyperdrive.baseToken()).approve(address(hyperdrive), _basePaid);
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, _basePaid);

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with base as the target asset.
        uint256 baseProceeds = closeLong(bob, maturityTime, longAmount);

        // Bob should receive approximately as much base as he paid since no
        // time as passed and the fees are zero.
        assertApproxEqAbs(baseProceeds, _basePaid, 1e9);

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            true,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_round_trip_long_maturity(
        uint256 _basePaid,
        uint256 _variableRate
    ) external {
        // Bob opens a long with base.
        _basePaid = _basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxLong()
        );
        IERC20(hyperdrive.baseToken()).approve(address(hyperdrive), _basePaid);
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, _basePaid);

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

        // Bob closes his long with base as the target asset.
        uint256 baseProceeds = closeLong(bob, maturityTime, longAmount);

        // Bob should receive almost exactly his bond amount.
        assertLe(baseProceeds, longAmount);
        assertApproxEqAbs(baseProceeds, longAmount, 2);

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            true,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// Short ///

    function test_open_short_nonpayable() external {
        vm.startPrank(bob);

        // Ensure that sending ETH to `openLong` fails.
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

        // Ensure that Bob receives a refund when he opens a short with "asBase"
        // set to false and sends ether to the contract.
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
        // Bob opens a short with base.
        _shortAmount = _shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        IERC20(hyperdrive.baseToken()).approve(
            address(hyperdrive),
            _shortAmount
        );
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, _shortAmount);

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with base as the target asset.
        uint256 baseProceeds = closeShort(bob, maturityTime, _shortAmount);

        // Bob should receive approximately as much base as he paid since no
        // time as passed and the fees are zero.
        assertApproxEqAbs(baseProceeds, basePaid, 1e9);

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            true,
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
        // Bob opens a short with base.
        _shortAmount = _shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        IERC20(hyperdrive.baseToken()).approve(
            address(hyperdrive),
            _shortAmount
        );
        (uint256 maturityTime, ) = openShort(bob, _shortAmount);

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

        // Bob closes his long with base as the target asset.
        uint256 baseProceeds = closeShort(bob, maturityTime, _shortAmount);

        // Bob should receive almost exactly the interest that accrued on the
        // bonds that were shorted.
        assertApproxEqAbs(
            baseProceeds,
            _shortAmount.mulDown(_variableRate),
            1e10
        );

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            true,
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

        // Accrue interest in the Morpho market. This amounts to manually
        // updating the total supply assets and the last update time.
        Id marketId = MarketParams({
            loanToken: LOAN_TOKEN,
            collateralToken: COLLATERAL_TOKEN,
            oracle: ORACLE,
            irm: IRM,
            lltv: LLTV
        }).id();
        Market memory market = MORPHO.market(marketId);
        uint256 totalSupplyAssets = variableRate >= 0
            ? market.totalSupplyAssets +
                uint256(market.totalSupplyAssets).mulDown(uint256(variableRate))
            : market.totalSupplyAssets -
                uint256(market.totalSupplyAssets).mulDown(
                    uint256(-variableRate)
                );
        bytes32 marketLocation = keccak256(abi.encode(marketId, 3));
        vm.store(
            address(MORPHO),
            marketLocation,
            bytes32(
                (uint256(market.totalSupplyShares) << 128) | totalSupplyAssets
            )
        );
        vm.store(
            address(MORPHO),
            bytes32(uint256(marketLocation) + 2),
            bytes32((uint256(market.fee) << 128) | uint256(block.timestamp))
        );

        // In order to prevent transfers from failing, we also need to increase
        // the DAI balance of the Morpho vault to match the total assets.
        bytes32 balanceLocation = keccak256(abi.encode(address(MORPHO), 2));
        vm.store(
            address(LOAN_TOKEN),
            balanceLocation,
            bytes32(totalSupplyAssets)
        );
    }
}
