// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { AaveV3ERC4626Factory, IPool, IRewardsController, ERC20 } from "yield-daddy/src/aave-v3/AaveV3ERC4626Factory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { ERC4626ValidationTest } from "./ERC4626Validation.t.sol";

contract AaveV3ERC4626Test is ERC4626ValidationTest {
    function setUp() public override __mainnet_fork(17_318_972) {
        super.setUp();

        // Aave v3 Lending Pool Contract
        IPool pool = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
        AaveV3ERC4626Factory yieldDaddyFactory = new AaveV3ERC4626Factory(
            pool,
            address(0),
            IRewardsController(address(0))
        );

        // Dai is the underlying token used for Aave instances
        ERC20 dai = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

        // Deploy a new instance of an Aave v3 ERC4626 token, for aDai
        token = IERC4626(address(yieldDaddyFactory.createERC4626(dai)));
        underlyingToken = IERC20(address(dai));

        // Alice account must be prefunded with lots of the underlyingToken.
        address daiWhale = 0x60FaAe176336dAb62e284Fe19B885B095d29fB7F;
        whaleTransfer(daiWhale, IERC20(address(dai)), alice);

        _setUp();
    }

    function advanceTimeWithYield(
        uint256 timeDelta,
        int256 // unused
    ) public override {
        // Aave derives interest based on time, so all we need
        // to do is advance the block timestamp.
        vm.warp(block.timestamp + timeDelta);
    }
}
