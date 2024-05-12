// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IEzETHHyperdrive } from "contracts/src/interfaces/IEzETHHyperdrive.sol";
import { MockEzEthPool } from "contracts/test/MockEzEthPool.sol";
import { IRestakeManager } from "contracts/src/interfaces/IRenzo.sol";
import { IRenzoOracle, IDepositQueue } from "contracts/src/interfaces/IRenzo.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { BaseTest } from "test/utils/BaseTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";
import { EtchingUtils } from "test/utils/EtchingUtils.sol";

import { console2 as console } from "forge-std/console2.sol";

contract EzETHHyperdriveTest is BaseTest, EtchingUtils {
    using HyperdriveUtils for *;
    using FixedPointMath for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    address EZETH_HYPERDRIVE_ADDRESS = 0x8B713283f6B2e081EdA4a0993c4467E7504d3109;
    IEzETHHyperdrive hyperdrive = IEzETHHyperdrive(EZETH_HYPERDRIVE_ADDRESS);
    uint256 STARTING_BLOCK = 5_875_056;

    function setUp() public override __sepolia_fork(STARTING_BLOCK){
        etchEzETHHyperdrive(EZETH_HYPERDRIVE_ADDRESS);
    }

    function test__spotPrice() public {
        address poolAddress = address(hyperdrive.renzo());
        MockEzEthPool pool = MockEzEthPool(poolAddress);
        pool.calculateTVLs();
        uint256 price = hyperdrive.pricePerVaultShare();
        console.log('price', price);
        uint256 spotPrice = HyperdriveUtils.calculateSpotPrice(hyperdrive);
        console.log('spotPrice', spotPrice);
    }
}
