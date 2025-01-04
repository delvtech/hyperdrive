// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdError } from "forge-std/StdError.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

/// @dev A test suite for the burn function.
contract BurnTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    /// @dev Sets up the harness and deploys and initializes a pool with fees.
    function setUp() public override {
        // Run the higher level setup function.
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();

        // Deploy and initialize a pool with non-trivial fees. The curve fee is
        // kept to zero to enable us to compare the result of burning with the
        // result of closing the positions separately.
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        config.fees.flat = 0.0005e18;
        config.fees.governanceLP = 0.15e18;
        deploy(alice, config);
        initialize(alice, 0.05e18, 100_000_000e18);
    }

    /// @dev Ensures that burning fails when the amount is zero.
    function test_burn_failure_zero_amount() external {
        // Mint a set of positions to Bob to use during testing.
        uint256 amountPaid = 100_000e18;
        (uint256 maturityTime, ) = mint(bob, amountPaid);

        // Attempt to burn with a bond amount of zero.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.MinimumTransactionAmount.selector);
        hyperdrive.burn(
            maturityTime,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that burning fails when the destination is the zero address.
    function test_burn_failure_destination_zero_address() external {
        // Mint a set of positions to Bob to use during testing.
        uint256 amountPaid = 100_000e18;
        (uint256 maturityTime, uint256 bondAmount) = mint(bob, amountPaid);

        // Alice attempts to set the destination to the zero address.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(IHyperdrive.RestrictedZeroAddress.selector);
        hyperdrive.burn(
            maturityTime,
            bondAmount,
            0,
            IHyperdrive.Options({
                destination: address(0),
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that burning fails when the bond amount is larger than the
    ///      balance of the burner.
    function test_burn_failure_invalid_amount() external {
        // Mint a set of positions to Bob to use during testing.
        uint256 amountPaid = 100_000e18;
        (uint256 maturityTime, uint256 bondAmount) = mint(bob, amountPaid);

        // Attempt to burn too many bonds. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.InsufficientBalance.selector);
        hyperdrive.burn(
            maturityTime,
            bondAmount + 1,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that burning fails when the maturity time is zero.
    function test_burn_failure_zero_maturity() external {
        // Mint a set of positions to Bob to use during testing.
        uint256 amountPaid = 100_000e18;
        (, uint256 bondAmount) = mint(bob, amountPaid);

        // Attempt to use a maturity time of zero.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.burn(
            0,
            bondAmount,
            0,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that burning fails when the maturity time is invalid.
    function test_burn_failure_invalid_maturity() external {
        // Mint a set of positions to Bob to use during testing.
        uint256 amountPaid = 100_000e18;
        mint(bob, amountPaid);

        // Attempt to use a timestamp greater than the maximum range.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.InvalidTimestamp.selector);
        hyperdrive.burn(
            uint256(type(uint248).max) + 1,
            MINIMUM_TRANSACTION_AMOUNT,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that bonds can be burned successfully immediately after
    ///      they are minted.
    function test_burn_immediately_with_regular_amount() external {
        // Mint a set of positions to Alice to use during testing.
        uint256 amountPaid = 100_000e18;
        (uint256 maturityTime, uint256 bondAmount) = mint(alice, amountPaid);

        // Get some data before minting.
        BurnTestCase memory testCase = _burnTestCase(
            alice, // burner
            bob, // destination
            maturityTime, // maturity time
            bondAmount, // bond amount
            true, // asBase
            "" // extraData
        );

        // Verify the mint transaction.
        _verifyBurn(testCase, amountPaid);
    }

    /// @dev Ensures that a small amount of bonds can be burned successfully
    ///      immediately after they are minted.
    function test_burn_immediately_with_small_amount() external {
        // Mint a set of positions to Alice to use during testing.
        uint256 amountPaid = 0.01e18;
        (uint256 maturityTime, uint256 bondAmount) = mint(alice, amountPaid);

        // Get some data before minting.
        BurnTestCase memory testCase = _burnTestCase(
            alice, // burner
            bob, // destination
            maturityTime, // maturity time
            bondAmount, // bond amount
            true, // asBase
            "" // extraData
        );

        // Verify the mint transaction.
        _verifyBurn(testCase, amountPaid);
    }

    /// @dev Ensure that bonds can be successfully burned halfway through the
    ///      term.
    function test_burn_halfway_through_term() external {
        // Alice mints a large pair position.
        uint256 amountPaid = 100_000e18;
        (uint256 maturityTime, uint256 bondAmount) = mint(alice, amountPaid);

        // Most of the term passes. The variable rate equals the fixed rate.
        uint256 timeDelta = 0.5e18;
        advanceTime(POSITION_DURATION.mulDown(timeDelta), 0.05e18);

        // Get some data before minting.
        BurnTestCase memory testCase = _burnTestCase(
            alice, // burner
            bob, // destination
            maturityTime, // maturity time
            bondAmount, // bond amount
            true, // asBase
            "" // extraData
        );

        // Verify the mint transaction.
        _verifyBurn(testCase, amountPaid);
    }

    /// @dev Ensure that bonds can be successfully burned at maturity.
    function test_burn_at_maturity() external {
        // Alice mints a large pair position.
        uint256 amountPaid = 100_000e18;
        (uint256 maturityTime, uint256 bondAmount) = mint(alice, amountPaid);

        // Most of the term passes. The variable rate equals the fixed rate.
        uint256 timeDelta = 1e18;
        advanceTime(POSITION_DURATION.mulDown(timeDelta), 0.05e18);

        // Get some data before minting.
        BurnTestCase memory testCase = _burnTestCase(
            alice, // burner
            bob, // destination
            maturityTime, // maturity time
            bondAmount, // bond amount
            true, // asBase
            "" // extraData
        );

        // Verify the mint transaction.
        _verifyBurn(testCase, amountPaid);
    }

    // // FIXME
    // function test_close_long_redeem_negative_interest() external {
    //     // Initialize the pool with a large amount of capital.
    //     uint256 fixedRate = 0.05e18;
    //     uint256 contribution = 500_000_000e18;
    //     initialize(alice, fixedRate, contribution);

    //     // Open a long position.
    //     uint256 basePaid = 10e18;
    //     (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

    //     // Term passes. The pool accrues interest at the current apr.
    //     uint256 timeAdvanced = POSITION_DURATION;
    //     int256 apr = -0.3e18;
    //     advanceTime(timeAdvanced, apr);

    //     // Get the reserves before closing the long.
    //     IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
    //     uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
    //     uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
    //         address(hyperdrive)
    //     );

    //     // Redeem the bonds
    //     uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

    //     // Account the negative interest with the bondAmount as principal
    //     (uint256 bondFaceValue, ) = HyperdriveUtils.calculateCompoundInterest(
    //         bondAmount,
    //         apr,
    //         timeAdvanced
    //     );

    //     // As negative interest occurred over the duration, the long position
    //     // takes on the loss. As the "matured" bondAmount is implicitly an
    //     // amount of shares, the base value of those shares are negative
    //     // relative to what they were at the start of the term.
    //     uint256 matureBondsValue = bondAmount
    //         .divDown(hyperdrive.getPoolConfig().initialVaultSharePrice)
    //         .mulDown(poolInfoBefore.vaultSharePrice);

    //     // Verify that Bob received base equal to the full bond amount.
    //     assertApproxEqAbs(baseProceeds, bondFaceValue, 10);
    //     assertApproxEqAbs(baseProceeds, matureBondsValue, 10);

    //     // Verify that the close long updates were correct.
    //     verifyCloseLong(
    //         TestCase({
    //             poolInfoBefore: poolInfoBefore,
    //             traderBaseBalanceBefore: bobBaseBalanceBefore,
    //             hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
    //             baseProceeds: baseProceeds,
    //             bondAmount: bondAmount,
    //             maturityTime: maturityTime,
    //             wasCheckpointed: false
    //         })
    //     );
    // }

    // // FIXME
    // function test_close_long_half_term_negative_interest() external {
    //     // Initialize the pool with a large amount of capital.
    //     uint256 fixedRate = 0.05e18;
    //     uint256 contribution = 500_000_000e18;
    //     initialize(alice, fixedRate, contribution);

    //     // Open a long position.
    //     uint256 basePaid = 10e18;
    //     (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

    //     // Term passes. The pool accrues negative interest.
    //     uint256 timeAdvanced = POSITION_DURATION.mulDown(0.5e18);
    //     int256 apr = -0.25e18;
    //     advanceTime(timeAdvanced, apr);

    //     // Get the reserves before closing the long.
    //     IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
    //     uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
    //     uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
    //         address(hyperdrive)
    //     );

    //     // Redeem the bonds
    //     uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

    //     // Initial share price
    //     uint256 initialVaultSharePrice = hyperdrive
    //         .getPoolConfig()
    //         .initialVaultSharePrice;

    //     // Ensure that the base proceeds are correct.
    //     {
    //         // All mature bonds are redeemed at the equivalent amount of shares
    //         // held throughout the duration, losing capital
    //         uint256 matureBonds = bondAmount.mulDown(
    //             ONE -
    //                 HyperdriveUtils.calculateTimeRemaining(
    //                     hyperdrive,
    //                     maturityTime
    //                 )
    //         );
    //         uint256 bondsValue = matureBonds;

    //         // Portion of immature bonds are sold on the YieldSpace curve
    //         uint256 immatureBonds = bondAmount - matureBonds;
    //         bondsValue += YieldSpaceMath
    //             .calculateSharesOutGivenBondsInDown(
    //                 HyperdriveMath.calculateEffectiveShareReserves(
    //                     poolInfoBefore.shareReserves,
    //                     poolInfoBefore.shareAdjustment
    //                 ),
    //                 poolInfoBefore.bondReserves,
    //                 immatureBonds,
    //                 ONE - hyperdrive.getPoolConfig().timeStretch,
    //                 poolInfoBefore.vaultSharePrice,
    //                 initialVaultSharePrice
    //             )
    //             .mulDown(poolInfoBefore.vaultSharePrice);

    //         bondsValue = bondsValue.divDown(initialVaultSharePrice).mulDown(
    //             poolInfoBefore.vaultSharePrice
    //         );

    //         assertLe(baseProceeds, bondsValue);
    //         assertApproxEqAbs(baseProceeds, bondsValue, 1);
    //     }

    //     // Verify that the close long updates were correct.
    //     verifyCloseLong(
    //         TestCase({
    //             poolInfoBefore: poolInfoBefore,
    //             traderBaseBalanceBefore: bobBaseBalanceBefore,
    //             hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
    //             baseProceeds: baseProceeds,
    //             bondAmount: bondAmount,
    //             maturityTime: maturityTime,
    //             wasCheckpointed: false
    //         })
    //     );
    // }

    // // FIXME
    // //
    // // This test ensures that the reserves are updated correctly when longs are
    // // closed at maturity with negative interest.
    // function test_close_long_negative_interest_at_maturity() external {
    //     // Initialize the pool with a large amount of capital.
    //     uint256 fixedRate = 0.05e18;
    //     uint256 contribution = 500_000_000e18;
    //     initialize(alice, fixedRate, contribution);

    //     // Open a long position.
    //     uint256 basePaid = 10e18;
    //     (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

    //     // The term passes and the pool accrues negative interest.
    //     int256 apr = -0.25e18;
    //     advanceTime(POSITION_DURATION, apr);

    //     // Get the reserves and base balances before closing the long.
    //     IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
    //     uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
    //     uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
    //         address(hyperdrive)
    //     );

    //     // Bob redeems the bonds. Ensure that the return value matches the
    //     // amount of base transferred to Bob.
    //     uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);
    //     uint256 closeVaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;

    //     // Bond holders take a proportional haircut on any negative interest
    //     // that accrues.
    //     uint256 bondValue = bondAmount
    //         .divDown(hyperdrive.getPoolConfig().initialVaultSharePrice)
    //         .mulDown(closeVaultSharePrice);

    //     // Calculate the value of the bonds compounded at the negative APR.
    //     (uint256 bondFaceValue, ) = HyperdriveUtils.calculateCompoundInterest(
    //         bondAmount,
    //         apr,
    //         POSITION_DURATION
    //     );

    //     assertApproxEqAbs(baseProceeds, bondValue, 6);
    //     assertApproxEqAbs(bondValue, bondFaceValue, 5);

    //     // Verify that the close long updates were correct.
    //     verifyCloseLong(
    //         TestCase({
    //             poolInfoBefore: poolInfoBefore,
    //             traderBaseBalanceBefore: bobBaseBalanceBefore,
    //             hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
    //             baseProceeds: baseProceeds,
    //             bondAmount: bondAmount,
    //             maturityTime: maturityTime,
    //             wasCheckpointed: false
    //         })
    //     );
    // }

    // // FIXME
    // //
    // // This test ensures that waiting to close your longs won't avoid negative
    // // interest that occurred while the long was open.
    // function test_close_long_negative_interest_before_maturity() external {
    //     // Initialize the pool with a large amount of capital.
    //     uint256 fixedRate = 0.05e18;
    //     uint256 contribution = 500_000_000e18;
    //     initialize(alice, fixedRate, contribution);

    //     // Open a long position.
    //     uint256 basePaid = 10e18;
    //     (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

    //     // The term passes and the pool accrues negative interest.
    //     int256 apr = -0.25e18;
    //     advanceTime(POSITION_DURATION, apr);

    //     // A checkpoint is created to lock in the close price.
    //     hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);
    //     uint256 closeVaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;

    //     // Another term passes and a large amount of positive interest accrues.
    //     advanceTime(POSITION_DURATION, 0.7e18);
    //     hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

    //     // Get the reserves and base balances before closing the long.
    //     IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
    //     uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
    //     uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
    //         address(hyperdrive)
    //     );

    //     // Bob redeems the bonds. Ensure that the return value matches the
    //     // amount of base transferred to Bob.
    //     uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

    //     // Bond holders take a proportional haircut on any negative interest
    //     // that accrues.
    //     uint256 bondValue = bondAmount
    //         .divDown(hyperdrive.getPoolConfig().initialVaultSharePrice)
    //         .mulDown(closeVaultSharePrice);

    //     // Calculate the value of the bonds compounded at the negative APR.
    //     (uint256 bondFaceValue, ) = HyperdriveUtils.calculateCompoundInterest(
    //         bondAmount,
    //         apr,
    //         POSITION_DURATION
    //     );

    //     assertLe(baseProceeds, bondValue);
    //     assertApproxEqAbs(baseProceeds, bondValue, 7);
    //     assertApproxEqAbs(bondValue, bondFaceValue, 5);

    //     // Verify that the close long updates were correct.
    //     verifyCloseLong(
    //         TestCase({
    //             poolInfoBefore: poolInfoBefore,
    //             traderBaseBalanceBefore: bobBaseBalanceBefore,
    //             hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
    //             baseProceeds: baseProceeds,
    //             bondAmount: bondAmount,
    //             maturityTime: maturityTime,
    //             wasCheckpointed: true
    //         })
    //     );
    // }

    // // FIXME
    // //
    // // This test ensures that waiting to close your longs won't avoid negative
    // // interest that occurred after the long was open while it was a zombie.
    // function test_close_long_negative_interest_after_maturity() external {
    //     // Initialize the pool with a large amount of capital.
    //     uint256 fixedRate = 0.05e18;
    //     uint256 contribution = 500_000_000e18;
    //     initialize(alice, fixedRate, contribution);

    //     // Open a long position.
    //     uint256 basePaid = 10e18;
    //     (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

    //     // The term passes and the pool accrues negative interest.
    //     int256 apr = 0.5e18;
    //     advanceTime(POSITION_DURATION, apr);

    //     // A checkpoint is created to lock in the close price.
    //     hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);
    //     uint256 closeVaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;

    //     // Another term passes and a large amount of negative interest accrues.
    //     int256 negativeApr = -0.2e18;
    //     advanceTime(POSITION_DURATION, negativeApr);
    //     hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

    //     // Get the reserves and base balances before closing the long.
    //     IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
    //     uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
    //     uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
    //         address(hyperdrive)
    //     );

    //     // Bob redeems the bonds. Ensure that the return value matches the
    //     // amount of base transferred to Bob.
    //     uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

    //     // Bond holders take a proportional haircut on any negative interest
    //     // that accrues.
    //     uint256 bondValue = bondAmount.divDown(closeVaultSharePrice).mulDown(
    //         hyperdrive.getPoolInfo().vaultSharePrice
    //     );

    //     // Calculate the value of the bonds compounded at the negative APR.
    //     (uint256 bondFaceValue, ) = HyperdriveUtils.calculateCompoundInterest(
    //         bondAmount,
    //         negativeApr,
    //         POSITION_DURATION
    //     );

    //     assertApproxEqAbs(baseProceeds, bondValue, 6);
    //     assertApproxEqAbs(bondValue, bondFaceValue, 5);

    //     // Verify that the close long updates were correct.
    //     verifyCloseLong(
    //         TestCase({
    //             poolInfoBefore: poolInfoBefore,
    //             traderBaseBalanceBefore: bobBaseBalanceBefore,
    //             hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
    //             baseProceeds: baseProceeds,
    //             bondAmount: bondAmount,
    //             maturityTime: maturityTime,
    //             wasCheckpointed: true
    //         })
    //     );
    // }

    // // FIXME
    // function test_close_long_after_matured_long() external {
    //     // Initialize the pool with a large amount of capital.
    //     uint256 fixedRate = 0.05e18;
    //     uint256 contribution = 500_000_000e18;
    //     initialize(alice, fixedRate, contribution);

    //     // A large long is opened and held until maturity. This should decrease
    //     // the share adjustment by the long amount.
    //     int256 shareAdjustmentBefore = hyperdrive.getPoolInfo().shareAdjustment;
    //     (, uint256 longAmount) = openLong(
    //         celine,
    //         hyperdrive.calculateMaxLong() / 2
    //     );
    //     advanceTime(hyperdrive.getPoolConfig().positionDuration, 0);
    //     hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);
    //     assertEq(
    //         hyperdrive.getPoolInfo().shareAdjustment,
    //         shareAdjustmentBefore - int256(longAmount)
    //     );

    //     // Bob opens a small long.
    //     uint256 basePaid = 1_000_000e18;
    //     (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

    //     // Celine opens a large short. This will make it harder for Bob to close
    //     // his long (however there should be adequate liquidity left).
    //     openShort(celine, hyperdrive.calculateMaxShort() / 2);

    //     // Bob is able to close his long.
    //     closeLong(bob, maturityTime, bondAmount);
    // }

    // // FIXME
    // //
    // // Test that the close long function works correctly after a matured short
    // // is closed.
    // function test_close_long_after_matured_short() external {
    //     // Initialize the pool with a large amount of capital.
    //     uint256 fixedRate = 0.05e18;
    //     uint256 contribution = 500_000_000e18;
    //     initialize(alice, fixedRate, contribution);

    //     // A large short is opened and held until maturity. This should increase
    //     // the share adjustment by the short amount.
    //     int256 shareAdjustmentBefore = hyperdrive.getPoolInfo().shareAdjustment;
    //     uint256 shortAmount = hyperdrive.calculateMaxShort() / 2;
    //     openShort(celine, shortAmount);
    //     advanceTime(hyperdrive.getPoolConfig().positionDuration, 0);
    //     hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);
    //     assertEq(
    //         hyperdrive.getPoolInfo().shareAdjustment,
    //         shareAdjustmentBefore + int256(shortAmount)
    //     );

    //     // Bob opens a small long.
    //     uint256 basePaid = 1_000_000e18;
    //     (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

    //     // Celine opens a large short. This will make it harder for Bob to close
    //     // his long (however there should be adequate liquidity left).
    //     openShort(celine, hyperdrive.calculateMaxShort() / 2);

    //     // Bob is able to close his long.
    //     closeLong(bob, maturityTime, bondAmount);
    // }

    struct BurnTestCase {
        // Trading metadata.
        address burner;
        address destination;
        uint256 maturityTime;
        uint256 bondAmount;
        bool asBase;
        bytes extraData;
        // The balances before the mint.
        uint256 burnerLongBalanceBefore;
        uint256 burnerShortBalanceBefore;
        uint256 destinationBaseBalanceBefore;
        uint256 hyperdriveBaseBalanceBefore;
        // The state variables before the mint.
        uint256 longsOutstandingBefore;
        uint256 shortsOutstandingBefore;
        uint256 governanceFeesAccruedBefore;
        // Idle, pool depth, and spot price before the mint.
        uint256 idleBefore;
        uint256 kBefore;
        uint256 spotPriceBefore;
        uint256 lpSharePriceBefore;
    }

    /// @dev Creates the test case for the burn transaction.
    /// @param _burner The owner of the bonds to burn.
    /// @param _destination The destination of the proceeds.
    /// @param _maturityTime The maturity time of the bonds to burn.
    /// @param _bondAmount The amount of bonds to burn.
    /// @param _asBase A flag indicating whether or not the deposit is in base
    ///        or vault shares.
    /// @param _extraData The extra data for the transaction.
    function _burnTestCase(
        address _burner,
        address _destination,
        uint256 _maturityTime,
        uint256 _bondAmount,
        bool _asBase,
        bytes memory _extraData
    ) internal view returns (BurnTestCase memory) {
        return
            BurnTestCase({
                // Trading metadata.
                burner: _burner,
                destination: _destination,
                maturityTime: _maturityTime,
                bondAmount: _bondAmount,
                asBase: _asBase,
                extraData: _extraData,
                // The balances before the burn.
                burnerLongBalanceBefore: hyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Long,
                        _maturityTime
                    ),
                    _burner
                ),
                burnerShortBalanceBefore: hyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Short,
                        _maturityTime
                    ),
                    _burner
                ),
                destinationBaseBalanceBefore: baseToken.balanceOf(_destination),
                hyperdriveBaseBalanceBefore: baseToken.balanceOf(
                    address(hyperdrive)
                ),
                // The state variables before the mint.
                longsOutstandingBefore: hyperdrive
                    .getPoolInfo()
                    .longsOutstanding,
                shortsOutstandingBefore: hyperdrive
                    .getPoolInfo()
                    .shortsOutstanding,
                governanceFeesAccruedBefore: hyperdrive
                    .getUncollectedGovernanceFees(),
                // Idle, pool depth, and spot price before the mint.
                idleBefore: hyperdrive.idle(),
                kBefore: hyperdrive.k(),
                spotPriceBefore: hyperdrive.calculateSpotPrice(),
                lpSharePriceBefore: hyperdrive.getPoolInfo().lpSharePrice
            });
    }

    /// @dev Process a burn transaction and verify that the state was updated
    ///      correctly.
    /// @param _testCase The test case for the burn test.
    /// @param _amountPaid The amount paid for the mint.
    function _verifyBurn(
        BurnTestCase memory _testCase,
        uint256 _amountPaid
    ) internal {
        // Before burning the bonds, close the long and short separately using
        // `closeLong` and `closeShort` in a snapshot. The combined proceeds
        // should be approximately equal to the proceeds of the burn.
        uint256 expectedProceeds;
        {
            uint256 snapshotId = vm.snapshot();
            expectedProceeds += closeLong(
                _testCase.burner,
                _testCase.maturityTime,
                _testCase.bondAmount,
                _testCase.asBase
            );
            expectedProceeds += closeShort(
                _testCase.burner,
                _testCase.maturityTime,
                _testCase.bondAmount,
                _testCase.asBase
            );
            vm.revertTo(snapshotId);
        }

        // Ensure that the burner can successfully burn the tokens.
        vm.stopPrank();
        vm.startPrank(_testCase.burner);
        uint256 proceeds = hyperdrive.burn(
            _testCase.maturityTime,
            _testCase.bondAmount,
            0,
            IHyperdrive.Options({
                destination: _testCase.destination,
                asBase: _testCase.asBase,
                extraData: _testCase.extraData
            })
        );

        // If no interest or negative interest accrued, ensure that the proceeds
        // were less than the amount deposited.
        uint256 openVaultSharePrice = hyperdrive
            .getCheckpoint(
                _testCase.maturityTime -
                    hyperdrive.getPoolConfig().positionDuration
            )
            .vaultSharePrice;
        if (hyperdrive.getPoolInfo().vaultSharePrice <= openVaultSharePrice) {
            assertLe(proceeds, _amountPaid);
        }

        // Ensure that the proceeds closely match the expected proceeds. We need
        // to adjust expected proceeds so that the governance fees paid match
        // those paid during the burn. Burning bonds always costs twice the flat
        // governance fee whereas closing positions costs a combination of curve
        // and flat governance fees.
        uint256 governanceFeeAdjustment = 2 *
            _testCase
                .bondAmount
                .mulUp(hyperdrive.getPoolConfig().fees.flat)
                .mulDown(
                    hyperdrive.calculateTimeRemaining(_testCase.maturityTime)
                )
                .mulDown(hyperdrive.getPoolConfig().fees.governanceLP);
        assertApproxEqAbs(
            proceeds + governanceFeeAdjustment,
            expectedProceeds,
            1e10
        );

        // Verify that the balances increased and decreased by the right amounts.
        assertEq(
            baseToken.balanceOf(_testCase.destination),
            _testCase.destinationBaseBalanceBefore + proceeds
        );
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Long,
                    _testCase.maturityTime
                ),
                _testCase.burner
            ),
            _testCase.burnerLongBalanceBefore - _testCase.bondAmount
        );
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    _testCase.maturityTime
                ),
                _testCase.burner
            ),
            _testCase.burnerShortBalanceBefore - _testCase.bondAmount
        );
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            _testCase.hyperdriveBaseBalanceBefore - proceeds
        );

        // Verify that the pool's idle increased by the flat fee minus the
        // governance fees.
        uint256 flatFee = 2 *
            _testCase
                .bondAmount
                .mulUp(hyperdrive.getPoolConfig().fees.flat)
                .mulDown(
                    ONE -
                        hyperdrive.calculateTimeRemaining(
                            _testCase.maturityTime
                        )
                )
                .mulDown(ONE - hyperdrive.getPoolConfig().fees.governanceLP);
        assertApproxEqAbs(
            hyperdrive.idle(),
            _testCase.idleBefore + flatFee,
            10
        );

        // If the flat fee is zero, ensure that the LP share price was unchanged.
        if (flatFee == 0) {
            assertApproxEqAbs(
                hyperdrive.getPoolInfo().lpSharePrice,
                _testCase.lpSharePriceBefore,
                1
            );
        }
        // Otherwise, ensure that the LP share price increased.
        else {
            assertGt(
                hyperdrive.getPoolInfo().lpSharePrice,
                _testCase.lpSharePriceBefore
            );
        }

        // Verify that spot price and pool depth are unchanged.
        assertEq(hyperdrive.calculateSpotPrice(), _testCase.spotPriceBefore);
        assertEq(hyperdrive.k(), _testCase.kBefore);

        // Ensure that the longs outstanding, shorts outstanding, and governance
        // fees accrued decreased by the right amount.
        assertEq(
            hyperdrive.getPoolInfo().longsOutstanding,
            _testCase.longsOutstandingBefore - _testCase.bondAmount
        );
        assertEq(
            hyperdrive.getPoolInfo().shortsOutstanding,
            _testCase.shortsOutstandingBefore - _testCase.bondAmount
        );
        assertEq(
            hyperdrive.getUncollectedGovernanceFees(),
            _testCase.governanceFeesAccruedBefore +
                2 *
                _testCase
                    .bondAmount
                    .mulUp(hyperdrive.getPoolConfig().fees.flat)
                    .mulDivDown(
                        hyperdrive.getPoolConfig().fees.governanceLP,
                        hyperdrive.getPoolInfo().vaultSharePrice
                    )
        );

        // Verify the `Burn` event.
        _verifyBurnEvent(_testCase, proceeds);
    }

    /// @dev Verify the burn event.
    /// @param _testCase The test case containing all of the metadata and data
    ///        relating to the burn transaction.
    /// @param _proceeds The proceeds of burning the bonds.
    function _verifyBurnEvent(
        BurnTestCase memory _testCase,
        uint256 _proceeds
    ) internal {
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            Burn.selector
        );
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(address(uint160(uint256(log.topics[1]))), _testCase.burner);
        assertEq(
            address(uint160(uint256(log.topics[2]))),
            _testCase.destination
        );
        assertEq(uint256(log.topics[3]), _testCase.maturityTime);
        (
            uint256 longAssetId,
            uint256 shortAssetId,
            uint256 amount,
            uint256 vaultSharePrice,
            bool asBase,
            uint256 bondAmount,
            bytes memory extraData
        ) = abi.decode(
                log.data,
                (uint256, uint256, uint256, uint256, bool, uint256, bytes)
            );
        assertEq(
            longAssetId,
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Long,
                _testCase.maturityTime
            )
        );
        assertEq(
            shortAssetId,
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Short,
                _testCase.maturityTime
            )
        );
        assertEq(amount, _proceeds);
        assertEq(vaultSharePrice, hyperdrive.getPoolInfo().vaultSharePrice);
        assertEq(asBase, _testCase.asBase);
        assertEq(bondAmount, _testCase.bondAmount);
        assertEq(extraData, _testCase.extraData);
    }
}
