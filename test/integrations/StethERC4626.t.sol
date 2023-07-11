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


contract StethERC4626 is ERC4626ValidationTest {
  using FixedPointMath for *;

  function setUp() public override __mainnet_fork(17_059_368) {
    underlyingToken = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    token = IERC4626(0xF9A98A9452485ed55cd3Ce5260C2b71c9807b11a);

    IERC20 steth = underlyingToken;
    IERC4626 stethERC4626 = token;

    alice = createUser("alice");
    bob = createUser("bob");

    vm.startPrank(deployer);

    ERC4626HyperdriveDeployer simpleDeployer = new ERC4626HyperdriveDeployer(
      stethERC4626
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
      stethERC4626
    );

    // Note this is wsteth so it could be somewhat problematic in the future
    address stethWhale = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    whaleTransfer(stethWhale, steth, alice);
   
    IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
      baseToken: underlyingToken,
      initialSharePrice: FixedPointMath.ONE_18.divDown(token.convertToShares(FixedPointMath.ONE_18)),
      positionDuration: POSITION_DURATION,
      checkpointDuration: CHECKPOINT_DURATION,
      timeStretch: FixedPointMath.ONE_18.divDown(
        22.186877016851916266e18
      ),
      governance: governance,
      feeCollector: feeCollector,
      fees: IHyperdrive.Fees({ curve: 0, flat: 0, governance: 0 }),
      oracleSize: ORACLE_SIZE,
      updateGap: UPDATE_GAP
    });

    uint256 contribution = 1_000e18; // Revisit

    vm.stopPrank();
    vm.startPrank(alice);
    underlyingToken.approve(address(factory), type(uint256).max);

    hyperdrive = factory.deployAndInitialize(config,
      new bytes32[](0),
      contribution,
      FIXED_RATE
    );

    steth.approve(address(stethERC4626), type(uint256).max);

    vm.stopPrank();
    vm.startPrank(bob);
    steth.approve(address(hyperdrive), type(uint256).max);
    vm.stopPrank();

    // Start recording events.
    vm.recordLogs(); 
  }

  function advanceTimeWithYield(uint256 timeDelta) override public {
    vm.warp(block.timestamp + timeDelta);
  }
}
