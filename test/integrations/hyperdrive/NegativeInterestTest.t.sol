// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";

// TODO: We need to test several cases for long negative interest.
//
// - [ ] Negative interest leading to haircut.
// - [ ] Negative interest leading to partial haircut.
// - [ ] Positive interest accrual, then long, then negative interest.
// - [ ] Long, negative interest, then positive interest after close.
// - [ ] Extreme inputs
//
// Ultimately, we'll want to test these cases with withdraw shares as well
// as this will complicate the issue.
contract NegativeInterestTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_negative_interest_short_complete_loss(
        int64 preTradingVariableRate,
        int64 postTradingApr
    ) external {
        // Initialize the market.
        uint256 apr = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Interest accrues for a term.
        vm.assume(
            preTradingVariableRate >= -0.9e18 && preTradingVariableRate <= 1e18
        );
        advanceTime(POSITION_DURATION, preTradingVariableRate);

        // Bob opens a short.
        uint256 shortAmount = 10_000e18;
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // A small amount of negative interest accrues over the term.
        advanceTime(POSITION_DURATION, -0.01e18);

        // A checkpoint is created to lock in the close price.
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // Interest accrues for a term.
        vm.assume(postTradingApr >= -1e18 && postTradingApr <= 1e18);
        advanceTime(POSITION_DURATION, postTradingApr);

        // Bob closes the short. He should receive nothing on account of the
        // negative interest.
        uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount);
        assertEq(baseProceeds, 0);
    }

    function test_negative_interest_short_trading_profits(
        int64 preTradingVariableRate
    ) external {
        // Initialize the market with a very low APR.
        uint256 apr = 0.01e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Interest accrues for a term.
        vm.assume(
            preTradingVariableRate >= -0.5e18 && preTradingVariableRate <= 1e18
        );

        advanceTime(POSITION_DURATION, preTradingVariableRate);

        // Bob opens a short.
        uint256 shortAmount = 10_000e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Celine opens a large short.
        uint256 longAmount = 300_000_000e18;
        openShort(celine, longAmount);

        // A small amount of negative interest accrues over the term.
        uint256 timeDelta = POSITION_DURATION.mulDown(0.5e18);
        int256 variableRate = -0.01e18;
        advanceTime(timeDelta, variableRate);

        // Bob closes the short. He should make a trading profit despite the
        // negative interest.
        uint256 estimatedProceeds = estimateShortProceeds(
            shortAmount,
            variableRate,
            HyperdriveUtils.calculateTimeRemaining(hyperdrive, maturityTime),
            timeDelta
        );
        uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount);
        assertGt(baseProceeds, basePaid);
        assertApproxEqAbs(baseProceeds, estimatedProceeds, 1e5);
    }

    function estimateShortProceeds(
        uint256 shortAmount,
        int256 variableRate,
        uint256 normalizedTimeRemaining,
        uint256 timeElapsed
    ) internal view returns (uint256) {
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory poolConfig = hyperdrive.getPoolConfig();

        (, , uint256 expectedSharePayment) = HyperdriveMath.calculateCloseShort(
            poolInfo.shareReserves,
            poolInfo.bondReserves,
            shortAmount,
            normalizedTimeRemaining,
            poolConfig.timeStretch,
            poolInfo.sharePrice,
            poolConfig.initialSharePrice
        );
        (, int256 expectedInterest) = HyperdriveUtils.calculateCompoundInterest(
            shortAmount,
            variableRate,
            timeElapsed
        );
        return
            uint256(
                int256(
                    shortAmount -
                        poolInfo.sharePrice.mulDown(expectedSharePayment)
                ) + expectedInterest
            );
    }
}
