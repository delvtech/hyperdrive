// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626HyperdriveDeployer } from "contracts/src/factory/ERC4626HyperdriveDeployer.sol";
import { ERC4626HyperdriveFactory } from "contracts/src/factory/ERC4626HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { MockERC4626Hyperdrive } from "contracts/test/MockERC4626Hyperdrive.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";
import { ERC4626ValidationTest } from "test/integrations/ERC4626Validation.t.sol";

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

        // Fund alice with DAI
        address daiWhale = 0x60FaAe176336dAb62e284Fe19B885B095d29fB7F;
        whaleTransfer(daiWhale, dai, alice);

        _setUp();
    }

    function advanceTimeWithYield(
        uint256 timeDelta,
        int256 // unused
    ) public override {
        vm.warp(block.timestamp + timeDelta);
        // Interest accumulates in the dsr based on time passed.
        // This may caused insolvency if too much interest accrues as no real dai is being
        // accrued.

        // Note - Mainnet only address for Pot, but fine since this test explicitly uses a Mainnet fork in test
        PotLike(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7).drip();
    }
}
