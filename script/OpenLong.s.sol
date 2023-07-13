// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { DsrHyperdrive } from "contracts/src/instances/DsrHyperdrive.sol";
import { DsrHyperdriveDataProvider } from "contracts/src/instances/DsrHyperdriveDataProvider.sol";
import { DsrManager } from "contracts/src/interfaces/IMaker.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract OpenLongScript is Script {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    IHyperdrive internal constant HYPERDRIVE =
        IHyperdrive(0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9);
    ERC20Mintable internal constant BASE =
        ERC20Mintable(0x5FbDB2315678afecb367f032d93F642f64180aa3);

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        BASE.mint(msg.sender, 10_000e18);
        BASE.approve(address(HYPERDRIVE), 10_000e18);
        (uint256 maturityTime, uint256 longAmount) = HYPERDRIVE.openLong(
            10_000e18,
            0,
            msg.sender,
            true
        );

        console.log(
            "Bob opened a long position of %s bonds that matures in timestamp %s",
            longAmount,
            maturityTime
        );
        console.log(
            "Bob's long balance is now %s bonds",
            HYPERDRIVE.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Long,
                    HYPERDRIVE.latestCheckpoint() +
                        HYPERDRIVE.getPoolConfig().positionDuration
                ),
                msg.sender
            )
        );

        vm.stopBroadcast();
    }

    function createUser(string memory name) public returns (address _user) {
        _user = address(uint160(uint256(keccak256(abi.encode(name)))));
        vm.label(_user, name);
        vm.deal(_user, 10000 ether);
    }
}
