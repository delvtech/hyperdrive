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
import { console } from "forge-std/console.sol";

abstract contract ERC4626ValidationTest is HyperdriveTest {
  using FixedPointMath for *;
  using Lib for *;

  ERC4626HyperdriveFactory internal factory;
  IERC20 internal underlyingToken;
  IERC4626 internal token;
  MockERC4626Hyperdrive hyperdriveInstance;

  uint256 internal constant FIXED_RATE = 0.05e18;

  function advanceTimeWithYield(uint256 timeDelta) virtual public;

  function test_deployAndInitialize() external {
    vm.startPrank(alice);
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

    uint256 contribution = 10_000e18; // Revisit

    underlyingToken.approve(address(factory), type(uint256).max);

    hyperdrive = factory.deployAndInitialize(config,
      new bytes32[](0),
      contribution,
      FIXED_RATE
    );

    assertEq(
        hyperdrive.getPoolInfo().lpTotalSupply,
        hyperdrive.getPoolInfo().shareReserves
    );

    // Verify that the correct events were emitted.
    verifyFactoryEvents(
      factory,
      alice,
      contribution - 1e5,
      FIXED_RATE,
      new bytes32[](0)
    );
  }
  
  function test_OpenLongWithUnderlying(uint256 basePaid) external {
    vm.startPrank(alice);  
    basePaid = basePaid.normalizeToRange(
      0.00001e18,
      min(HyperdriveUtils.calculateMaxLong(hyperdrive), underlyingToken.balanceOf(alice))
    );

    openLongERC4626(alice, basePaid, true);

    // TODO: Add assertions
  } 
 
  /* Q: Are these tests needed? Steth mainly had them to ensure payable logic worked correctly
  function test_OpenLongFails() external {
    // alice is expected to have all the WANT tokens
    vm.startPrank(bob);
    vm.expectRevert(IHyperdrive.TransferFailed.selector);
    hyperdrive.openLong(1e18, 0, bob, true);
  } */
  
  function test_OpenLongWithToken(uint256 basePaid) external {
    vm.startPrank(alice);  
    basePaid = basePaid.normalizeToRange(
      0.00001e18,
      min(HyperdriveUtils.calculateMaxLong(hyperdrive), underlyingToken.balanceOf(alice))
    );
    underlyingToken.approve(address(token), type(uint256).max);
    token.deposit(basePaid, alice);

    openLongERC4626(alice, basePaid, false);
  }
  
  
  function test_CloseLongWithUnderlying(uint256 basePaid) external {
      vm.startPrank(alice);
      // Alice opens a long.
      basePaid = basePaid.normalizeToRange(
          0.00001e18,
          min(HyperdriveUtils.calculateMaxLong(hyperdrive), underlyingToken.balanceOf(alice))
      );
      (uint256 maturityTime, uint256 longAmount) = openLongERC4626(alice, basePaid, true);

      hyperdrive.closeLong(maturityTime, longAmount, 0, alice, true);
  }
  
  function test_CloseLongWithToken(uint256 basePaid) external {
      vm.startPrank(alice);
      // Alice opens a long.
      basePaid = basePaid.normalizeToRange(
          0.00001e18,
          min(HyperdriveUtils.calculateMaxLong(hyperdrive), underlyingToken.balanceOf(alice))
      );
      (uint256 maturityTime, uint256 longAmount) = openLongERC4626(alice, basePaid, true);

      hyperdrive.closeLong(maturityTime, longAmount, 0, alice, false);
  }
  

  function test_OpenShortWithUnderlying() external {
    vm.startPrank(alice);
    uint256 shortAmount = 0.001e18;
    shortAmount = shortAmount.normalizeToRange(
      0.00001e18,
      min(HyperdriveUtils.calculateMaxShort(hyperdrive), underlyingToken.balanceOf(alice))
    );

    (uint256 maturityTime, ) = openShortERC4626(alice, shortAmount, true);
  }
  
  function test_OpenShortWithToken(uint256 shortAmount) external {
    vm.startPrank(alice);
    shortAmount = shortAmount.normalizeToRange(
      0.00001e18,
      min(HyperdriveUtils.calculateMaxShort(hyperdrive), underlyingToken.balanceOf(alice))
    );

    underlyingToken.approve(address(token), type(uint256).max);
    token.deposit(shortAmount, alice);
    openShortERC4626(alice, shortAmount, false);
  }
  
  function test_CloseShortWithUnderlying(uint256 shortAmount, int256 variableRate) external {
    vm.startPrank(alice);
    shortAmount = shortAmount.normalizeToRange(
      0.00001e18,
      min(HyperdriveUtils.calculateMaxShort(hyperdrive), underlyingToken.balanceOf(alice))
    );

    (uint256 maturityTime, ) = openShortERC4626(alice, shortAmount, true);
    // The term passes and interest accrues.
    variableRate = variableRate.normalizeToRange(0, 2.5e18);
  
    advanceTimeWithYield(POSITION_DURATION);

    hyperdrive.closeShort(maturityTime, shortAmount, 0, alice, true);
  }
  
  function test_CloseShortWithToken(uint256 shortAmount, int256 variableRate) external {
    vm.startPrank(alice);
    shortAmount = shortAmount.normalizeToRange(
      0.00001e18,
      min(HyperdriveUtils.calculateMaxShort(hyperdrive), underlyingToken.balanceOf(alice))
    );

    underlyingToken.approve(address(token), type(uint256).max);
    token.deposit(shortAmount, alice);
    (uint256 maturityTime, ) = openShortERC4626(alice, shortAmount, true);
    // The term passes and interest accrues.
    variableRate = variableRate.normalizeToRange(0, 2.5e18);

    advanceTimeWithYield(POSITION_DURATION);

    hyperdrive.closeShort(maturityTime, shortAmount, 0, alice, false);
  }

  /* Helper Functions for dealing with Forked ERC4626 behavior */
  /**
   * @dev Returns the smallest of two numbers.
   */
  function min(uint256 a, uint256 b) internal pure returns (uint256) {
     return a < b ? a : b;
  }

  function openLongERC4626(
      address trader,
      uint256 baseAmount,
      bool asUnderlying
  ) internal returns (uint256 maturityTime, uint256 bondAmount) {
      vm.stopPrank();
      vm.startPrank(trader);

      // Open the long.
      maturityTime = HyperdriveUtils.maturityTimeFromLatestCheckpoint(
          hyperdrive
      );
      uint256 bondBalanceBefore = hyperdrive.balanceOf(
           AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
          trader
      );
      if (asUnderlying) {
        underlyingToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, trader, asUnderlying);
      } else {
        token.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, trader, asUnderlying);
      }
      uint256 bondBalanceAfter = hyperdrive.balanceOf(
          AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
          trader
      );
      return (maturityTime, bondBalanceAfter.sub(bondBalanceBefore));
    }

    function openShortERC4626(
        address trader,
        uint256 bondAmount,
        bool asUnderlying
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
      vm.stopPrank();
      vm.startPrank(trader);
      // Open the short
      maturityTime = HyperdriveUtils.maturityTimeFromLatestCheckpoint(
          hyperdrive
      );
      if (asUnderlying) {
        underlyingToken.approve(address(hyperdrive), bondAmount);
        (maturityTime, baseAmount) = hyperdrive.openShort(
            bondAmount,
            type(uint256).max,
            trader,
            asUnderlying
        );
      } else {
        token.approve(address(hyperdrive), bondAmount);
        (maturityTime, baseAmount) = hyperdrive.openShort(
            bondAmount,
            type(uint256).max,
            trader,
            asUnderlying
        );
      }
      return (maturityTime, baseAmount);
    }

}
