// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { ERC4626HyperdriveDeployer } from "contracts/src/factory/ERC4626HyperdriveDeployer.sol";
import { ERC4626HyperdriveFactory } from "contracts/src/factory/ERC4626HyperdriveFactory.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { MockERC4626Hyperdrive } from "../mocks/Mock4626Hyperdrive.sol";
import { HyperdriveUtils } from "../utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";
import { ERC4626ValidationTest } from "./ERC4626Validation.t.sol";

// Interface for the `Pot` of the underlying DSR
interface PotLike {
    function rho() external view returns (uint256);

    function dsr() external view returns (uint256);

    function drip() external returns (uint256);
}

contract sDaiTest is ERC4626ValidationTest {
    using FixedPointMath for *;

    function setUp() public override __mainnet_fork(17_318_972) {
        super.setUp();

        underlyingToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        token = IERC4626(0x83F20F44975D03b1b09e64809B757c47f942BEeA);

        IERC20 dai = underlyingToken;
        IERC4626 sDai = token;

        vm.startPrank(deployer);

        ERC4626HyperdriveDeployer simpleDeployer = new ERC4626HyperdriveDeployer(
                sDai
            );

        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ForwarderFactory();
        // New hyperdrive factory for sDai instances
        factory = new ERC4626HyperdriveFactory(
            alice,
            simpleDeployer,
            bob,
            bob,
            IHyperdrive.Fees(0, 0, 0),
            defaults,
            address(forwarderFactory),
            forwarderFactory.ERC20LINK_HASH(),
            token
        );

        // Fund alice with DAI
        address daiWhale = 0x60FaAe176336dAb62e284Fe19B885B095d29fB7F;
        whaleTransfer(daiWhale, dai, alice);

        IHyperdrive.PoolConfig memory config = testConfig(FIXED_RATE);
        // Config changes required from default for ERC4626 support
        config.baseToken = underlyingToken;
        config.initialSharePrice = FixedPointMath.ONE_18.divDown(
            token.convertToShares(FixedPointMath.ONE_18)
        );

        uint256 contribution = 10_000e18;

        vm.stopPrank();
        vm.startPrank(alice);
        underlyingToken.approve(address(factory), type(uint256).max);

        // Deploy and set the global hyperdrive instance
        hyperdrive = factory.deployAndInitialize(
            config,
            new bytes32[](0),
            contribution,
            FIXED_RATE
        );

        dai.approve(address(hyperdrive), type(uint256).max);
        dai.approve(address(sDai), type(uint256).max);

        vm.stopPrank();
        vm.startPrank(bob);
        dai.approve(address(hyperdrive), type(uint256).max);
        vm.stopPrank();

        // Start recording events.
        vm.recordLogs();
    }

    function advanceTimeWithYield(uint256 timeDelta) public override {
        vm.warp(block.timestamp + timeDelta);
        // Interest accumulates in the dsr based on time passed.
        // This may caused insolvency in excess as no real dai is being 
        // accrued.

        // Note - Mainnet only address for Pot, but fine since this test explicitly uses a Mainnet fork in test
        PotLike(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7).drip();
    }
}
