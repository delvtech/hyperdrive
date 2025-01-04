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

    // FIXME: Figure out why this test is failing.
    //
    /// @dev Ensure that bonds can be burned successfully halfway through the
    ///      term after negative interest accrues.
    function test_burn_halfway_through_term_negative_interest() external {
        // Alice mints a large pair position.
        uint256 amountPaid = 100_000e18;
        (uint256 maturityTime, uint256 bondAmount) = mint(alice, amountPaid);

        // Half of the term passes. A significant amount of negative interest
        // accrues.
        uint256 timeDelta = 0.5e18;
        advanceTime(POSITION_DURATION.mulDown(timeDelta), -0.3e18);

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

    /// @dev Ensure that bonds can be burned successfully at maturity after
    ///      negative interest accrues.
    function test_burn_at_maturity_negative_interest() external {
        // Alice mints a large pair position.
        uint256 amountPaid = 100_000e18;
        (uint256 maturityTime, uint256 bondAmount) = mint(alice, amountPaid);

        // The term passes. A significant amount of negative interest
        // accrues.
        uint256 timeDelta = 1e18;
        advanceTime(POSITION_DURATION.mulDown(timeDelta), -0.3e18);

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

    // FIXME: Figure out why this test is failing.
    //
    /// @dev Ensure that bonds can be burned successfully after maturity after
    ///      negative interest accrues.
    function test_burn_after_maturity_negative_interest() external {
        // Alice mints a large pair position.
        uint256 amountPaid = 100_000e18;
        (uint256 maturityTime, uint256 bondAmount) = mint(alice, amountPaid);

        // Two terms pass. A significant amount of negative interest
        // accrues.
        uint256 timeDelta = 2e18;
        advanceTime(POSITION_DURATION.mulDown(timeDelta), -0.1e18);

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
        uint256 closeVaultSharePrice = block.timestamp < _testCase.maturityTime
            ? hyperdrive.getPoolInfo().vaultSharePrice
            : hyperdrive.getCheckpoint(_testCase.maturityTime).vaultSharePrice;
        uint256 governanceFeeAdjustment = 2 *
            _testCase
                .bondAmount
                .mulUp(hyperdrive.getPoolConfig().fees.flat)
                .mulDown(
                    hyperdrive.calculateTimeRemaining(_testCase.maturityTime)
                )
                .mulDown(hyperdrive.getPoolConfig().fees.governanceLP);
        if (closeVaultSharePrice < openVaultSharePrice) {
            governanceFeeAdjustment = governanceFeeAdjustment.mulDivDown(
                closeVaultSharePrice,
                openVaultSharePrice
            );
        }
        assertApproxEqAbs(
            proceeds + governanceFeeAdjustment,
            expectedProceeds,
            1e10
        );
        console.log("test: 2");

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
        // governance fees. If negative interest accrued, this fee needs to be
        // scaled down in proportion to the negative interest.
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
        if (closeVaultSharePrice < openVaultSharePrice) {
            flatFee = flatFee.mulDivDown(
                closeVaultSharePrice,
                openVaultSharePrice
            );
        }
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

        // Ensure that the longs outstanding and shorts outstanding decreased by
        // the right amount and that governance fees accrued increased by the
        // right amount. If negative interest accrued, scale the governance fee.
        assertEq(
            hyperdrive.getPoolInfo().longsOutstanding,
            _testCase.longsOutstandingBefore - _testCase.bondAmount
        );
        assertEq(
            hyperdrive.getPoolInfo().shortsOutstanding,
            _testCase.shortsOutstandingBefore - _testCase.bondAmount
        );
        uint256 governanceFee = 2 *
            _testCase
                .bondAmount
                .mulUp(hyperdrive.getPoolConfig().fees.flat)
                .mulDivDown(
                    hyperdrive.getPoolConfig().fees.governanceLP,
                    hyperdrive.getPoolInfo().vaultSharePrice
                );
        if (closeVaultSharePrice < openVaultSharePrice) {
            governanceFee = governanceFee.mulDivDown(
                closeVaultSharePrice,
                openVaultSharePrice
            );
        }
        assertEq(
            hyperdrive.getUncollectedGovernanceFees(),
            _testCase.governanceFeesAccruedBefore + governanceFee
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
