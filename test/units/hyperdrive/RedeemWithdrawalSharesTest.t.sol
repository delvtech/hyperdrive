// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { VmSafe } from "forge-std/Vm.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract RedeemWithdrawalSharesTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_redeem_withdrawal_shares_failure_output_limit() external {
        // Initialize the pool.
        uint256 lpShares = initialize(alice, 0.02e18, 500_000_000e18);

        // Bob opens a large short.
        uint256 shortAmount = HyperdriveUtils.calculateMaxShort(hyperdrive);
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Alice removes her liquidity.
        (, uint256 withdrawalShares) = removeLiquidity(alice, lpShares);

        // The term passes and no interest accrues.
        advanceTime(POSITION_DURATION, 0);

        // Alice tries to redeem her withdrawal shares with a large output limit.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(Errors.OutputLimit.selector);
        uint256 expectedOutputPerShare = shortAmount.divDown(withdrawalShares);
        hyperdrive.redeemWithdrawalShares(
            withdrawalShares,
            2 * expectedOutputPerShare,
            alice,
            true
        );
    }
}
