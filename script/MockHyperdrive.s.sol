// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { stdJson } from "forge-std/StdJson.sol";
import { Script } from "forge-std/Script.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
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

        // Deploy the base token.
        ERC20Mintable baseToken = new ERC20Mintable();

        // Deploy the hyperdrive instance.
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: IERC20(address(baseToken)),
            initialSharePrice: FixedPointMath.ONE_18,
            minimumShareReserves: 10e18,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: FixedPointMath.ONE_18.divDown(
                22.186877016851916266e18
            ),
            fees: IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.05e18,
                governance: 0.1e18
            }),
            governance: address(0),
            feeCollector: address(0),
            oracleSize: 10,
            updateGap: 3600
        });
        MockHyperdriveDataProviderTestnet dataProvider = new MockHyperdriveDataProviderTestnet(
                config
            );
        MockHyperdriveTestnet hyperdrive = new MockHyperdriveTestnet(
            config,
            address(dataProvider),
            0.05e18
        );

        // Initialize the Hyperdrive pool.
        uint256 contribution = 1_000_000e18;
        uint256 fixedRate = 0.05e18;
        baseToken.mint(msg.sender, contribution);
        baseToken.approve(address(hyperdrive), contribution);
        hyperdrive.initialize(contribution, fixedRate, msg.sender, true);

        // Deploy the MockHyperdriveMath contract.
        MockHyperdriveMath mockHyperdriveMath = new MockHyperdriveMath();

        vm.stopBroadcast();

        // Writes the addresses to a file.
        string memory result = "result";
        vm.serializeAddress(result, "baseToken", address(baseToken));
        vm.serializeAddress(result, "mockHyperdrive", address(hyperdrive));
        result = vm.serializeAddress(
            result,
            "mockHyperdriveMath",
            address(mockHyperdriveMath)
        );
        result.write("./artifacts/script_addresses.json");
    }
}
