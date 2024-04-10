// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { console2 as console } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";
import { MockLido } from "contracts/test/MockLido.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Lib } from "test/utils/Lib.sol";
import { IHyperdriveGovernedRegistry } from "contracts/src/interfaces/IHyperdriveGovernedRegistry.sol";

contract Inspect is Script {
    using FixedPointMath for *;
    using AssetId for *;
    using Lib for *;

    IHyperdriveGovernedRegistry internal constant HYPERDRIVE_REGISTRY =
        IHyperdriveGovernedRegistry(
            address(0xba5156E697d39a03EDA824C19f375383F6b759EA)
        );

    function setUp() external {}

    function run() external {
        vm.startBroadcast();

        vm.stopBroadcast();
    }
}
