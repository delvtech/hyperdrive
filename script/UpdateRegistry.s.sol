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

contract UpdateRegistry is Script {
    using FixedPointMath for *;
    using AssetId for *;
    using Lib for *;

    HyperdriveFactory internal constant FACTORY =
        HyperdriveFactory(payable(0x338D5634c391ef47FB797417542aa75F4f71A4a6));
    IHyperdrive POOL =
        IHyperdrive(address(0xdb0275129e4107e41AD79C799e1B59a6B9bF4eb0));

    address internal constant DAI =
        address(0x58fa9611D2a14CBec045b92Cef06b600897a4fB6);
    address internal constant SDAI =
        address(0xC672A891525532d29b842B9753046F6d30ce613c);
    address internal constant LINKER_FACTORY =
        address(0x13b0AcFA6B77C0464Ce26Ff80da7758b8e1f526E);
    bytes32 internal constant LINKER_CODE_HASH =
        bytes32(
            0xbce832c0ea372ef949945c6a4846b1439b728e08890b93c2aa99e2e3c50ece34
        );
    IHyperdriveGovernedRegistry internal constant HYPERDRIVE_REGISTRY =
        IHyperdriveGovernedRegistry(
            address(0xba5156E697d39a03EDA824C19f375383F6b759EA)
        );

    function setUp() external {}

    function run() external {
        vm.startBroadcast();

        // ERC4626 14 day
        HYPERDRIVE_REGISTRY.setHyperdriveInfo(
            address(0x1b812C782469e17ef4FA57A0de02Ffd3Df2c5A21),
            0
        );
        // ERC4626 30 day
        HYPERDRIVE_REGISTRY.setHyperdriveInfo(
            address(0xdb0275129e4107e41AD79C799e1B59a6B9bF4eb0),
            0
        );
        // ERC4626 14 day
        HYPERDRIVE_REGISTRY.setHyperdriveInfo(
            address(0x392839dA0dACAC790bd825C81ce2c5E264D793a8),
            1
        );
        // ERC4626 30 day
        HYPERDRIVE_REGISTRY.setHyperdriveInfo(
            address(0xb932F8085399C228b16A9F7FC3219d47FfA2810d),
            1
        );

        vm.stopBroadcast();
    }
}