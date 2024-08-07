// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { Test } from "forge-std/Test.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { LPMath } from "../../../contracts/src/libraries/LPMath.sol";
import { YieldSpaceMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { MockYieldSpaceMath } from "../../../contracts/test/MockYieldSpaceMath.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract YieldSpaceMathTest is Test {
    using FixedPointMath for uint256;
    using Lib for *;

    function test__calculateSharesInGivenBondsOutDown__failure() external {
        // This case demonstrates y < dy
        {
            // NOTE: Coverage only works if I initialize the fixture in the test function
            MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
            vm.expectRevert(
                abi.encodeWithSelector(
                    IHyperdrive.InsufficientLiquidity.selector
                )
            );
            yieldSpaceMath.calculateSharesInGivenBondsOutDown(
                1_000_000e18, // shareReserves
                3_000_000e18, // bondReserves + s
                3_000_000e18 + 1, // amountOut
                ONE - ONE.divDown(22.186877016851916266e18), // stretchedTimeElapsed
                ONE, // c
                ONE // mu
            );
        }

        // This failure case represents _z < ze
        {
            // NOTE: Coverage only works if I initialize the fixture in the test function
            MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
            uint256 ze = 201711851401369463146;
            uint256 y = 88213171903337272229610;
            uint256 dy = 0;
            uint256 timeStretch = ONE.divDown(22.186877016851916266e18);
            uint256 t = 1e18 - ONE.divDown(2e18).mulDown(timeStretch);
            uint256 c = 1093118736259066507447734907058253;
            uint256 mu = 783036196803737685851513777904720724235403957943825401897387005112993629524;
            ze = ze.normalizeToRange(0, 500_000_000e18);
            y = y.normalizeToRange(0, 500_000_000e18);
            dy = dy.normalizeToRange(0, 500_000_000e18);
            c = c.normalizeToRange(0.0001e18, 1e18);
            mu = mu.normalizeToRange(0.0001e18, 1e18);
            if (y < dy) return;
            vm.expectRevert(
                abi.encodeWithSelector(
                    IHyperdrive.InsufficientLiquidity.selector
                )
            );
            yieldSpaceMath.calculateSharesInGivenBondsOutDown(
                ze, // shareReserves
                y, // bondReserves
                dy, // amountIn
                t, // stretchedTimeElapsed
                c, // c
                mu // mu
            );
        }
    }

    function test__calculateBondsOutGivenSharesInDown__failure() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 ze = 224;
        uint256 y = 3226;
        uint256 dz = 5936;
        uint256 timeStretch = ONE.divDown(22.186877016851916266e18);
        uint256 t = 1e18 - ONE.divDown(2e18).mulDown(timeStretch);
        uint256 c = 120209876281281145568259943;
        uint256 mu = 1984;
        mu = mu.normalizeToRange(0, 1e18);
        c = c.normalizeToRange(0, 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(IHyperdrive.InsufficientLiquidity.selector)
        );
        yieldSpaceMath.calculateBondsOutGivenSharesInDown(
            ze, // shareReserves
            y, // bondReserves
            dz, // amountIn
            t, // stretchedTimeElapsed
            c, // c
            mu // mu
        );
    }

    function test__calculateOutGivenIn() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 timeStretch = ONE.divDown(22.186877016851916266e18);
        // test small amount of shares in
        uint256 result1 = yieldSpaceMath.calculateBondsOutGivenSharesInDown(
            100000e18, // shareReserves
            100000e18 + 200000e18, // bondReserves + s
            100e18, // amountIn
            1e18 - ONE.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult1 = 102.50516899477225e18;
        assertApproxEqAbs(result1, pythonResult1, 1e9);

        // test large amount shares in
        uint256 result2 = yieldSpaceMath.calculateBondsOutGivenSharesInDown(
            100000e18, // shareReserves
            100000e18 + 200000e18, // bondReserves + s
            80000e18, // amountIn
            1e18 - ONE.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult2 = 81138.27602200207e18;
        assertApproxEqAbs(result2, pythonResult2, 1e9);

        // test small amount bond in
        uint256 result3 = yieldSpaceMath.calculateSharesOutGivenBondsInDown(
            100000e18, // shareReserves
            100000e18 + 200000e18, // bondReserves + s
            100e18, // amountIn
            1e18 - ONE.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult3 = 97.55314236719278e18;
        assertApproxEqAbs(result3, pythonResult3, 1e9);

        // test large amount bond in
        uint256 result4 = yieldSpaceMath.calculateSharesOutGivenBondsInDown(
            100000e18, // shareReserves
            100000e18 + 200000e18, // bondReserves + s
            80000e18, // amountIn
            1e18 - ONE.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult4 = 76850.14470187116e18;
        assertApproxEqAbs(result4, pythonResult4, 1e9);
    }

    function test__calculateSharesInGivenBondsOutUp__failure() external {
        // This failure case represents _z < ze
        {
            // NOTE: Coverage only works if I initialize the fixture in the test function
            MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
            uint256 ze = 201711851401369463146;
            uint256 y = 88213171903337272229610;
            uint256 dy = 0;
            uint256 timeStretch = ONE.divDown(22.186877016851916266e18);
            uint256 t = 1e18 - ONE.divDown(2e18).mulDown(timeStretch);
            uint256 c = 1093118736259066507447734907058253;
            uint256 mu = 783036196803737685851513777904720724235403957943825401897387005112993629524;
            ze = ze.normalizeToRange(0, 500_000_000e18);
            y = y.normalizeToRange(0, 500_000_000e18);
            dy = dy.normalizeToRange(0, 500_000_000e18);
            c = c.normalizeToRange(0.0001e18, 1e18);
            mu = mu.normalizeToRange(0.0001e18, 1e18);
            if (y < dy) return;
            vm.expectRevert(
                abi.encodeWithSelector(
                    IHyperdrive.InsufficientLiquidity.selector
                )
            );
            yieldSpaceMath.calculateSharesInGivenBondsOutUp(
                ze, // shareReserves
                y, // bondReserves
                dy, // amountIn
                t, // stretchedTimeElapsed
                c, // c
                mu // mu
            );
        }
    }

    // calculateInGivenOut false
    function test__calculateSharesInGivenBondsOut() external {
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 timeStretch = ONE.divDown(22.186877016851916266e18);

        // test small amount bond in
        uint256 result3 = yieldSpaceMath.calculateSharesInGivenBondsOutUp(
            100000e18, // shareReserves
            100000e18 + 200000e18, // bondReserves + s
            100e18, // amountIn
            1e18 - ONE.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult3 = 97.55601990513969e18;
        assertApproxEqAbs(result3, pythonResult3, 1e9);

        // test large amount bond in
        uint256 result4 = yieldSpaceMath.calculateSharesInGivenBondsOutUp(
            100000e18, // shareReserves
            100000e18 + 200000e18, // bondReserves + s
            80000e18, // amountIn
            1e18 - ONE.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult4 = 78866.87433323538e18;
        assertApproxEqAbs(result4, pythonResult4, 1e9);

        // test y < dy
        vm.expectRevert(
            abi.encodeWithSelector(IHyperdrive.InsufficientLiquidity.selector)
        );
        yieldSpaceMath.calculateSharesInGivenBondsOutUp(
            100000e18, // shareReserves
            99e18, // bondReserves + s
            100e18, // amountIn
            1e18 - ONE.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
    }

    // This test verifies that sane values won't result in the YieldSpace math
    // functions returning zero.
    function test__calculateSharesInGivenBondsOut__extremeValues(
        uint256 fixedRate,
        uint256 shareReserves,
        uint256 vaultSharePrice,
        uint256 initialVaultSharePrice,
        uint256 tradeSize
    ) external {
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();

        uint256 minimumShareReserves = 1e5;
        fixedRate = fixedRate.normalizeToRange(0.01e18, 1e18);
        initialVaultSharePrice = initialVaultSharePrice.normalizeToRange(
            0.8e18,
            5e18
        );
        vaultSharePrice = vaultSharePrice.normalizeToRange(
            initialVaultSharePrice,
            5e18
        );

        // Test a large span of orders of magnitudes of both the reserves and
        // the size of the reserves. This test demonstrates that for the
        // expected range of reserves reserves, the YieldSpaceMath will only
        // return zero for tiny amounts of tokens.
        for (uint256 i = 6; i <= 18; i += 1) {
            shareReserves = shareReserves.normalizeToRange(
                10 ** (i + 1),
                10 ** (i + 9)
            );
            for (uint256 j = i - (i / 2 + 1); j < i; j++) {
                // Calculate the bond reserves that give the pool the expected spot rate.
                uint256 timeStretch = HyperdriveMath.calculateTimeStretch(
                    fixedRate,
                    365 days
                );
                uint256 fixedRate_ = fixedRate; // avoid stack-too-deep
                (, int256 shareAdjustment, uint256 bondReserves) = LPMath
                    .calculateInitialReserves(
                        shareReserves,
                        vaultSharePrice,
                        initialVaultSharePrice,
                        fixedRate_,
                        365 days,
                        timeStretch
                    );
                {
                    (, uint256 maxBondAmount) = HyperdriveUtils
                        .calculateMaxLong(
                            HyperdriveUtils.MaxTradeParams({
                                shareReserves: shareReserves,
                                shareAdjustment: shareAdjustment,
                                bondReserves: bondReserves,
                                longsOutstanding: 0,
                                longExposure: 0,
                                timeStretch: timeStretch,
                                vaultSharePrice: vaultSharePrice,
                                initialVaultSharePrice: initialVaultSharePrice,
                                minimumShareReserves: minimumShareReserves,
                                curveFee: 0,
                                flatFee: 0,
                                governanceLPFee: 0
                            }),
                            0,
                            15
                        );
                    tradeSize = tradeSize.normalizeToRange(
                        10 ** j,
                        maxBondAmount
                    );
                }
                uint256 shareReserves_ = shareReserves; // avoid stack-too-deep
                uint256 vaultSharePrice_ = vaultSharePrice; // avoid stack-too-deep
                uint256 initialVaultSharePrice_ = initialVaultSharePrice; // avoid stack-too-deep
                uint256 tradeSize_ = tradeSize; // avoid stack-too-deep
                uint256 result = yieldSpaceMath
                    .calculateSharesInGivenBondsOutDown(
                        shareReserves_,
                        bondReserves,
                        tradeSize_,
                        1e18 - ONE.mulDown(timeStretch),
                        vaultSharePrice_,
                        initialVaultSharePrice_
                    );
                assertGt(result, 0);
            }
        }
    }

    function test__calculateMaxBuy(
        uint256 fixedRate,
        uint256 shareReserves,
        uint256 vaultSharePrice,
        uint256 initialVaultSharePrice
    ) external {
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();

        fixedRate = fixedRate.normalizeToRange(0.01e18, 1e18);
        shareReserves = shareReserves.normalizeToRange(
            0.0001e18,
            500_000_000e18
        );
        initialVaultSharePrice = initialVaultSharePrice.normalizeToRange(
            0.8e18,
            5e18
        );
        vaultSharePrice = vaultSharePrice.normalizeToRange(
            initialVaultSharePrice,
            5e18
        );

        // Calculate the bond reserves that give the pool the expected spot rate.
        uint256 timeStretch = HyperdriveMath.calculateTimeStretch(
            fixedRate,
            365 days
        );
        (, int256 shareAdjustment, uint256 bondReserves) = LPMath
            .calculateInitialReserves(
                shareReserves,
                vaultSharePrice,
                initialVaultSharePrice,
                fixedRate,
                365 days,
                timeStretch
            );
        uint256 effectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(shareReserves, shareAdjustment);

        // Calculatethe share payment and bonds proceeds of the max buy.
        (uint256 maxDy, bool success) = yieldSpaceMath
            .calculateMaxBuyBondsOutSafe(
                effectiveShareReserves,
                bondReserves,
                1e18 - ONE.mulDown(timeStretch),
                vaultSharePrice,
                initialVaultSharePrice
            );
        assertEq(success, true);
        uint256 maxDz;
        (maxDz, success) = yieldSpaceMath.calculateMaxBuySharesInSafe(
            effectiveShareReserves,
            bondReserves,
            1e18 - ONE.mulDown(timeStretch),
            vaultSharePrice,
            initialVaultSharePrice
        );

        // Ensure that the maximum buy is a valid trade on this invariant and
        // that the ending spot price is close to 1.
        uint256 vaultSharePrice_ = vaultSharePrice; // avoid stack-too-deep
        uint256 initialVaultSharePrice_ = initialVaultSharePrice; // avoid stack-too-deep
        assertApproxEqAbs(
            yieldSpaceMath.kDown(
                effectiveShareReserves,
                bondReserves,
                ONE - timeStretch,
                vaultSharePrice_,
                initialVaultSharePrice_
            ),
            yieldSpaceMath.kDown(
                effectiveShareReserves + maxDz,
                bondReserves - maxDy,
                ONE - timeStretch,
                vaultSharePrice_,
                initialVaultSharePrice_
            ),
            1e12 // TODO: Investigate this bound.
        );
        assertApproxEqAbs(
            HyperdriveMath.calculateSpotPrice(
                effectiveShareReserves + maxDz,
                bondReserves - maxDy,
                initialVaultSharePrice_,
                timeStretch
            ),
            1e18,
            1e7
        );
    }
}
