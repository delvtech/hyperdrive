// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract InitializeTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_initialize_failure() external {
        uint256 fixedRate = 0.5e18;
        uint256 contribution = 1000.0e18;

        // Initialize the pool with Alice.
        uint256 lpShares = initialize(alice, fixedRate, contribution);
        verifyInitializeEvent(alice, lpShares, contribution, fixedRate);

        // Alice removes all of her liquidity.
        removeLiquidity(alice, lpShares);

        // Attempt to initialize the pool a second time. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        vm.expectRevert(IHyperdrive.PoolAlreadyInitialized.selector);
        hyperdrive.initialize(
            contribution,
            fixedRate,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_initialize_failure_not_payable() external {
        uint256 fixedRate = 0.5e18;
        uint256 contribution = 1000.0e18;

        // Attempt to initialize the pool. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.initialize{ value: 1 }(
            contribution,
            fixedRate,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_initialize_success(
        uint256 initialSharePrice,
        uint256 checkpointDuration,
        uint256 checkpointsPerTerm,
        uint256 targetRate,
        uint256 contribution
    ) external {
        initialSharePrice = initialSharePrice.normalizeToRange(0.5e18, 5e18);
        checkpointDuration = checkpointDuration.normalizeToRange(1, 24);
        checkpointDuration *= 1 hours;
        checkpointsPerTerm = checkpointsPerTerm.normalizeToRange(7, 2 * 365);
        targetRate = targetRate.normalizeToRange(0.01e18, 1e18);
        contribution = contribution.normalizeToRange(1_000e18, 100_000_000e18);

        // Deploy a Hyperdrive pool with the given parameters.
        IHyperdrive.PoolConfig memory config = testConfig(0.05e18);
        config.initialSharePrice = initialSharePrice;
        config.checkpointDuration = checkpointDuration;
        config.positionDuration = checkpointDuration * checkpointsPerTerm;
        deploy(alice, config);

        // Initialize the pool with Alice.
        uint256 lpShares = initialize(alice, targetRate, contribution);
        verifyInitializeEvent(alice, lpShares, contribution, targetRate);

        // Ensure that the pool's spot rate is approximately equal to the target
        // spot rate.
        uint256 spotRate = hyperdrive.calculateSpotAPR();
        assertApproxEqAbs(spotRate, targetRate, 1e10); // 8 decimals of precision

        // Ensure that Alice's base balance has been depleted and that Alice
        // received the correct amount of LP shares.
        assertEq(baseToken.balanceOf(alice), 0);
        assertEq(baseToken.balanceOf(address(hyperdrive)), contribution);
        assertEq(
            lpShares,
            hyperdrive.getPoolInfo().shareReserves - 2 * MINIMUM_SHARE_RESERVES
        );

        // Ensure that the total supply of LP shares and Alice's balance of LP
        // shares are correct.
        assertEq(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID) -
                MINIMUM_SHARE_RESERVES
        );
        assertEq(lpShares, hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice));
    }

    function verifyInitializeEvent(
        address provider,
        uint256 expectedLpShares,
        uint256 expectedBaseAmount,
        uint256 expectedSpotRate
    ) internal {
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            Initialize.selector
        );
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(address(uint160(uint256(log.topics[1]))), provider);
        (
            uint256 lpShares,
            uint256 baseAmount,
            uint256 sharePrice,
            uint256 spotRate
        ) = abi.decode(log.data, (uint256, uint256, uint256, uint256));
        assertEq(lpShares, expectedLpShares);
        assertEq(baseAmount, expectedBaseAmount);
        assertEq(sharePrice, hyperdrive.getPoolInfo().sharePrice);
        assertEq(spotRate, expectedSpotRate);
    }
}
