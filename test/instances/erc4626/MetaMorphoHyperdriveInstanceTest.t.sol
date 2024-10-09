// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Id, IMorpho, Market, MarketParams } from "morpho-blue/src/interfaces/IMorpho.sol";
import { MorphoBalancesLib } from "morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../../contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IMetaMorpho } from "../../../contracts/src/interfaces/IMetaMorpho.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { Lib } from "../../utils/Lib.sol";
import { ERC4626HyperdriveInstanceTest } from "./ERC4626HyperdriveInstanceTest.t.sol";

abstract contract MetaMorphoHyperdriveInstanceTest is
    ERC4626HyperdriveInstanceTest
{
    using FixedPointMath for uint256;
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using MorphoBalancesLib for IMorpho;
    using stdStorage for StdStorage;

    /// @dev The MetaMorpho vault.
    IMetaMorpho internal vault;

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public virtual override {
        // Invoke the Instance testing suite setup.
        super.setUp();

        // The MetaMorpho vault is the vault shares token.
        vault = IMetaMorpho(address(config.vaultSharesToken));

        // Set the MetaMorpho vault's fee to zero to simplify the interest logic.
        // This also accrues all of the existing interest at the existing fee
        // level. Doing this before testing ensures that our total shares checks
        // in `verifyDeposit` and `verifyWithdrawal` succeeeds.
        vm.stopPrank();
        vm.startPrank(vault.owner());
        vault.setFee(0);
    }

    /// Helpers ///

    /// @dev Advance time and accrue interest.
    /// @param timeDelta The time to advance.
    /// @param variableRate The variable rate.
    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Get the total assets before warping the time.
        IMorpho morpho = vault.MORPHO();
        uint256[] memory totalSupplyAssetsBefore = new uint256[](
            vault.withdrawQueueLength()
        );
        for (uint256 i = 0; i < totalSupplyAssetsBefore.length; i++) {
            totalSupplyAssetsBefore[i] = morpho.expectedTotalSupplyAssets(
                morpho.idToMarketParams(vault.withdrawQueue(i))
            );
        }

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in the Morpho market. This amounts to manually
        // updating the total supply assets and the last update time of each of
        // the markets in the withdraw queue to increase the total supply a
        // sufficient amount.
        for (uint256 i = 0; i < totalSupplyAssetsBefore.length; i++) {
            Id marketId = vault.withdrawQueue(i);
            Market memory market = morpho.market(marketId);
            (uint256 totalSupplyAssets, ) = totalSupplyAssetsBefore[i]
                .calculateInterest(variableRate, timeDelta);
            bytes32 marketLocation = keccak256(abi.encode(marketId, 3));
            vm.store(
                address(morpho),
                marketLocation,
                bytes32(
                    (uint256(market.totalSupplyShares) << 128) |
                        totalSupplyAssets
                )
            );
            vm.store(
                address(morpho),
                bytes32(uint256(marketLocation) + 2),
                bytes32((uint256(market.fee) << 128) | uint256(block.timestamp))
            );
        }
    }
}
