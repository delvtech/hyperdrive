// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { MakerDsrHyperdrive } from "contracts/src/instances/MakerDsrHyperdrive.sol";
import { DsrManager } from "contracts/src/interfaces/IMaker.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

contract MakerDsrHyperdriveScript is Script {
    using FixedPointMath for uint256;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy an instance of MakerDsrHyperdrive.
        DsrManager dsrManager = DsrManager(
            address(0xF7F0de3744C82825D77EdA8ce78f07A916fB6bE7)
        );
        MakerDsrHyperdrive hyperdrive = new MakerDsrHyperdrive({
            _linkerCodeHash: bytes32(0),
            _linkerFactory: address(0),
            _checkpointsPerTerm: 365, // 1 year term
            _checkpointDuration: 1 days, // 1 day checkpoints
            _timeStretch: HyperdriveUtils.calculateTimeStretch(0.02e18), // 2% APR time stretch
            _fees: IHyperdrive.Fees({
                curve: 0.1e18, // 10% curve fee
                flat: 0.05e18, // 5% flat fee
                governance: 0.1e18 // 10% governance fee
            }),
            _governance: address(0),
            _dsrManager: dsrManager
        });

        vm.stopBroadcast();

        console.log("Deployed MakerDsrHyperdrive to: %s", address(hyperdrive));
    }
}
