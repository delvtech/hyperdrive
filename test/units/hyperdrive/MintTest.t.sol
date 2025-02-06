// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

/// @dev A test suite for the mint function.
contract MintTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    /// @dev Sets up the harness and deploys and initializes a pool with fees.
    function setUp() public override {
        // Run the higher level setup function.
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();

        // Deploy and initialize a pool with fees.
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        config.fees.curve = 0.01e18;
        config.fees.flat = 0.0005e18;
        config.fees.governanceLP = 0.15e18;
        deploy(alice, config);
        initialize(alice, 0.05e18, 100_000e18);
    }

    /// @dev Ensures that minting fails when the amount is zero.
    function test_mint_failure_zero_amount() external {
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.MinimumTransactionAmount.selector);
        hyperdrive.mint(
            0,
            0,
            0,
            IHyperdrive.PairOptions({
                longDestination: bob,
                shortDestination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that minting fails when the vault share price is lower than
    ///      the minimum vault share price.
    function test_mint_failure_minVaultSharePrice() external {
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 basePaid = 10e18;
        baseToken.mint(bob, basePaid);
        baseToken.approve(address(hyperdrive), basePaid);
        uint256 minVaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice *
            2;
        vm.expectRevert(IHyperdrive.MinimumSharePrice.selector);
        hyperdrive.mint(
            basePaid,
            0,
            minVaultSharePrice,
            IHyperdrive.PairOptions({
                longDestination: bob,
                shortDestination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that minting fails when the bond proceeds is lower than
    ///      the minimum output.
    function test_mint_failure_minOutput() external {
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 basePaid = 10e18;
        baseToken.mint(bob, basePaid);
        baseToken.approve(address(hyperdrive), basePaid);
        uint256 minOutput = 15e18;
        vm.expectRevert(IHyperdrive.OutputLimit.selector);
        hyperdrive.mint(
            basePaid,
            minOutput,
            0,
            IHyperdrive.PairOptions({
                longDestination: bob,
                shortDestination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that minting fails when ether is sent to the contract.
    function test_mint_failure_not_payable() external {
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 basePaid = 10e18;
        baseToken.mint(bob, basePaid);
        baseToken.approve(address(hyperdrive), basePaid);
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.mint{ value: 1 }(
            basePaid,
            0,
            0,
            IHyperdrive.PairOptions({
                longDestination: bob,
                shortDestination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that minting fails when the long destination is the zero
    ///      address.
    function test_mint_failure_long_destination_zero_address() external {
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 basePaid = 10e18;
        baseToken.mint(bob, basePaid);
        baseToken.approve(address(hyperdrive), basePaid);
        vm.expectRevert(IHyperdrive.RestrictedZeroAddress.selector);
        hyperdrive.mint(
            basePaid,
            0,
            0,
            IHyperdrive.PairOptions({
                longDestination: address(0),
                shortDestination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that minting fails when the short destination is the zero
    ///      address.
    function test_mint_failure_short_destination_zero_address() external {
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 basePaid = 10e18;
        baseToken.mint(bob, basePaid);
        baseToken.approve(address(hyperdrive), basePaid);
        vm.expectRevert(IHyperdrive.RestrictedZeroAddress.selector);
        hyperdrive.mint(
            basePaid,
            0,
            0,
            IHyperdrive.PairOptions({
                longDestination: bob,
                shortDestination: address(0),
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that minting fails when the pool is paused.
    function test_mint_failure_pause() external {
        pause(true);
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 basePaid = 10e18;
        baseToken.mint(bob, basePaid);
        baseToken.approve(address(hyperdrive), basePaid);
        vm.expectRevert(IHyperdrive.PoolIsPaused.selector);
        hyperdrive.mint(
            basePaid,
            0,
            0,
            IHyperdrive.PairOptions({
                longDestination: bob,
                shortDestination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
        pause(false);
    }

    /// @dev Ensures that minting performs correctly when it succeeds.
    function test_mint_success() external {
        // Mint some base tokens to Alice and approve Hyperdrive.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 baseAmount = 100_000e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);

        // Get some data before minting.
        MintTestCase memory testCase = _mintTestCase(
            alice, // funder
            bob, // long
            celine, // short
            baseAmount, // amount
            true, // asBase
            "" // extraData
        );

        // Verify the mint transaction.
        _verifyMint(testCase);
    }

    /// @dev Ensures that minting performs correctly when there is prepaid
    ///      interest.
    function test_mint_success_prepaid_interest() external {
        // Mint some base tokens to Alice and approve Hyperdrive.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 baseAmount = 100_000e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);

        // Mint a checkpoint and accrue interest. This sets us up to have
        // prepaid interest to account for.
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);
        advanceTime(CHECKPOINT_DURATION.mulDown(0.5e18), 2.5e18);

        // Get some data before minting.
        MintTestCase memory testCase = _mintTestCase(
            alice, // funder
            bob, // long
            celine, // short
            baseAmount, // amount
            true, // asBase
            "" // extraData
        );

        // Verify the mint transaction.
        _verifyMint(testCase);
    }

    /// @dev Ensures that minting performs correctly when negative interest
    ///      accrues.
    function test_mint_success_negative_interest() external {
        // Mint some base tokens to Alice and approve Hyperdrive.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 baseAmount = 100_000e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);

        // Mint a checkpoint and accrue interest. This sets us up to have
        // prepaid interest to account for.
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);
        advanceTime(CHECKPOINT_DURATION.mulDown(0.5e18), -0.2e18);

        // Get some data before minting.
        MintTestCase memory testCase = _mintTestCase(
            alice, // funder
            bob, // long
            celine, // short
            baseAmount, // amount
            true, // asBase
            "" // extraData
        );

        // Verify the mint transaction.
        _verifyMint(testCase);
    }

    struct MintTestCase {
        // Trading metadata.
        address funder;
        address long;
        address short;
        uint256 maturityTime;
        uint256 amount;
        bool asBase;
        bytes extraData;
        // The balances before the mint.
        uint256 funderBaseBalanceBefore;
        uint256 hyperdriveBaseBalanceBefore;
        uint256 longBalanceBefore;
        uint256 shortBalanceBefore;
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

    /// @dev Creates the test case for the mint transaction.
    /// @param _funder The funder of the mint.
    /// @param _long The long destination.
    /// @param _short The short destination.
    /// @param _amount The amount of base or vault shares to deposit.
    /// @param _asBase A flag indicating whether or not the deposit is in base
    ///        or vault shares.
    /// @param _extraData The extra data for the transaction.
    function _mintTestCase(
        address _funder,
        address _long,
        address _short,
        uint256 _amount,
        bool _asBase,
        bytes memory _extraData
    ) internal view returns (MintTestCase memory) {
        uint256 maturityTime = hyperdrive.latestCheckpoint() +
            hyperdrive.getPoolConfig().positionDuration;
        return
            MintTestCase({
                // Trading metadata.
                funder: _funder,
                long: _long,
                short: _short,
                maturityTime: maturityTime,
                amount: _amount,
                asBase: _asBase,
                extraData: _extraData,
                // The balances before the mint.
                funderBaseBalanceBefore: baseToken.balanceOf(_funder),
                hyperdriveBaseBalanceBefore: baseToken.balanceOf(
                    address(hyperdrive)
                ),
                longBalanceBefore: hyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Long,
                        maturityTime
                    ),
                    _long
                ),
                shortBalanceBefore: hyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Short,
                        maturityTime
                    ),
                    _short
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

    /// @dev Process a mint transaction and verify that the state was updated
    ///      correctly.
    /// @param _testCase The test case for the mint test.
    function _verifyMint(MintTestCase memory _testCase) internal {
        // Ensure that Alice can successfully mint.
        vm.stopPrank();
        vm.startPrank(alice);
        (uint256 maturityTime, uint256 bondAmount) = hyperdrive.mint(
            _testCase.amount,
            0,
            0,
            IHyperdrive.PairOptions({
                longDestination: _testCase.long,
                shortDestination: _testCase.short,
                asBase: _testCase.asBase,
                extraData: _testCase.extraData
            })
        );
        assertEq(maturityTime, _testCase.maturityTime);

        // Verify that the balances increased and decreased by the right amounts.
        assertEq(
            baseToken.balanceOf(_testCase.funder),
            _testCase.funderBaseBalanceBefore - _testCase.amount
        );
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Long,
                    _testCase.maturityTime
                ),
                _testCase.long
            ),
            _testCase.longBalanceBefore + bondAmount
        );
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    _testCase.maturityTime
                ),
                _testCase.short
            ),
            _testCase.shortBalanceBefore + bondAmount
        );
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            _testCase.hyperdriveBaseBalanceBefore + _testCase.amount
        );

        // Verify that idle, spot price, LP share price, and pool depth are all
        // unchanged.
        assertEq(hyperdrive.idle(), _testCase.idleBefore);
        assertEq(hyperdrive.calculateSpotPrice(), _testCase.spotPriceBefore);
        assertEq(hyperdrive.k(), _testCase.kBefore);
        assertEq(
            hyperdrive.getPoolInfo().lpSharePrice,
            _testCase.lpSharePriceBefore
        );

        // Ensure that the longs outstanding, shorts outstanding, and governance
        // fees accrued increased by the right amount.
        assertEq(
            hyperdrive.getPoolInfo().longsOutstanding,
            _testCase.longsOutstandingBefore + bondAmount
        );
        assertEq(
            hyperdrive.getPoolInfo().shortsOutstanding,
            _testCase.shortsOutstandingBefore + bondAmount
        );
        assertEq(
            hyperdrive.getUncollectedGovernanceFees(),
            _testCase.governanceFeesAccruedBefore +
                2 *
                bondAmount
                    .mulUp(hyperdrive.getPoolConfig().fees.flat)
                    .mulDivDown(
                        hyperdrive.getPoolConfig().fees.governanceLP,
                        hyperdrive.getPoolInfo().vaultSharePrice
                    )
        );

        // Ensure that the base amount is the bond amount plus the prepaid
        // variable interest plus the governance fees plus the prepaid flat fee.
        uint256 openVaultSharePrice = hyperdrive
            .getCheckpoint(hyperdrive.latestCheckpoint())
            .vaultSharePrice;
        uint256 requiredBaseAmount = bondAmount +
            bondAmount.mulDivDown(
                hyperdrive.getPoolInfo().vaultSharePrice -
                    openVaultSharePrice.min(
                        hyperdrive.getPoolInfo().vaultSharePrice
                    ),
                openVaultSharePrice
            ) +
            bondAmount.mulDown(hyperdrive.getPoolConfig().fees.flat) +
            2 *
            bondAmount.mulDown(hyperdrive.getPoolConfig().fees.flat).mulDown(
                hyperdrive.getPoolConfig().fees.governanceLP
            );
        assertGt(_testCase.amount, requiredBaseAmount);
        assertApproxEqAbs(_testCase.amount, requiredBaseAmount, 1e6);

        // Verify the `Mint` event.
        _verifyMintEvent(_testCase, bondAmount);
    }

    /// @dev Verify the mint event.
    /// @param _testCase The test case containing all of the metadata and data
    ///        relating to the mint transaction.
    /// @param _bondAmount The amount of bonds that were minted.
    function _verifyMintEvent(
        MintTestCase memory _testCase,
        uint256 _bondAmount
    ) internal {
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            MintBonds.selector
        );
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(address(uint160(uint256(log.topics[1]))), _testCase.long);
        assertEq(address(uint160(uint256(log.topics[2]))), _testCase.short);
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
        assertEq(amount, _testCase.amount);
        assertEq(vaultSharePrice, hyperdrive.getPoolInfo().vaultSharePrice);
        assertEq(asBase, _testCase.asBase);
        assertEq(bondAmount, _bondAmount);
        assertEq(extraData, _testCase.extraData);
    }
}
