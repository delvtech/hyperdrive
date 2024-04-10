// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { console2 as console } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";

contract TokenUpdates is Script {
    address internal constant ADMIN_ADDRESS =
        address(0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8);
    address internal constant LINKER_FACTORY =
        address(0x13b0AcFA6B77C0464Ce26Ff80da7758b8e1f526E);
    bytes32 internal constant LINKER_CODE_HASH =
        bytes32(
            0xbce832c0ea372ef949945c6a4846b1439b728e08890b93c2aa99e2e3c50ece34
        );

    function setUp() external {}

    function run() external {
        vm.startBroadcast();

        // Deploy DAI.
        ERC20Mintable dai = new ERC20Mintable(
            "DAI",
            "DAI",
            18,
            ADMIN_ADDRESS,
            true,
            10_000e18
        );
        console.log("dai = %s", address(dai));

        // Deploy sDAI.
        MockERC4626 sDai = new MockERC4626(
            dai,
            "sDAI",
            "SDAI",
            0.13e18,
            ADMIN_ADDRESS,
            true,
            10_000e18
        );
        console.log("sDai = %s", address(sDai));

        // Set up the minting permissions.
        dai.setPublicCapability(bytes4(keccak256("mint(uint256)")), true);
        dai.setPublicCapability(
            bytes4(keccak256("mint(address,uint256)")),
            true
        );
        sDai.setPublicCapability(bytes4(keccak256("mint(uint256)")), true);
        sDai.setPublicCapability(
            bytes4(keccak256("mint(address,uint256)")),
            true
        );

        vm.stopBroadcast();
    }
}
