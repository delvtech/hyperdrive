// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Script.sol";

interface Faucet {
    function mint(address token, address to, uint256 amount) external;
}

contract FaucetScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Mint dai token to deployer address
        address dai = address(0x11fE4B6AE13d2a6055C8D9cF65c55bac32B5d844);
        Faucet faucet = Faucet(
            address(0xe2bE5BfdDbA49A86e27f3Dd95710B528D43272C2)
        );
        faucet.mint(dai, deployerAddress, 50_000e18);

        vm.stopBroadcast();
    }
}
