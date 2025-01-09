// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

/// @dev An integration test suite for the mint function.
contract MintTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    /// @dev Sets up the harness and deploys and initializes a pool with fees.
    function setUp() public override {
        // Run the higher level setup function.
        super.setUp();

        // Deploy and initialize a pool with the flat fee and governance LP fee
        // turned on. The curve fee is turned off to simplify the assertions.
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        config.fees.flat = 0.0005e18;
        config.fees.governanceLP = 0.15e18;
        deploy(alice, config);
        initialize(alice, 0.05e18, 100_000e18);
    }

    /// @dev Ensures that minting and closing positions instantaneously works as
    ///      expected. In particular, we want to ensure that:
    ///
    ///      - Idle increases by the flat fees and is less than or equal to the
    ///        base balance of Hyperdrive.
    ///      - The spot price remains the same.
    ///      - The pool depth remains the same.
    ///      - The trader gets the right amount of money from closing their
    ///        positions.
    function test_mint_and_close_instantaneously(uint256 _baseAmount) external {
        // Get some data before minting and closing the positions.
        uint256 spotPriceBefore = hyperdrive.calculateSpotPrice();
        uint256 kBefore = hyperdrive.k();
        uint256 idleBefore = hyperdrive.idle();

        // Alice mints some bonds.
        _baseAmount = _baseAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            20_000e18
        );
        (uint256 maturityTime, uint256 bondAmount) = mint(alice, _baseAmount);

        // Alice closes the long and short instantaneously.
        uint256 longProceeds = closeLong(alice, maturityTime, bondAmount);
        uint256 shortProceeds = closeShort(alice, maturityTime, bondAmount);

        // Ensure that Alice's total proceeds are less than the amount of base
        // paid. Furthermore, we assert that the proceeds are approximately
        // equal to the base amount minus the governance fees.
        assertLt(longProceeds + shortProceeds, _baseAmount);
        assertApproxEqAbs(
            longProceeds + shortProceeds,
            _baseAmount -
                2 *
                bondAmount.mulUp(hyperdrive.getPoolConfig().fees.flat).mulDown(
                    hyperdrive.getPoolConfig().fees.governanceLP
                ),
            1e6
        );

        // Ensure that the spot price didn't change.
        assertApproxEqAbs(hyperdrive.calculateSpotPrice(), spotPriceBefore, 1);

        // Ensure that the pool depth didn't change.
        assertApproxEqAbs(hyperdrive.k(), kBefore, 1e6);

        // Ensure that the idle stayed roughly constant during this trade.
        // Furthermore, we can assert that the pool's idle is less than or equal
        // to the base balance of the Hyperdrive pool. This ensures that the
        // pool thinks it is solvent and that it actually is solvent.
        assertApproxEqAbs(hyperdrive.idle(), idleBefore, 1e6);
        assertLe(hyperdrive.idle(), baseToken.balanceOf(address(hyperdrive)));
    }

    /// @dev Ensures that minting and closing positions before maturity works as
    ///      expected. In particular, we want to ensure that:
    ///
    ///      - Idle increases by the flat fees and is less than or equal to the
    ///        base balance of Hyperdrive.
    ///      - The spot price remains the same.
    ///      - The pool depth remains the same.
    ///      - The trader gets the right amount of money from closing their
    ///        positions.
    /// @param _baseAmount The amount of base to use when minting the positions.
    /// @param _timeDelta The amount of time that passes. This is greater than
    ///        no time and less than the position duration.
    /// @param _variableRate The variable rate when time passes.
    function test_mint_and_close_before_maturity(
        uint256 _baseAmount,
        uint256 _timeDelta,
        int256 _variableRate
    ) external {
        // Get some data before minting and closing the positions.
        uint256 vaultSharePriceBefore = hyperdrive
            .getPoolInfo()
            .vaultSharePrice;
        uint256 spotPriceBefore = hyperdrive.calculateSpotPrice();
        uint256 idleBefore = hyperdrive.idle();

        // Alice mints some bonds.
        _baseAmount = _baseAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            20_000e18
        );
        (uint256 maturityTime, uint256 bondAmount) = mint(alice, _baseAmount);

        // Part of the term passes and interest accrues.
        _variableRate = _variableRate.normalizeToRange(0, 2.5e18);
        _timeDelta = _timeDelta.normalizeToRange(
            1,
            hyperdrive.getPoolConfig().positionDuration - 1
        );
        advanceTime(_timeDelta, _variableRate);

        // Alice closes the long and short before maturity.
        uint256 longProceeds = closeLong(alice, maturityTime, bondAmount);
        uint256 shortProceeds = closeShort(alice, maturityTime, bondAmount);

        // Ensure that Alice's total proceeds are less than the base amount
        // scaled by the amount of interest that accrued.
        uint256 baseAmount = _baseAmount; // avoid stack-too-deep
        assertLt(
            longProceeds + shortProceeds,
            baseAmount.mulDivDown(
                hyperdrive.getPoolInfo().vaultSharePrice,
                vaultSharePriceBefore
            )
        );

        // Ensure that Alice received the correct amount of proceeds from
        // closing her position. She should receive the par value of the bond
        // plus any interest that accrued over the term. Additionally, she
        // receives the flat fee that she repaid. Then she pays the flat fee
        // twice. The flat fee that she pays is scaled for the amount of time
        // that passed since minting the bonds.
        assertApproxEqAbs(
            longProceeds + shortProceeds,
            bondAmount.mulDivDown(
                hyperdrive.getPoolInfo().vaultSharePrice,
                vaultSharePriceBefore
            ) +
                bondAmount.mulUp(hyperdrive.getPoolConfig().fees.flat) -
                2 *
                bondAmount.mulUp(hyperdrive.getPoolConfig().fees.flat).mulDown(
                    ONE - hyperdrive.calculateTimeRemaining(maturityTime)
                ),
            1e7
        );

        // Ensure that the spot price didn't change.
        assertApproxEqAbs(hyperdrive.calculateSpotPrice(), spotPriceBefore, 1);

        // Ensure that the idle only increased by the flat fee from each trade.
        // Furthermore, we can assert that the pool's idle is less than or equal
        // to the base balance of the Hyperdrive pool. This ensures that the
        // pool thinks it is solvent and that it actually is solvent.
        assertApproxEqAbs(
            hyperdrive.idle(),
            idleBefore.mulDivDown(
                hyperdrive.getPoolInfo().vaultSharePrice,
                vaultSharePriceBefore
            ) +
                2 *
                bondAmount
                    .mulUp(hyperdrive.getPoolConfig().fees.flat)
                    .mulDown(
                        ONE - hyperdrive.calculateTimeRemaining(maturityTime)
                    )
                    .mulDown(
                        ONE - hyperdrive.getPoolConfig().fees.governanceLP
                    ),
            1e7
        );
        assertLe(hyperdrive.idle(), baseToken.balanceOf(address(hyperdrive)));
    }

    /// @dev Ensures that minting and closing positions at maturity works as
    ///      expected. In particular, we want to ensure that:
    ///
    ///      - Idle increases by the flat fees and is less than or equal to the
    ///        base balance of Hyperdrive.
    ///      - The spot price remains the same.
    /// @param _baseAmount The amount of base to use when minting the positions.
    /// @param _variableRate The variable rate when time passes.
    function test_mint_and_close_at_maturity(
        uint256 _baseAmount,
        int256 _variableRate
    ) external {
        // Get some data before minting and closing the positions.
        uint256 vaultSharePriceBefore = hyperdrive
            .getPoolInfo()
            .vaultSharePrice;
        uint256 spotPriceBefore = hyperdrive.calculateSpotPrice();
        uint256 idleBefore = hyperdrive.idle();

        // Alice mints some bonds.
        _baseAmount = _baseAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            20_000e18
        );
        (uint256 maturityTime, uint256 bondAmount) = mint(alice, _baseAmount);

        // The term passes and interest accrues.
        _variableRate = _variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(hyperdrive.getPoolConfig().positionDuration, _variableRate);

        // Alice closes the long and short at maturity.
        uint256 longProceeds = closeLong(alice, maturityTime, bondAmount);
        uint256 shortProceeds = closeShort(alice, maturityTime, bondAmount);

        // Ensure that Alice's total proceeds are less than the base amount
        // scaled by the amount of interest that accrued.
        uint256 baseAmount = _baseAmount; // avoid stack-too-deep
        assertLt(
            longProceeds + shortProceeds,
            baseAmount.mulDivDown(
                hyperdrive.getPoolInfo().vaultSharePrice,
                vaultSharePriceBefore
            )
        );

        // Ensure that Alice received the correct amount of proceeds from
        // closing her position. She should receive the par value of the bond
        // plus any interest that accrued over the term. Additionally, she
        // receives the flat fee that she repaid. Then she pays the flat fee
        // twice.
        assertApproxEqAbs(
            longProceeds + shortProceeds,
            bondAmount.mulDivDown(
                hyperdrive.getPoolInfo().vaultSharePrice,
                vaultSharePriceBefore
            ) - bondAmount.mulUp(hyperdrive.getPoolConfig().fees.flat),
            1e6
        );

        // Ensure that the spot price didn't change.
        assertEq(hyperdrive.calculateSpotPrice(), spotPriceBefore);

        // Ensure that the idle only increased by the flat fee from each trade.
        // Furthermore, we can assert that the pool's idle is less than or equal
        // to the base balance of the Hyperdrive pool. This ensures that the
        // pool thinks it is solvent and that it actually is solvent.
        assertApproxEqAbs(
            hyperdrive.idle(),
            idleBefore.mulDivDown(
                hyperdrive.getPoolInfo().vaultSharePrice,
                vaultSharePriceBefore
            ) +
                2 *
                bondAmount.mulUp(hyperdrive.getPoolConfig().fees.flat).mulDown(
                    ONE - hyperdrive.getPoolConfig().fees.governanceLP
                ),
            1e6
        );
        assertLe(hyperdrive.idle(), baseToken.balanceOf(address(hyperdrive)));
    }
}
