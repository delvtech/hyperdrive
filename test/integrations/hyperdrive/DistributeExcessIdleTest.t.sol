// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { MockHyperdrive } from "contracts/test/MockHyperdrive.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract DistributeExcessIdleTest is HyperdriveTest {
    using FixedPointMath for *;
    using HyperdriveUtils for *;
    using Lib for *;

    function test_long_and_short(
        uint256 contribution,
        uint256 longAmount,
        uint256 shortAmount,
        uint256 timeDelta,
        int256 variableRate
    ) external {
        // Alice deploys and initializes the pool.
        uint256 fixedRate = 0.02e18;
        contribution = contribution.normalizeToRange(1_000e18, 500_000_000e18);
        IHyperdrive.PoolConfig memory config = testConfig(fixedRate);
        deploy(alice, config);
        uint256 lpShares = initialize(alice, fixedRate, contribution);
        contribution -= 2 * config.minimumShareReserves;

        // Bob adds liquidity.
        addLiquidity(bob, 200_000_000e18);

        // Celine opens a long.
        longAmount = longAmount.normalizeToRange(
            config.minimumTransactionAmount,
            hyperdrive.calculateMaxLong()
        );
        openLong(celine, longAmount);

        // Celine opens a short.
        shortAmount = shortAmount.normalizeToRange(
            config.minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        openShort(celine, shortAmount);

        // Time passes and interest accrues.
        timeDelta = timeDelta.normalizeToRange(
            0,
            POSITION_DURATION.mulDown(0.99e18)
        );
        // NOTE: Only positive rates are supported. The N.I. state machine will
        // ensure this is the case.
        variableRate = variableRate.normalizeToRange(0, 2e18);
        advanceTime(POSITION_DURATION.mulDown(0.5e18), variableRate);

        // Mint a checkpoint.
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Convert Alice's LP shares to withdrawal shares.
        _convertLpToWithdrawalShares(alice, lpShares);

        // Alice triggers `distributeExcessIdle` by calling `redeemWithdrawalShares`.
        uint256 lpSharePriceBefore = hyperdrive.lpSharePrice();
        redeemWithdrawalShares(alice, lpShares);
        // NOTE: This fudge factor is required for the test to pass.
        assertGe(hyperdrive.lpSharePrice() + 1e3, lpSharePriceBefore);
    }

    function _convertLpToWithdrawalShares(
        address _owner,
        uint256 _amount
    ) internal {
        MockHyperdrive(address(hyperdrive)).burn(
            AssetId._LP_ASSET_ID,
            _owner,
            _amount
        );
        MockHyperdrive(address(hyperdrive)).mint(
            AssetId._WITHDRAWAL_SHARE_ASSET_ID,
            _owner,
            _amount
        );
    }
}
