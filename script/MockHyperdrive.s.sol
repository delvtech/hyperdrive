// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Script } from "forge-std/Script.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockHyperdriveTestnet, MockHyperdriveDataProviderTestnet } from "contracts/test/MockHyperdriveTestnet.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";

// FIXME: We need to use a private key that has eth on this chain.
contract MockHyperdriveScript is Script {
    using FixedPointMath for uint256;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);

        // Mock ERC20
        ERC20Mintable baseToken = new ERC20Mintable();
        baseToken.mint(1_000_000e18);

        // Mock Hyperdrive, 1 year term
        MockHyperdriveDataProviderTestnet dataProvider = new MockHyperdriveDataProviderTestnet(
                baseToken,
                5e18,
                FixedPointMath.ONE_18,
                365 days,
                1 days,
                FixedPointMath.ONE_18.divDown(22.186877016851916266e18),
                IHyperdrive.Fees({
                    curve: 0.1e18,
                    flat: 0.05e18,
                    governance: 0.1e18
                }),
                address(0)
            );
        MockHyperdriveTestnet hyperdrive = new MockHyperdriveTestnet(
            address(dataProvider),
            baseToken,
            5e18,
            FixedPointMath.ONE_18,
            365 days,
            1 days,
            FixedPointMath.ONE_18.divDown(22.186877016851916266e18),
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.05e18,
                governance: 0.1e18
            }),
            address(0)
        );

        baseToken.approve(address(hyperdrive), 10_000_000e18);
        hyperdrive.initialize(100_000e18, 0.05e18, deployer, true);

        vm.stopBroadcast();
    }
}
