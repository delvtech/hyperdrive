// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import "forge-std/console2.sol";

contract LPFairnessTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_lp_fairness_short() external {
        // limit the fuzz testing to apy's less than 100%
        //vm.assume(param < 1e18);
        // variable interest rate earned by the pool
        int256 apy = 0.10e18;//int256(param);
        // fixed interest rate the pool pays the longs
        uint256 apr = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, apr, initialLiquidity);
    {
        // Store the pool APR before Celine opens a short.
        uint256 aprBefore = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );
        console2.log("aprBefore", aprBefore);
    }
        // Celine opens a short.
        uint256 bondsShorted = 5_000_000e18;
        console2.log("bondsShorted", bondsShorted);
        (, uint256 baseSpent) = openShort(celine, bondsShorted);
        console2.log("baseSpent", baseSpent);
    {
        // Store the pool APR after Celine opens a short.
        uint256 aprAfter = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);
        console2.log("aprAfter", aprAfter);
    }
        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // The term passes.
        advanceTime(POSITION_DURATION,apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue, int256 poolInterest) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + contribution + baseSpent,
            apy,
            POSITION_DURATION
        );
        console2.log("poolInterest", poolInterest);
        console2.log("poolValue", poolValue);

        // Calculate the value of the pool after interest is accrued.
        (, int256 shortInterest) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted,
            apy,
            POSITION_DURATION
        );

        // calculate the portion of the pool's value (after interest) that bob contributed.
        uint256 contributionWithInterest = uint256(poolValue - baseSpent).mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));
        console2.log("contributionWithInterest", contributionWithInterest);

        // calculate the portion of the fixed interest that bob earned
        uint256 fixedInterestEarned = baseSpent.mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));
        console2.log("fixedInterestEarned", fixedInterestEarned);

        // calculate the portion of the variable interest that bob owes
        uint256 variableInterestOwed = uint256(shortInterest).mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));
        console2.log("variableInterestOwed", variableInterestOwed);

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = contributionWithInterest + fixedInterestEarned - variableInterestOwed;
        console2.log("expectedWithdrawalProceeds", expectedWithdrawalProceeds);

        // Bob removes liquidity
        uint256 withdrawalProceeds = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1 wei);
    }

    function test_lp_fairness_long(uint256 param) external {
        // limit the fuzz testing to apy's less than 100%
        vm.assume(param < 1e18);
        // variable interest rate earned by the pool
        int256 apy = int256(param);
        // fixed interest rate the pool pays the longs
        uint256 apr = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, apr, initialLiquidity);

        // Store the pool APR before Celine opens a long.
        uint256 aprBeforeLong = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        console2.log("aprBeforeLong", aprBeforeLong);

        // Celine opens a long.
        uint256 baseSpent = 5_100_000e18;
        console2.log("baseSpent", baseSpent);
        (, uint256 bondsPurchased) = openLong(celine, baseSpent);
        console2.log("bondsPurchased", bondsPurchased);


        // Store the pool APR after Celine opens a short.
        uint256 aprAfterLong = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);

        console2.log("aprAfterLong", aprAfterLong);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // The term passes.
        advanceTime(POSITION_DURATION,apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + contribution + baseSpent,
            apy,
            POSITION_DURATION
        );
        console2.log("poolValue", poolValue);
        // calculate the portion of the pool's value (after interest) that bob contributed.
        uint256 contributionWithInterest = (poolValue - baseSpent).mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));
        console2.log("contributionWithInterest", contributionWithInterest);
        // calculate the portion of the fixed interest that bob owes
        uint256 percentLongProceedsOwed = (bondsPurchased - baseSpent).mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));
        console2.log("percentLongProceedsOwed", percentLongProceedsOwed);
        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = contributionWithInterest - percentLongProceedsOwed;
        console2.log("expectedWithdrawalProceeds", expectedWithdrawalProceeds);

        // Ensure that if the new LP withdraws, they get their money back.
        uint256 withdrawalProceeds = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1 wei);
    }

    function test_lp_fairness_long_multiple_trades() external {
        // limit the fuzz testing to apy's less than 100%
        //vm.assume(param < 1e18);
        // variable interest rate earned by the pool
        int256 apy = 0.10e18; //int256(param);
        // fixed interest rate the pool pays the longs
        uint256 apr = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, apr, initialLiquidity);
{
        // Store the pool APR before Celine opens a long.
        uint256 aprBeforeLong = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );
        console2.log("aprBeforeLong", aprBeforeLong);
}
        // Celine opens a long.
        uint256 baseSpent = 1_000_000e18;
        console2.log("baseSpent", baseSpent);
        (, uint256 bondsPurchased) = openLong(celine, baseSpent);
        console2.log("bondsPurchased", bondsPurchased);

{
        // Store the pool APR after Celine opens a short.
        uint256 aprAfterLong = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);
        console2.log("aprAfterLong", aprAfterLong);
}
        // 1/2 the term passes.
        advanceTime(POSITION_DURATION/2,apy);
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + baseSpent,
            apy,
            POSITION_DURATION/2
        );

        // Celine opens another long.
        uint256 baseSpent2 = 2_000_000e18;
        console2.log("baseSpent2", baseSpent2);
        (, uint256 bondsPurchased2) = openLong(celine, baseSpent2);
        console2.log("bondsPurchased2", bondsPurchased2);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // 1/2 the term passes.
        advanceTime(POSITION_DURATION/2,apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue2, ) = HyperdriveUtils.calculateCompoundInterest(
            poolValue + contribution + baseSpent2,
            apy,
            POSITION_DURATION/2
        );
        console2.log("poolValue2", poolValue2);
        // calculate the portion of the pool's value (after interest) that bob contributed.
        uint256 contributionWithInterest = (poolValue2 - baseSpent2 - baseSpent).mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));
        console2.log("contributionWithInterest", contributionWithInterest);
        // calculate the portion of the fixed interest that bob owes
        uint256 percentLongProceedsOwed = (bondsPurchased + bondsPurchased2 - baseSpent2 - baseSpent).mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));
        console2.log("percentLongProceedsOwed", percentLongProceedsOwed);
        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = contributionWithInterest - percentLongProceedsOwed;
        console2.log("expectedWithdrawalProceeds", expectedWithdrawalProceeds);

        // Ensure that if the new LP withdraws, they get their money back.
        uint256 withdrawalProceeds = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1 wei);
    }
}

