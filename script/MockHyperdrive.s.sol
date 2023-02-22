// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "../test/mocks/ERC20Mintable.sol";
import "../test/mocks/MockHyperdrive.sol";


contract MockHyperdriveScript is Script {
    function setUp() public {}

    function run() public {

      uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Mock ERC20
        ERC20Mintable BASE = new ERC20Mintable();
        BASE.mint(1_000_000 * 1e18);

        // Mock Hyperdrive
        MockHyperdrive hyperdrive = new MockHyperdrive(BASE, 1e18, 183, 4.32 * 1e7, 50);

        BASE.approve(address(hyperdrive), 10_000_000 * 1e18);
        hyperdrive.initialize(100_000 * 1e18, 50, msg.sender);

        hyperdrive.openLong(10_000 * 1e18, 0, msg.sender);






        vm.stopBroadcast();
    }
}
