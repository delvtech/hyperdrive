// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../../contracts/src/interfaces/IHyperdriveAdminController.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";
import { MockHyperdrive, MockHyperdriveTarget0, MockHyperdriveTarget1 } from "../../../contracts/test/MockHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract UpdateLiquidityTest is HyperdriveTest {
    using FixedPointMath for *;
    using HyperdriveUtils for *;
    using Lib for *;

    MockHyperdrive mockHyperdrive;

    function setUp() public override {
        super.setUp();

        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        config.baseToken = IERC20(
            address(
                new ERC20Mintable(
                    "Base",
                    "BASE",
                    18,
                    address(0),
                    false,
                    type(uint256).max
                )
            )
        );
        config.minimumShareReserves = 1e15;
        mockHyperdrive = new MockHyperdrive(config, adminController);
        hyperdrive = IHyperdrive(address(mockHyperdrive));
    }

    function test__updateLiquidity__zeroDelta(
        uint128 _shareReserves,
        uint128 _bondReserves
    ) external {
        // Set the reserves to random values.
        mockHyperdrive.setReserves(_shareReserves, _bondReserves);

        // Update the liquidity.
        mockHyperdrive.updateLiquidity(0);

        // Check that the reserves are unchanged.
        assertEq(hyperdrive.getPoolInfo().shareReserves, _shareReserves);
        assertEq(hyperdrive.getPoolInfo().bondReserves, _bondReserves);
    }

    function test__updateLiquidity__insufficientEndingShareReserves(
        uint256 _shareReserves,
        uint256 _bondReserves,
        int256 _shareReservesDelta
    ) external {
        // Set the reserves to random values. The share reserves are set to
        // greater than or equal the minimum share reserves.
        _shareReserves = _shareReserves.normalizeToRange(
            hyperdrive.getPoolConfig().minimumShareReserves,
            type(uint128).max
        );
        mockHyperdrive.setReserves(
            uint128(_shareReserves),
            uint128(_bondReserves)
        );

        // Update the liquidity. The share reserves delta is sampled so that
        // the ending share reserves are less than the minimum share reserves,
        // so we expect this to fail.
        // NOTE: We sample starting at the minimum int248 value to avoid
        // underflows when sampling.
        _shareReservesDelta = _shareReservesDelta.normalizeToRange(
            type(int248).min,
            int256(hyperdrive.getPoolConfig().minimumShareReserves) -
                int256(_shareReserves) -
                int256(1)
        );
        vm.expectRevert(IHyperdrive.UpdateLiquidityFailed.selector);
        mockHyperdrive.updateLiquidity(_shareReservesDelta);
    }

    function test__updateLiquidity__excessiveEndingShareReserves(
        uint256 _shareReserves,
        uint256 _bondReserves,
        int256 _shareReservesDelta
    ) external {
        // Set the reserves to random values. The share reserves are set to
        // greater than or equal the minimum share reserves.
        _shareReserves = _shareReserves.normalizeToRange(
            hyperdrive.getPoolConfig().minimumShareReserves,
            type(uint128).max
        );
        mockHyperdrive.setReserves(
            uint128(_shareReserves),
            uint128(_bondReserves)
        );

        // Update the liquidity. The share reserves delta is sampled so that
        // the ending share reserves are greater than the max uint128.
        _shareReservesDelta = _shareReservesDelta.normalizeToRange(
            int256(uint256(type(uint128).max)) - int256(_shareReserves) + 1,
            type(int256).max - int256(_shareReserves)
        );
        vm.expectRevert();
        mockHyperdrive.updateLiquidity(_shareReservesDelta);
    }

    function test__updateLiquidity__excessiveEndingBondReserves(
        uint256 _shareReserves,
        uint256 _bondReserves,
        int256 _shareReservesDelta
    ) external {
        // Set the reserves to random values. The share reserves are less than
        // 1e18 and the bond reserves are greater than type(uint128).max / 2.
        _shareReserves = _shareReserves.normalizeToRange(
            hyperdrive.getPoolConfig().minimumShareReserves,
            1e18 - 1
        );
        _bondReserves = _bondReserves.normalizeToRange(
            type(uint128).max / 2 + 1,
            type(uint128).max
        );
        mockHyperdrive.setReserves(
            uint128(_shareReserves),
            uint128(_bondReserves)
        );

        // Update the liquidity. The share reserves delta is greater than 2e18.
        _shareReservesDelta = _shareReservesDelta.normalizeToRange(
            2e18,
            type(int128).max
        );
        vm.expectRevert();
        mockHyperdrive.updateLiquidity(_shareReservesDelta);
    }

    function test__updateLiquidity__success(
        uint256 _shareReserves,
        uint256 _bondReserves,
        int256 _shareReservesDelta
    ) external {
        // Set the reserves to random values. The share reserves and bond
        // reserves are set to reasonable values for the 18 decimal scale.
        _shareReserves = _shareReserves.normalizeToRange(0.1e18, 1_000_000e18);
        _bondReserves = _bondReserves.normalizeToRange(
            _shareReserves,
            _shareReserves.mulDown(1_000e18)
        );
        mockHyperdrive.setReserves(
            uint128(_shareReserves),
            uint128(_bondReserves)
        );

        // Update the liquidity. The share reserves delta is sampled to avoid
        // overflows.
        uint256 startingSpotPrice = hyperdrive.calculateSpotPrice();
        _shareReservesDelta = _shareReservesDelta.normalizeToRange(
            int256(hyperdrive.getPoolConfig().minimumShareReserves) -
                int256(_shareReserves),
            int256(
                type(uint128).max.mulDivDown(_shareReserves, _bondReserves)
            ) / 2
        );
        mockHyperdrive.updateLiquidity(_shareReservesDelta);

        // Ensure that the ending spot price is approximately equal to the
        // starting spot price.
        uint256 endingSpotPrice = hyperdrive.calculateSpotPrice();
        assertApproxEqAbs(startingSpotPrice, endingSpotPrice, 1e3);

        // Ensure that the share reserves were updated correctly.
        uint256 expectedShareReserves = uint256(
            int256(_shareReserves) + _shareReservesDelta
        );
        assertEq(hyperdrive.getPoolInfo().shareReserves, expectedShareReserves);
        assertEq(
            hyperdrive.getPoolInfo().bondReserves,
            _bondReserves.mulDivDown(expectedShareReserves, _shareReserves)
        );
    }
}
