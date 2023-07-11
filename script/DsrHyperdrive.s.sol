// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { DsrHyperdrive } from "contracts/src/instances/DsrHyperdrive.sol";
import { DsrHyperdriveDataProvider } from "contracts/src/instances/DsrHyperdriveDataProvider.sol";
import { DsrManager } from "contracts/src/interfaces/IMaker.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

interface Faucet {
    function mint(address token, address to, uint256 amount) external;
}

contract DsrHyperdriveScript is Script {
    using FixedPointMath for uint256;

    Faucet internal constant FAUCET =
        Faucet(0xe2bE5BfdDbA49A86e27f3Dd95710B528D43272C2);
    DsrManager internal constant DSR_MANAGER =
        DsrManager(0xF7F0de3744C82825D77EdA8ce78f07A916fB6bE7);

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy an instance of DsrHyperdrive.
        console.log("Deploying DsrHyperdrive...");
        IERC20 dai = IERC20(DSR_MANAGER.dai());
        IHyperdrive.Fees memory fees = IHyperdrive.Fees({
            curve: 0.1e18, // 10% curve fee
            flat: 0.05e18, // 5% flat fee
            governance: 0.1e18 // 10% governance fee
        });
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: dai,
            initialSharePrice: 1e18,
            minimumShareReserves: 10e18,
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
            DSR_MANAGER
        );
        IHyperdrive hyperdrive = IHyperdrive(
            address(
                new DsrHyperdrive(
                    config,
                    address(dataProvider),
                    bytes32(0),
                    address(0),
                    DSR_MANAGER
                )
            )
        );

        // Initialize the Hyperdrive instance.
        console.log("Initializing DsrHyperdrive...");
        uint256 contribution = 50_000e18;
        FAUCET.mint(address(dai), msg.sender, contribution);
        dai.approve(address(hyperdrive), contribution);
        hyperdrive.initialize(contribution, 0.02e18, msg.sender, true);

        // Ensure that the Hyperdrive instance was initialized properly.
        console.log("Verifying deployment...");
        IHyperdrive.PoolConfig memory config_ = hyperdrive.getPoolConfig();
        require(config_.baseToken == dai);
        require(config_.initialSharePrice == FixedPointMath.ONE_18);
        IHyperdrive.PoolInfo memory info = hyperdrive.getPoolInfo();
        require(info.shareReserves == contribution);
        require(info.sharePrice == FixedPointMath.ONE_18);
        console.log("DsrHyperdrive was deployed successfully.");

        vm.stopBroadcast();

        console.log("Deployed DsrHyperdrive to: %s", address(hyperdrive));
    }
}
