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

import { AaveV3ERC4626Factory, IPool, IRewardsController, ERC20 } from "yield-daddy/src/aave-v3/AaveV3ERC4626Factory.sol";

contract AaveV3ERC4626Test is ERC4626ValidationTest {
  using FixedPointMath for uint256;

  function setUp() public override __mainnet_fork(17_318_972) {
    IPool pool = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    AaveV3ERC4626Factory yieldDaddyFactory = new AaveV3ERC4626Factory(pool, address(0), IRewardsController(address(0)));
    ERC20 dai = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    token = IERC4626(address(yieldDaddyFactory.createERC4626(dai)));
    underlyingToken = IERC20(address(dai));

    alice = createUser("alice");
    bob = createUser("bob");

    vm.startPrank(deployer);

    ERC4626HyperdriveDeployer simpleDeployer = new ERC4626HyperdriveDeployer(
      token
    );

    address[] memory defaults = new address[](1);
    defaults[0] = bob;
    forwarderFactory = new ForwarderFactory();
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

    address daiWhale = 0x60FaAe176336dAb62e284Fe19B885B095d29fB7F;
    whaleTransfer(daiWhale, IERC20(address(dai)), alice);

    IHyperdrive.PoolConfig memory config = testConfig(FIXED_RATE);
    config.baseToken = underlyingToken;
    config.initialSharePrice = FixedPointMath.ONE_18.divDown(token.convertToShares(FixedPointMath.ONE_18));

    uint256 contribution = 10_000e18; // Revisit

    vm.stopPrank();
    vm.startPrank(alice);
    underlyingToken.approve(address(factory), type(uint256).max);

    hyperdrive = factory.deployAndInitialize(config,
      new bytes32[](0),
      contribution,
      FIXED_RATE
    );

    dai.approve(address(hyperdriveInstance), type(uint256).max);
    dai.approve(address(underlyingToken), type(uint256).max);

    vm.stopPrank();
    vm.startPrank(bob);
    dai.approve(address(hyperdriveInstance), type(uint256).max);
    vm.stopPrank();

    // Start recording events.
    vm.recordLogs();
  } 

  function advanceTimeWithYield(uint256 timeDelta) override public {
    vm.warp(block.timestamp + timeDelta);
  }
}
