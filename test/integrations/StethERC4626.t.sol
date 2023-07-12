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
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { ERC4626ValidationTest } from "./ERC4626Validation.t.sol"; 

contract StethERC4626 is ERC4626ValidationTest {
  using FixedPointMath for *;

  function setUp() public override __mainnet_fork(17_376_154) {
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
   
    IHyperdrive.PoolConfig memory config = testConfig(FIXED_RATE);
    config.baseToken = underlyingToken;
    config.initialSharePrice = FixedPointMath.ONE_18.divDown(token.convertToShares(FixedPointMath.ONE_18));

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

    // The Lido storage location that tracks buffered ether reserves. We can
    // simulate the accrual of interest by updating this value.
    bytes32 BUFFERED_ETHER_POSITION =
        keccak256("lido.Lido.bufferedEther");

    ILido LIDO =
        ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    uint256 variableRate = 1.5e18;

    // Accrue interest in Lido. Since the share price is given by
    // `getTotalPooledEther() / getTotalShares()`, we can simulate the
    // accrual of interest by multiplying the total pooled ether by the
    // variable rate plus one.
    uint256 bufferedEther = variableRate >= 0
      ? LIDO.getBufferedEther() +
        LIDO.getTotalPooledEther().mulDown(uint256(variableRate))
      : LIDO.getBufferedEther() -
        LIDO.getTotalPooledEther().mulDown(uint256(variableRate));
   
    vm.store(
      address(LIDO),
      BUFFERED_ETHER_POSITION,
      bytes32(bufferedEther)
    );
  }
}
