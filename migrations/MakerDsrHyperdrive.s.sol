// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MakerDsrHyperdrive } from "contracts/src/instances/MakerDsrHyperdrive.sol";
import { DsrManager } from "contracts/src/interfaces/IMaker.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveBase } from "contracts/src/HyperdriveBase.sol";

contract MakerDsrHyperdriveScript is Script {
    using FixedPointMath for uint256;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy an instance of MakerDsrHyperdrive.
        address dsrManager = address(
            0xF7F0de3744C82825D77EdA8ce78f07A916fB6bE7
        );
        MakerDsrHyperdrive hyperdrive = new MakerDsrHyperdrive({
            _linkerCodeHash: bytes32(0),
            _linkerFactory: address(0),
            _checkpointsPerTerm: 365, // 1 year term
            _checkpointDuration: 1 days, // 1 day checkpoints
            _timeStretch: calculateTimeStretch(0.02e18), // 2% APR time stretch
            _fees: HyperdriveBase.Fees({
                curveFee: 0.1e18, // 10% curve fee
                flatFee: 0.05e18, // 5% flat fee
                governanceFee: 0.1e18 // 10% governance fee
            }),
            _governance: address(0),
            _dsrManager: DsrManager(dsrManager)
        });

        // Initialize Hyperdrive to have an APR equal to 1%.
        uint256 apr = 0.01e18;
        uint256 contribution = 50_000e18;
        hyperdrive.baseToken().approve(address(hyperdrive), contribution);
        hyperdrive.initialize(contribution, apr, deployerAddress, true);

        vm.stopBroadcast();
    }
}
