// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import "contracts/test/ERC20Mintable.sol";
import "contracts/test/MockHyperdriveTestnet.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";

contract MockHyperdriveScript is Script {
    using FixedPointMath for uint256;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Mock ERC20
        ERC20Mintable BASE = new ERC20Mintable();
        BASE.mint(1_000_000 * 1e18);

        // Mock Hyperdrive, 1 year term
        MockHyperdriveTestnet hyperdrive = new MockHyperdriveTestnet(
            BASE,
            5e18,
            FixedPointMath.ONE_18,
            365,
            1 days,
            FixedPointMath.ONE_18.divDown(22.186877016851916266e18),
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.05e18,
                governance: 0.1e18
            }),
            address(0)
        );

        BASE.approve(address(hyperdrive), 10_000_000e18);
        hyperdrive.initialize(100_000e18, 0.05e18, msg.sender, false);
        hyperdrive.openLong(10_000e18, 0, msg.sender, false);

        vm.stopBroadcast();
    }
}
