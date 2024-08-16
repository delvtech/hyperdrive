// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract VariableInterestLongTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function test_positive_negative_interest_long_immediate_open_close_fuzz(
        uint256 initialVaultSharePrice,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialVaultSharePrice [0.1,5]
        // variableInterest [-50,50]
        initialVaultSharePrice = initialVaultSharePrice.normalizeToRange(
            .1e18,
            5e18
        );
        variableInterest = variableInterest.normalizeToRange(-.5e18, .5e18);
        immediate_open_close(initialVaultSharePrice, variableInterest);
    }

    function test_positive_interest_long_immediate_open_close() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - positive interest causes the share price to go up
        // - a long is opened and immediately closed
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 variableInterest = 0.05e18;
            immediate_open_close(initialVaultSharePrice, variableInterest);
        }

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long is opened and immediately closed
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            immediate_open_close(initialVaultSharePrice, variableInterest);
        }

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - positive interest causes the share price to go up
        // - a long is opened and immediately closed
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 variableInterest = 0.10e18;
            immediate_open_close(initialVaultSharePrice, variableInterest);
        }
    }

    function test_negative_interest_long_immediate_open_close() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - negative interest causes the share price to go down
        // - a long is opened and immediately closed
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 variableInterest = -0.05e18;
            immediate_open_close(initialVaultSharePrice, variableInterest);
        }

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - negative interest causes the share price to go to < 1
        // - a long is opened and immediately closed
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = -0.05e18;
            immediate_open_close(initialVaultSharePrice, variableInterest);
        }

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - negative interest causes the share price to go to further < 1
        // - a long is opened and immediately closed
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 variableInterest = -0.05e18;
            immediate_open_close(initialVaultSharePrice, variableInterest);
        }
    }

    function immediate_open_close(
        uint256 initialVaultSharePrice,
        int256 variableInterest
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialVaultSharePrice, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        // Open a long position.
        uint256 basePaid = 10_000e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Immediately close the long.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // It shouldn't be profitable to open and close a long position with negative interest.
        assertGe(basePaid, baseProceeds);
        assertApproxEqAbs(baseProceeds, basePaid, 1e12);
    }

    function test_positive_negative_interest_long_full_term_fuzz(
        uint256 initialVaultSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialVaultSharePrice [0.1,5]
        // preTradeVariableInterest [-50,50]
        // variableInterest [-50,50]
        initialVaultSharePrice = initialVaultSharePrice.normalizeToRange(
            .1e18,
            5e18
        );
        preTradeVariableInterest = preTradeVariableInterest.normalizeToRange(
            -0.5e18,
            0.5e18
        );
        variableInterest = variableInterest.normalizeToRange(-0.5e18, 0.5e18);
        full_term(
            initialVaultSharePrice,
            preTradeVariableInterest,
            variableInterest
        );
    }

    function test_positive_interest_long_full_term() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - positive interest causes the share price to go up
        // - a long is opened
        // - positive interest accrues over the full term
        // - long is closed
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 preTradeVariableInterest = 0.10e18;
            int256 variableInterest = 0.05e18;
            full_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go up
        // - a long is opened
        // - positive interest accrues over the full term
        // - long is closed
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 preTradeVariableInterest = 0.10e18;
            int256 variableInterest = 0.05e18;
            full_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - positive interest causes the share price to go up
        // - a long is opened
        // - positive interest accrues over the full term
        // - long is closed
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 preTradeVariableInterest = 0.10e18;
            int256 variableInterest = 0.05e18;
            full_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }
    }

    function test_negative_interest_long_full_term() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the full term
        // - long is closed
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            full_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the full term
        // - long is closed
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            full_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - negative interest causes the share price to go further down
        // - a long is opened
        // - negative interest accrues over the full term
        // - long is closed
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            full_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }
    }

    function full_term(
        uint256 initialVaultSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialVaultSharePrice, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue negative interest
        advanceTime(POSITION_DURATION, preTradeVariableInterest);
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        uint256 openVaultSharePrice = poolInfo.vaultSharePrice;

        // Open a long position.
        uint256 basePaid = 10_000e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Full term passes
        advanceTime(POSITION_DURATION, variableInterest);
        poolInfo = hyperdrive.getPoolInfo();
        uint256 closeVaultSharePrice = poolInfo.vaultSharePrice;

        // Estimate the proceeds
        uint256 estimatedProceeds = estimateLongProceeds(
            bondAmount,
            HyperdriveUtils.calculateTimeRemaining(hyperdrive, maturityTime),
            openVaultSharePrice,
            closeVaultSharePrice
        );

        // Close the long
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);
        assertApproxEqAbs(baseProceeds, estimatedProceeds, 20);
    }

    function test_positive_negative_interest_long_half_term_fuzz(
        uint256 initialVaultSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialVaultSharePrice [0.1,5]
        // preTradeVariableInterest [-50,50]
        // variableInterest [-50,50]
        initialVaultSharePrice = initialVaultSharePrice.normalizeToRange(
            .1e18,
            5e18
        );
        preTradeVariableInterest = preTradeVariableInterest.normalizeToRange(
            -0.5e18,
            0.5e18
        );
        variableInterest = variableInterest.normalizeToRange(-0.5e18, 0.5e18);
        half_term(
            initialVaultSharePrice,
            preTradeVariableInterest,
            variableInterest
        );
    }

    function test_positive_interest_long_half_term() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - positive interest causes the share price to go up
        // - a long is opened
        // - positive interest accrues over half term
        // - long is closed
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 preTradeVariableInterest = 0.10e18;
            int256 variableInterest = 0.05e18;
            half_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go up
        // - a long is opened
        // - positive interest accrues over half term
        // - long is closed
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 preTradeVariableInterest = 0.10e18;
            int256 variableInterest = 0.05e18;
            half_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - positive interest causes the share price to go up
        // - a long is opened
        // - positive interest accrues over half term
        // - long is closed
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 preTradeVariableInterest = 0.10e18;
            int256 variableInterest = 0.05e18;
            half_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }
    }

    function test_negative_interest_long_half_term() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over half term
        // - long is closed
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            half_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over half term
        // - long is closed
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            half_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - negative interest causes the share price to go further down
        // - a long is opened
        // - negative interest accrues over half term
        // - long is closed
        {
            uint256 initialVaultSharePrice = 0.90e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            half_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }
    }

    function half_term(
        uint256 initialVaultSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialVaultSharePrice, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue negative interest
        advanceTime(POSITION_DURATION, preTradeVariableInterest);
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        uint256 openVaultSharePrice = poolInfo.vaultSharePrice;

        // Open a long position.
        uint256 basePaid = 10_000e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // half term passes
        advanceTime(POSITION_DURATION / 2, variableInterest);

        // Estimate the proceeds.
        poolInfo = hyperdrive.getPoolInfo();
        uint256 closeVaultSharePrice = poolInfo.vaultSharePrice;
        uint256 estimatedProceeds = estimateLongProceeds(
            bondAmount,
            HyperdriveUtils.calculateTimeRemaining(hyperdrive, maturityTime),
            openVaultSharePrice,
            closeVaultSharePrice
        );

        // Close the long.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);
        assertApproxEqAbs(baseProceeds, estimatedProceeds, 20);
    }
}
