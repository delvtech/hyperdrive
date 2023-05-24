// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { DsrHyperdrive } from "contracts/src/instances/DsrHyperdrive.sol";
import { DsrHyperdriveDataProvider } from "contracts/src/instances/DsrHyperdriveDataProvider.sol";
import { DsrManager } from "contracts/src/interfaces/IMaker.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

contract DsrHyperdriveScript is Script {
    using FixedPointMath for uint256;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy an instance of DsrHyperdrive.
        DsrManager dsrManager = DsrManager(
            address(0xF7F0de3744C82825D77EdA8ce78f07A916fB6bE7)
        );
        IHyperdrive.Fees memory fees = IHyperdrive.Fees({
            curve: 0.1e18, // 10% curve fee
            flat: 0.05e18, // 5% flat fee
            governance: 0.1e18 // 10% governance fee
        });
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: IERC20(dsrManager.dai()),
            initialSharePrice: 1e18,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: HyperdriveUtils.calculateTimeStretch(0.02e18),
            governance: address(0),
            feeCollector: address(0),
            fees: fees,
            oracleSize: 10,
            updateGap: 1 hours
        });
        DsrHyperdriveDataProvider dataProvider = new DsrHyperdriveDataProvider(
            config,
            bytes32(0),
            address(0),
            dsrManager
        );
        DsrHyperdrive hyperdrive = new DsrHyperdrive(
            config,
            address(dataProvider),
            bytes32(0),
            address(0),
            dsrManager
        );

        vm.stopBroadcast();

        console.log("Deployed DsrHyperdrive to: %s", address(hyperdrive));
    }
}
