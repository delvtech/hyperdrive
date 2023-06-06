// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { stdJson } from "forge-std/StdJson.sol";
import { Script } from "forge-std/Script.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { MockHyperdriveMath } from "contracts/test/MockHyperdriveMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockHyperdriveTestnet, MockHyperdriveDataProviderTestnet } from "contracts/test/MockHyperdriveTestnet.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";

contract MockHyperdriveScript is Script {
    using stdJson for string;

    using FixedPointMath for uint256;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

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

        // Initializes the Hyperdrive pool.
        baseToken.approve(address(hyperdrive), 10_000_000e18);
        hyperdrive.initialize(100_000e18, 0.05e18, msg.sender, true);

        MockHyperdriveMath mockHyperdriveMath = new MockHyperdriveMath();

        vm.stopBroadcast();

        // Writes the addresses to a file.
        string memory result = "result";
        vm.serializeAddress(result, "baseToken", address(baseToken));
        result = vm.serializeAddress(
            result,
            "dsrHyperdrive",
            address(hyperdrive)
        );
        result = vm.serializeAddress(
            result,
            "mockHyperdriveMath",
            address(mockHyperdriveMath)
        );
        result.write("./artifacts/script_addresses.json");
    }
}
