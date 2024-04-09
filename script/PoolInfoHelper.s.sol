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

contract VerifierHelper is Script {
    using FixedPointMath for *;
    using AssetId for *;
    using Lib for *;

    HyperdriveFactory internal constant FACTORY =
        HyperdriveFactory(payable(0x338D5634c391ef47FB797417542aa75F4f71A4a6));
    IHyperdrive POOL =
        IHyperdrive(address(0x1b812C782469e17ef4FA57A0de02Ffd3Df2c5A21));

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

    function setUp() external {}

    function run() external view {
        IHyperdrive.PoolInfo memory p = POOL.getPoolInfo();
        console.log("shareReserves: %s", p.shareReserves.toString(18));
        console.log("shareAdjustment: %s", p.shareAdjustment.toString(18));
        console.log(
            "zombieBaseProceeds: %s",
            p.zombieBaseProceeds.toString(18)
        );
        console.log(
            "zombieShareReserves: %s",
            p.zombieShareReserves.toString(18)
        );
        console.log("bondReserves: %s", p.bondReserves.toString(18));
        console.log("lpTotalSupply: %s", p.lpTotalSupply.toString(18));
        console.log("vaultSharePrice: %s", p.vaultSharePrice.toString(18));
        console.log("longsOutstanding: %s", p.longsOutstanding.toString(18));
        console.log(
            "longAverageMaturityTime: %s",
            p.longAverageMaturityTime.toString(18)
        );
        console.log("shortsOutstanding: %s", p.shortsOutstanding.toString(18));
        console.log(
            "shortAverageMaturityTime: %s",
            p.shortAverageMaturityTime.toString(18)
        );
        console.log(
            "withdrawalSharesReadyToWithdraw: %s",
            p.withdrawalSharesReadyToWithdraw.toString(18)
        );
        console.log(
            "withdrawalSharesProceeds: %s",
            p.withdrawalSharesProceeds.toString(18)
        );
        console.log("lpSharePrice: %s", p.lpSharePrice.toString(18));
        console.log("longExposure: %s", p.longExposure.toString(18));

        console.log(
            "shares asset balance: %s",
            POOL
                .balanceOf(
                    AssetId._LP_ASSET_ID,
                    address(0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8)
                )
                .toString(18)
        );
        console.log(
            "lp asset balance: %s",
            POOL
                .balanceOf(
                    AssetId._LP_ASSET_ID,
                    address(0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8)
                )
                .toString(18)
        );
    }
}
