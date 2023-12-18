// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

// FIXME
import { console2 as console } from "forge-std/console2.sol";

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract NegativeInterestLpTest is HyperdriveTest {
    using FixedPointMath for *;
    using HyperdriveUtils for *;
    using Lib for *;

    // FIXME: Based on the issues with NegativePresentValue, I should try to
    // scale the proceeds in `calculatePresentValue`. I'll need to come up with
    // a reason why the netting things that I talked about aren't required, but
    // I think it has something to do with the fact that we are still net short
    // when we consider the effective share reserves (the inventory of longs and
    // shorts doesn't have anything to do with the share reserves).
    function test__negativeInterest__earlyWithdrawalsGetLess(
        bytes32 __seed
    ) external {
        // FIXME
        __seed = 0x17c40277bdcc700449daf4cfc143a45267dfae59698a606c80ce0ca0a4f772d8;

        // Set the seed.
        _seed = __seed;

        // Alice initialize the pool.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        uint256 aliceLpShares = initialize(alice, fixedRate, contribution);
        contribution -= 2 * hyperdrive.getPoolConfig().minimumShareReserves;

        // Celine adds liquidity.
        uint256 celineLpShares = addLiquidity(celine, contribution);

        // Accrues positive interest for a period. This gives us an interesting
        // starting share price.
        advanceTime(hyperdrive.getPoolConfig().positionDuration, 1e18);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Execute a series of random open trades.
        uint256 maturityTime0 = hyperdrive.maturityTimeFromLatestCheckpoint();
        Trade[] memory trades0 = randomOpenTrades();
        for (uint256 i = 0; i < trades0.length; i++) {
            executeTrade(trades0[i]);
        }

        // Time passes and negative interest accrues.
        {
            uint256 timeDelta = uint256(seed()).normalizeToRange(
                CHECKPOINT_DURATION,
                POSITION_DURATION.mulDown(0.99e18)
            );
            int256 variableRate = int256(uint256(seed())).normalizeToRange(
                -0.5e18,
                -0.1e18
            );
            advanceTimeWithCheckpoints(timeDelta, variableRate);
        }

        // Execute a series of random open trades.
        uint256 maturityTime1 = hyperdrive.maturityTimeFromLatestCheckpoint();
        Trade[] memory trades1 = randomOpenTrades();
        for (uint256 i = 0; i < trades1.length; i++) {
            executeTrade(trades1[i]);
        }

        // Alice removes her liquidity.
        console.log("test: 1");
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidity(alice, aliceLpShares);
        console.log("test: 2");

        // Close all of the positions in a random order.
        Trade[] memory closeTrades;
        {
            Trade[] memory closeTrades0 = randomCloseTrades(
                maturityTime0,
                hyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Long,
                        maturityTime0
                    ),
                    alice
                ),
                maturityTime0,
                hyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Short,
                        maturityTime0
                    ),
                    alice
                )
            );
            Trade[] memory closeTrades1 = randomCloseTrades(
                maturityTime1,
                hyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Long,
                        maturityTime1
                    ),
                    alice
                ),
                maturityTime1,
                hyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Short,
                        maturityTime1
                    ),
                    alice
                )
            );
            closeTrades = combineTrades(closeTrades0, closeTrades1);
        }
        for (uint256 i = 0; i < closeTrades.length; i++) {
            executeTrade(closeTrades[i]);
        }

        // Celine removes her liquidity.
        console.log("test: 3");
        (
            uint256 celineBaseProceeds,
            uint256 celineWithdrawalShares
        ) = removeLiquidity(celine, celineLpShares);
        console.log("test: 4");

        // Alice and Celine redeem their withdrawal shares.
        {
            (uint256 aliceWithdrawalProceeds, ) = redeemWithdrawalShares(
                alice,
                aliceWithdrawalShares
            );
            aliceBaseProceeds += aliceWithdrawalProceeds;
        }
        {
            (uint256 celineWithdrawalProceeds, ) = redeemWithdrawalShares(
                celine,
                celineWithdrawalShares
            );
            celineBaseProceeds += celineWithdrawalProceeds;
        }

        // FIXME: Explain the fudge factor.
        //
        // Ensure that Alice's base proceeds were less than or equal to Celine's.
        assertLe(aliceBaseProceeds.mulDown(0.99e18), celineBaseProceeds);
    }
}
