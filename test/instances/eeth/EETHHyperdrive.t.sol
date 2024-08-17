// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ILiquidityPool } from "../../../contracts/src/interfaces/ILiquidityPool.sol";
import { IEETH } from "../../../contracts/src/interfaces/IEETH.sol";
import { EETHHyperdriveCoreDeployer } from "../../../contracts/src/deployers/eeth/EETHHyperdriveCoreDeployer.sol";
import { EETHHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/eeth/EETHHyperdriveDeployerCoordinator.sol";
import { EETHTarget0Deployer } from "../../../contracts/src/deployers/eeth/EETHTarget0Deployer.sol";
import { EETHTarget1Deployer } from "../../../contracts/src/deployers/eeth/EETHTarget1Deployer.sol";
import { EETHTarget2Deployer } from "../../../contracts/src/deployers/eeth/EETHTarget2Deployer.sol";
import { EETHTarget3Deployer } from "../../../contracts/src/deployers/eeth/EETHTarget3Deployer.sol";
import { EETHTarget4Deployer } from "../../../contracts/src/deployers/eeth/EETHTarget4Deployer.sol";
import { HyperdriveFactory } from "../../../contracts/src/factory/HyperdriveFactory.sol";
import { EETHConversions } from "../../../contracts/src/instances/eeth/EETHConversions.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IEETHHyperdrive } from "../../../contracts/src/interfaces/IEETHHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { ETH } from "../../../contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { ERC20ForwarderFactory } from "../../../contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract EETHHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    // The mainnet liquidity pool.
    ILiquidityPool internal constant POOL =
        ILiquidityPool(0x308861A430be4cce5502d0A12724771Fc6DaF216);

    // The mainnet EETH token.
    IEETH internal constant EETH =
        IEETH(0x35fA164735182de50811E8e2E824cFb9B6118ac2);

    // The mainnet address that has the ability to call the rebase function.
    address internal constant MEMBERSHIP_MANAGER =
        0x3d320286E014C3e1ce99Af6d6B00f0C1D63E3000;

    // Whale accounts.
    address internal EETH_TOKEN_WHALE =
        0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address[] internal EETHTokenWhaleAccounts = [EETH_TOKEN_WHALE];

    // The configuration for the Instance testing suite.
    InstanceTestConfig internal __testConfig =
        InstanceTestConfig({
            name: "Hyperdrive",
            kind: "EETHHyperdrive",
            decimals: 18,
            baseTokenWhaleAccounts: new address[](0),
            vaultSharesTokenWhaleAccounts: EETHTokenWhaleAccounts,
            baseToken: IERC20(ETH),
            vaultSharesToken: IERC20(address(EETH)),
            shareTolerance: 1e5,
            minimumShareReserves: 1e15,
            minimumTransactionAmount: 1e15,
            positionDuration: POSITION_DURATION,
            enableBaseDeposits: true,
            enableShareDeposits: true,
            enableBaseWithdraws: false,
            enableShareWithdraws: true,
            baseWithdrawError: abi.encodeWithSelector(
                IHyperdrive.UnsupportedToken.selector
            ),
            isRebasing: true,
            fees: IHyperdrive.Fees({
                curve: 0,
                flat: 0,
                governanceLP: 0,
                governanceZombie: 0
            })
        });

    /// @dev Instantiates the instance testing suite with the configuration.
    constructor() InstanceTest(__testConfig) {}

    /// @dev Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(20_362_343) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy Hyperdrive instances.
    /// @return The extra data.
    function getExtraData() internal pure override returns (bytes memory) {
        return new bytes(0);
    }

    /// @dev Converts base amount to the equivalent amount in shares.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        return
            EETHConversions.convertToShares(
                POOL,
                IERC20(address(EETH)),
                baseAmount
            );
    }

    /// @dev Converts share amount to the equivalent amount in base.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        return
            EETHConversions.convertToBase(
                POOL,
                IERC20(address(EETH)),
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
                new EETHHyperdriveDeployerCoordinator(
                    string.concat(__testConfig.name, "DeployerCoordinator"),
                    _factory,
                    address(new EETHHyperdriveCoreDeployer(POOL)),
                    address(new EETHTarget0Deployer(POOL)),
                    address(new EETHTarget1Deployer(POOL)),
                    address(new EETHTarget2Deployer(POOL)),
                    address(new EETHTarget3Deployer(POOL)),
                    address(new EETHTarget4Deployer(POOL)),
                    POOL
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    function getSupply() internal view override returns (uint256, uint256) {
        return (POOL.getTotalPooledEther(), EETH.totalShares());
    }

    /// @dev Fetches the token balance information of an account.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (EETH.balanceOf(account), EETH.shares(account));
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
        if (asBase) {
            // Ensure that the amount of pooled ether increased by the base paid.
            assertEq(POOL.getTotalPooledEther(), totalBaseBefore + amountPaid);

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(bob.balance, traderBalancesBefore.ETHBalance - amountPaid);

            // Ensure that the EETH balances were updated correctly.
            assertApproxEqAbs(
                EETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.baseBalance + amountPaid,
                5
            );
            assertEq(EETH.balanceOf(trader), traderBalancesBefore.baseBalance);

            // Ensure that the EETH shares were updated correctly.
            uint256 expectedShares = convertToShares(amountPaid);
            assertEq(EETH.totalShares(), totalSharesBefore + expectedShares);
            assertEq(
                EETH.shares(address(hyperdrive)),
                hyperdriveBalancesBefore.sharesBalance + expectedShares
            );
            assertEq(EETH.shares(bob), traderBalancesBefore.sharesBalance);
        } else {
            // Ensure that the amount of pooled ether stays the same.
            assertEq(POOL.getTotalPooledEther(), totalBaseBefore);

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(trader.balance, traderBalancesBefore.ETHBalance);

            // Ensure that the EETH balances were updated correctly.
            assertApproxEqAbs(
                EETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.baseBalance + amountPaid,
                3
            );
            assertApproxEqAbs(
                EETH.balanceOf(trader),
                traderBalancesBefore.baseBalance - amountPaid,
                3
            );

            // Ensure that the EETH shares were updated correctly.
            uint256 expectedShares = convertToShares(amountPaid);
            assertEq(EETH.totalShares(), totalSharesBefore);
            assertApproxEqAbs(
                EETH.shares(address(hyperdrive)),
                hyperdriveBalancesBefore.sharesBalance + expectedShares,
                3
            );
            assertApproxEqAbs(
                EETH.shares(trader),
                traderBalancesBefore.sharesBalance - expectedShares,
                3
            );
        }
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
        // Base withdraws are not supported for this instance.
        if (asBase) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Ensure that the total pooled ether and shares stays the same.
        assertEq(POOL.getTotalPooledEther(), totalBaseBefore);
        assertApproxEqAbs(EETH.totalShares(), totalSharesBefore, 1);

        // Ensure that the ETH balances were updated correctly.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(trader.balance, traderBalancesBefore.ETHBalance);

        // Ensure that the EETH balances were updated correctly.
        assertApproxEqAbs(
            EETH.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.baseBalance - baseProceeds,
            1e4
        );
        assertApproxEqAbs(
            EETH.balanceOf(trader),
            traderBalancesBefore.baseBalance + baseProceeds,
            1e4
        );

        // Ensure that the EETH shares were updated correctly.
        uint256 expectedShares = convertToShares(baseProceeds);
        assertApproxEqAbs(
            EETH.shares(address(hyperdrive)),
            hyperdriveBalancesBefore.sharesBalance - expectedShares,
            2
        );
        assertApproxEqAbs(
            EETH.shares(trader),
            traderBalancesBefore.sharesBalance + expectedShares,
            2
        );
    }

    // /// Price Per Share ///

    function test__pricePerVaultShare(uint256 basePaid) external {
        // Ensure that the share price is the expected value.
        (uint256 totalSupplyAssets, uint256 totalSupplyShares) = getSupply();
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

    function test_round_trip_lp_instantaneous(uint256 contribution) external {
        // Bob adds liquidity with base.
        contribution = contribution.normalizeToRange(100e18, 100_000e18);
        uint256 lpShares = addLiquidity(bob, contribution);

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
            lpShares,
            false
        );
        baseProceeds = convertToBase(baseProceeds);
        assertEq(withdrawalShares, 0);

        // Bob should receive approximately as much base as he contributed since
        // no time as passed and the fees are zero.
        assertApproxEqAbs(baseProceeds, contribution, 1e5);

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
        uint256 contribution,
        uint256 variableRate
    ) external {
        // Bob adds liquidity with base.
        contribution = contribution.normalizeToRange(100e18, 100_000e18);
        uint256 lpShares = addLiquidity(bob, contribution);

        // Alice opens a large short.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 shortAmount = hyperdrive.calculateMaxShort();
        openShort(alice, shortAmount);

        // Bob removes his liquidity with base as the target asset.
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            bob,
            lpShares,
            false
        );
        assertGt(withdrawalShares, 0);

        // The term passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, int256(variableRate));

        // Bob should be able to redeem all of his withdrawal shares for
        // approximately the LP share price.
        uint256 lpSharePrice = hyperdrive.getPoolInfo().lpSharePrice;
        uint256 withdrawalSharesRedeemed;
        (baseProceeds, withdrawalSharesRedeemed) = redeemWithdrawalShares(
            bob,
            withdrawalShares,
            false
        );
        baseProceeds = convertToBase(baseProceeds);
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

    function test_round_trip_long_instantaneous(uint256 basePaid) external {
        // Bob opens a long with base.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxLong()
        );
        (uint256 maturityTime, uint256 bondAmount) = hyperdrive.openLong{
            value: basePaid
        }(
            basePaid,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
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

        // Bob closes his long.
        uint256 baseProceeds = convertToBase(
            closeLong(bob, maturityTime, bondAmount, false)
        );

        // Bob should receive approximately as much base as he paid since no
        // time as passed and the fees are zero.
        assertApproxEqAbs(baseProceeds, basePaid, 1e5);

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
        uint256 basePaid,
        uint256 variableRate
    ) external {
        // Bob opens a long with base.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxLong()
        );
        (uint256 maturityTime, uint256 bondAmount) = hyperdrive.openLong{
            value: basePaid
        }(
            basePaid,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Advance the time and accrue a large amount of interest.
        variableRate = variableRate.normalizeToRange(0, 1000e18);
        advanceTime(POSITION_DURATION, int256(variableRate));

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long.
        uint256 baseProceeds = convertToBase(
            closeLong(bob, maturityTime, bondAmount, false)
        );

        // Bob should receive almost exactly his bond amount.
        assertApproxEqAbs(baseProceeds, bondAmount, 1e4);

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

    function test_round_trip_short_instantaneous(uint256 shortAmount) external {
        // Bob opens a short with base.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

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
        uint256 baseProceeds = convertToBase(
            closeShort(bob, maturityTime, shortAmount, false)
        );

        // Bob should receive approximately as much base as he paid since no
        // time as passed and the fees are zero.
        assertApproxEqAbs(baseProceeds, basePaid, 1e4);

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
        uint256 shortAmount,
        uint256 variableRate
    ) external {
        // Bob opens a short with base.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // The term passes and some interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, int256(variableRate));

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
        uint256 baseProceeds = convertToBase(
            closeShort(bob, maturityTime, shortAmount, false)
        );

        // Bob should receive almost exactly the interest that accrued on the
        // bonds that were shorted.
        assertApproxEqAbs(
            baseProceeds,
            shortAmount.mulDown(uint256(variableRate)),
            1e4
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

    /// Getters ///

    function test_getters() external view {
        assertEq(
            IEETHHyperdrive(address(hyperdrive)).liquidityPool(),
            address(POOL)
        );
    }

    /// Helpers ///

    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in Etherfi. Since the share price is given by
        // `getTotalPooledEther() / getTotalShares()`, we can simulate the
        // accrual of interest by multiplying the total pooled ether by the
        // variable rate plus one.
        uint256 etherToAdd = POOL.getTotalPooledEther().mulDown(
            uint256(variableRate)
        );
        vm.startPrank(MEMBERSHIP_MANAGER);
        POOL.rebase(int128(int256(etherToAdd)));
        vm.deal(address(POOL), etherToAdd);
    }
}
