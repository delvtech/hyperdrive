// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { AssetId } from "contracts/libraries/AssetId.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
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
        hyperdrive = new MockHyperdrive(
            baseToken,
            FixedPointMath.ONE_18,
            365 days,
            1 days,
            22.186877016851916266e18
        );
    }

    /// Initialize ///

    // FIXME: It would be good to fuzz this. We should also try this with
    // different values for initial share price and share price.
    function test_initialization_success() external {
        // Initialize Hyperdrive.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 contribution = 1000.0e18;
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        uint256 apr = 0.5e18;
        hyperdrive.initialize(contribution, apr);

        // Ensure that the pool's APR is approximately equal to the target APR
        // within 3 decimals of precision.
        uint256 poolApr = HyperdriveMath.calculateAPRFromReserves(
            hyperdrive.shareReserves(),
            hyperdrive.bondReserves(),
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
            hyperdrive.initialSharePrice(),
            hyperdrive.positionDuration(),
            hyperdrive.timeStretch()
        );
        assertApproxEqAbs(poolApr, apr, 1.0e3);

        // Ensure that Alice's base balance has been depleted and that Alice
        // received some LP tokens.
        assertEq(baseToken.balanceOf(alice), 0);
        assertEq(
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
            contribution.divDown(hyperdrive.getSharePrice())
        );
    }

    function test_initialization_failure() external {
        // Initialize the pool with Alice.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 apr = 0.5e18;
        uint256 contribution = 1000.0e18;
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        hyperdrive.initialize(contribution, apr);

        // Attempt to initialize the pool a second time. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        vm.expectRevert(Errors.PoolAlreadyInitialized.selector);
        hyperdrive.initialize(contribution, apr);
    }
}
