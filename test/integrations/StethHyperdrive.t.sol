// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { StethHyperdriveDeployer } from "contracts/src/factory/StethHyperdriveDeployer.sol";
import { StethHyperdriveFactory } from "contracts/src/factory/StethHyperdriveFactory.sol";
import { StethHyperdrive } from "contracts/src/instances/StethHyperdrive.sol";
import { StethHyperdriveDataProvider } from "contracts/src/instances/StethHyperdriveDataProvider.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract StethHyperdriveTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    uint256 internal constant FIXED_RATE = 0.05e18;

    // The Lido storage location that tracks buffered ether reserves. We can
    // simulate the accrual of interest by updating this value.
    bytes32 internal constant BUFFERED_ETHER_POSITION =
        keccak256("lido.Lido.bufferedEther");

    ILido internal constant LIDO =
        ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IERC20 internal constant ETH =
        IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    address internal STETH_WHALE = 0x1982b2F5814301d4e9a8b0201555376e62F82428;
    address internal ETH_WHALE = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    function setUp() public override __mainnet_fork(17_376_154) {
        super.setUp();

        // Deploy the StethHyperdrive deployer and factory.
        vm.startPrank(deployer);
        StethHyperdriveDeployer simpleDeployer = new StethHyperdriveDeployer(
            LIDO,
            ETH
        );
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        StethHyperdriveFactory factory = new StethHyperdriveFactory(
            alice,
            simpleDeployer,
            bob,
            bob,
            IHyperdrive.Fees(0, 0, 0),
            defaults,
            LIDO
        );

        // Alice deploys the hyperdrive instance.
        vm.stopPrank();
        vm.startPrank(alice);
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: IERC20(ETH),
            initialSharePrice: LIDO.getTotalPooledEther().divDown(
                LIDO.getTotalShares()
            ),
            positionDuration: POSITION_DURATION,
            checkpointDuration: CHECKPOINT_DURATION,
            timeStretch: HyperdriveUtils.calculateTimeStretch(0.05e18),
            governance: governance,
            feeCollector: feeCollector,
            fees: IHyperdrive.Fees({ curve: 0, flat: 0, governance: 0 }),
            oracleSize: ORACLE_SIZE,
            updateGap: UPDATE_GAP
        });
        uint256 contribution = 10_000e18;
        hyperdrive = factory.deployAndInitialize{ value: contribution }(
            config,
            bytes32(0),
            address(0),
            new bytes32[](0),
            contribution,
            FIXED_RATE
        );

        // Ensure that Alice has the correct amount of LP shares.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            HyperdriveMath.calculateInitialBondReserves(
                contribution.divDown(config.initialSharePrice),
                config.initialSharePrice,
                config.initialSharePrice,
                FIXED_RATE,
                config.positionDuration,
                config.timeStretch
            ) + contribution,
            1e5
        );

        // Fund the test accounts with stETH and ETH.
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = celine;
        fundAccounts(address(hyperdrive), IERC20(LIDO), STETH_WHALE, accounts);
    }

    /// Stuck Tokens ///

    function test__receive() external {
        vm.startPrank(alice);
        vm.expectRevert(Errors.UnexpectedSender.selector);
        (bool success, ) = address(hyperdrive).call{ value: 1 ether }("");

        // HACK(jalextowle): The call succeeds if `vm.expectRevert` is used
        // before the call. If the `vm.expectRevert` is removed, `success` is
        // false as expected.
        assert(success);
    }

    /// Price Per Share ///

    function test__pricePerShare(uint256 basePaid) external {
        // Ensure that the share price is the expected value.
        uint256 totalPooledEther = LIDO.getTotalPooledEther();
        uint256 totalShares = LIDO.getTotalShares();
        uint256 sharePrice = hyperdrive.getPoolInfo().sharePrice;
        assertEq(sharePrice, totalPooledEther.divDown(totalShares));

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of ETH. This will
        // be an approximation since Lido uses `mulDivDown` whereas this test
        // pre-computes the share price.
        basePaid = basePaid.normalizeToRange(
            0.00001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        uint256 hyperdriveSharesBefore = LIDO.sharesOf(address(hyperdrive));
        openLong(bob, basePaid);
        assertApproxEqAbs(
            LIDO.sharesOf(address(hyperdrive)),
            hyperdriveSharesBefore + basePaid.divDown(sharePrice),
            1e4
        );
    }

    /// Long ///

    function test_open_long_with_ETH(uint256 basePaid) external {
        // Get some balance information before the deposit.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a long by depositing ETH.
        basePaid = basePaid.normalizeToRange(
            0.00001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        openLong(bob, basePaid);

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyDeposit(
            bob,
            basePaid,
            true,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_open_long_with_steth(uint256 basePaid) external {
        // Get some balance information before the deposit.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a long by depositing stETH.
        basePaid = basePaid.normalizeToRange(
            0.00001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        openLong(bob, basePaid, false);

        // Ensure that Lido's aggregates and the token balances were updated
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

    function test_close_long_with_ETH(uint256 basePaid) external {
        // Bob opens a long.
        basePaid = basePaid.normalizeToRange(
            0.00001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Bob attempts to close his long with ETH as the target asset. This
        // fails since ETH isn't supported as a withdrawal asset.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.UnsupportedToken.selector);
        hyperdrive.closeLong(maturityTime, longAmount, 0, bob, true);
    }

    function test_close_long_with_steth(uint256 basePaid) external {
        // Bob opens a long.
        basePaid = basePaid.normalizeToRange(
            0.00001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Get some balance information before the withdrawal.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with stETH as the target asset.
        uint256 baseProceeds = closeLong(bob, maturityTime, longAmount, false);

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyStethWithdrawal(
            bob,
            baseProceeds,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// Short ///

    function test_open_short_with_ETH(uint256 shortAmount) external {
        // Get some balance information before the deposit.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a short by depositing ETH.
        shortAmount = shortAmount.normalizeToRange(
            0.00001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (, uint256 basePaid) = openShort(bob, shortAmount);

        // Ensure that the amount of base paid by the short is reasonable.
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            POSITION_DURATION
        );
        assertGt(basePaid, 0);
        assertGe(realizedRate, FIXED_RATE);

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyDeposit(
            bob,
            basePaid,
            true,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_open_short_with_steth(uint256 shortAmount) external {
        // Get some balance information before the deposit.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a short by depositing ETH.
        shortAmount = shortAmount.normalizeToRange(
            0.00001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (, uint256 basePaid) = openShort(bob, shortAmount, false);

        // Ensure that the amount of base paid by the short is reasonable.
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            POSITION_DURATION
        );
        assertGt(basePaid, 0);
        assertGe(realizedRate, FIXED_RATE);

        // Ensure that Lido's aggregates and the token balances were updated
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

    function test_close_short_with_ETH(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        // Bob opens a short.
        shortAmount = shortAmount.normalizeToRange(
            0.00001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // The term passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Bob attempts to close his short with ETH as the target asset. This
        // fails since ETH isn't supported as a withdrawal asset.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.UnsupportedToken.selector);
        hyperdrive.closeShort(maturityTime, shortAmount, 0, bob, true);
    }

    function test_close_short_with_steth(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        // Bob opens a short.
        shortAmount = shortAmount.normalizeToRange(
            0.00001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // The term passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Get some balance information before closing the short.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his short with stETH as the target asset. Bob's proceeds
        // should be the variable interest that accrued on the shorted bonds.
        (, int256 expectedBaseProceeds) = HyperdriveUtils.calculateInterest(
            shortAmount,
            variableRate,
            POSITION_DURATION
        );
        uint256 baseProceeds = closeShort(
            bob,
            maturityTime,
            shortAmount,
            false
        );
        assertApproxEqAbs(baseProceeds, uint256(expectedBaseProceeds), 1e9);

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyStethWithdrawal(
            bob,
            baseProceeds,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// Assertions ///

    function verifyDeposit(
        address trader,
        uint256 basePaid,
        bool asUnderlying,
        uint256 totalPooledEtherBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        if (asUnderlying) {
            // Ensure that the amount of pooled ether increased by the base paid.
            assertEq(
                LIDO.getTotalPooledEther(),
                totalPooledEtherBefore + basePaid
            );

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                ETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(
                ETH.balanceOf(bob),
                traderBalancesBefore.ETHBalance - basePaid
            );

            // Ensure that the stETH balances were updated correctly.
            assertApproxEqAbs(
                LIDO.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.stethBalance + basePaid,
                1
            );
            assertEq(LIDO.balanceOf(trader), traderBalancesBefore.stethBalance);

            // Ensure that the stETH shares were updated correctly.
            uint256 expectedShares = basePaid.mulDivDown(
                totalSharesBefore,
                totalPooledEtherBefore
            );
            assertEq(LIDO.getTotalShares(), totalSharesBefore + expectedShares);
            assertEq(
                LIDO.sharesOf(address(hyperdrive)),
                hyperdriveBalancesBefore.stethShares + expectedShares
            );
            assertEq(LIDO.sharesOf(bob), traderBalancesBefore.stethShares);
        } else {
            // Ensure that the amount of pooled ether stays the same.
            assertEq(LIDO.getTotalPooledEther(), totalPooledEtherBefore);

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                ETH.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(ETH.balanceOf(trader), traderBalancesBefore.ETHBalance);

            // Ensure that the stETH balances were updated correctly.
            assertApproxEqAbs(
                LIDO.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.stethBalance + basePaid,
                1
            );
            assertApproxEqAbs(
                LIDO.balanceOf(trader),
                traderBalancesBefore.stethBalance - basePaid,
                1
            );

            // Ensure that the stETH shares were updated correctly.
            uint256 expectedShares = basePaid.mulDivDown(
                totalSharesBefore,
                totalPooledEtherBefore
            );
            assertEq(LIDO.getTotalShares(), totalSharesBefore);
            assertEq(
                LIDO.sharesOf(address(hyperdrive)),
                hyperdriveBalancesBefore.stethShares + expectedShares
            );
            assertEq(
                LIDO.sharesOf(trader),
                traderBalancesBefore.stethShares - expectedShares
            );
        }
    }

    function verifyStethWithdrawal(
        address trader,
        uint256 baseProceeds,
        uint256 totalPooledEtherBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        // Ensure that the total pooled ether and shares stays the same.
        assertEq(LIDO.getTotalPooledEther(), totalPooledEtherBefore);
        assertApproxEqAbs(LIDO.getTotalShares(), totalSharesBefore, 1);

        // Ensure that the ETH balances were updated correctly.
        assertEq(
            ETH.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(ETH.balanceOf(trader), traderBalancesBefore.ETHBalance);

        // Ensure that the stETH balances were updated correctly.
        assertApproxEqAbs(
            LIDO.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.stethBalance - baseProceeds,
            1
        );
        assertApproxEqAbs(
            LIDO.balanceOf(trader),
            traderBalancesBefore.stethBalance + baseProceeds,
            1
        );

        // Ensure that the stETH shares were updated correctly.
        uint256 expectedShares = baseProceeds.mulDivDown(
            totalSharesBefore,
            totalPooledEtherBefore
        );
        assertApproxEqAbs(
            LIDO.sharesOf(address(hyperdrive)),
            hyperdriveBalancesBefore.stethShares - expectedShares,
            1
        );
        assertApproxEqAbs(
            LIDO.sharesOf(trader),
            traderBalancesBefore.stethShares + expectedShares,
            1
        );
    }

    /// Helpers ///

    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in Lido. Since the share price is given by
        // `getTotalPooledEther() / getTotalShares()`, we can simulate the
        // accrual of interest by multiplying the total pooled ether by the
        // variable rate plus one.
        uint256 bufferedEther = variableRate >= 0
            ? LIDO.getBufferedEther() +
                LIDO.getTotalPooledEther().mulDown(uint256(variableRate))
            : LIDO.getBufferedEther() -
                LIDO.getTotalPooledEther().mulDown(uint256(variableRate));
        vm.store(
            address(LIDO),
            BUFFERED_ETHER_POSITION,
            bytes32(bufferedEther)
        );
    }

    struct AccountBalances {
        uint256 stethShares;
        uint256 stethBalance;
        uint256 ETHBalance;
    }

    function getAccountBalances(
        address account
    ) internal view returns (AccountBalances memory) {
        return
            AccountBalances({
                stethShares: LIDO.sharesOf(account),
                stethBalance: LIDO.balanceOf(account),
                ETHBalance: ETH.balanceOf(account)
            });
    }
}
