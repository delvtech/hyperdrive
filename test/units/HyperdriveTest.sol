// SPDX-License-Identifier: Apache-2.0

import { Test } from "forge-std/Test.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "test/mocks/ERC20Mintable.sol";
import { MockHyperdrive } from "test/mocks/MockHyperdrive.sol";

contract HyperdriveTest is Test {
    using FixedPointMath for uint256;

    address alice = address(uint160(uint256(keccak256("alice"))));
    address bob = address(uint160(uint256(keccak256("bob"))));

    ERC20Mintable baseToken;
    MockHyperdrive hyperdrive;

    function setUp() public {
        vm.startPrank(alice);

        // Instantiate the base token.
        baseToken = new ERC20Mintable();

        // Instantiate Hyperdrive.
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            22.186877016851916266e18
        );
        hyperdrive = new MockHyperdrive(
            baseToken,
            FixedPointMath.ONE_18,
            365,
            1 days,
            timeStretch
        );

        // Advance time so that Hyperdrive can look back more than a position
        // duration.
        vm.warp(365 days * 3);
    }

    function initialize(
        address lp,
        uint256 apr,
        uint256 contribution
    ) internal {
        vm.stopPrank();
        vm.startPrank(lp);

        // Initialize the pool.
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        hyperdrive.initialize(contribution, apr, lp);
    }

    struct PoolInfo {
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 lpTotalSupply;
        uint256 sharePrice;
        uint256 longsOutstanding;
        uint256 longAverageMaturityTime;
        uint256 longBaseVolume;
        uint256 shortsOutstanding;
        uint256 shortAverageMaturityTime;
        uint256 shortBaseVolume;
    }

    function getPoolInfo() internal view returns (PoolInfo memory) {
        (
            uint256 shareReserves,
            uint256 bondReserves,
            uint256 lpTotalSupply,
            uint256 sharePrice,
            uint256 longsOutstanding,
            uint256 longAverageMaturityTime,
            uint256 longBaseVolume,
            uint256 shortsOutstanding,
            uint256 shortAverageMaturityTime,
            uint256 shortBaseVolume
        ) = hyperdrive.getPoolInfo();
        return
            PoolInfo({
                shareReserves: shareReserves,
                bondReserves: bondReserves,
                lpTotalSupply: lpTotalSupply,
                sharePrice: sharePrice,
                longsOutstanding: longsOutstanding,
                longAverageMaturityTime: longAverageMaturityTime,
                longBaseVolume: longBaseVolume,
                shortsOutstanding: shortsOutstanding,
                shortAverageMaturityTime: shortAverageMaturityTime,
                shortBaseVolume: shortBaseVolume
            });
    }

    function calculateAPRFromRealizedPrice(
        uint256 baseAmount,
        uint256 bondAmount,
        uint256 timeRemaining,
        uint256 positionDuration
    ) internal pure returns (uint256) {
        // apr = (dy - dx) / (dx * t)
        uint256 t = timeRemaining.divDown(positionDuration);
        return (bondAmount.sub(baseAmount)).divDown(baseAmount.mulDown(t));
    }
}
