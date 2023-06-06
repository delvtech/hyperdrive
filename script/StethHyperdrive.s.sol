// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { StethHyperdrive } from "contracts/src/instances/StethHyperdrive.sol";
import { StethHyperdriveDataProvider } from "contracts/src/instances/StethHyperdriveDataProvider.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { IWETH } from "contracts/src/interfaces/IWETH.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

interface Faucet {
    function mint(address token, address to, uint256 amount) external;
}

contract StethHyperdriveScript is Script {
    using FixedPointMath for uint256;

    ILido internal constant LIDO =
        ILido(0x1643E812aE58766192Cf7D2Cf9567dF2C37e9B7F);
    IWETH internal constant WETH =
        IWETH(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6);

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy an instance of StethHyperdrive.
        console.log("Deploying StethHyperdrive...");
        uint256 initialSharePrice = LIDO.getTotalPooledEther().divDown(
            LIDO.getTotalShares()
        );
        IHyperdrive.Fees memory fees = IHyperdrive.Fees({
            curve: 0.1e18, // 10% curve fee
            flat: 0.05e18, // 5% flat fee
            governance: 0.1e18 // 10% governance fee
        });
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: WETH,
            initialSharePrice: initialSharePrice,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: HyperdriveUtils.calculateTimeStretch(0.05e18),
            governance: address(0),
            feeCollector: address(0),
            fees: fees,
            oracleSize: 10,
            updateGap: 1 hours
        });
        StethHyperdriveDataProvider dataProvider = new StethHyperdriveDataProvider(
                config,
                bytes32(0),
                address(0),
                LIDO
            );
        IHyperdrive hyperdrive = IHyperdrive(
            address(
                new StethHyperdrive(
                    config,
                    address(dataProvider),
                    bytes32(0),
                    address(0),
                    LIDO
                )
            )
        );

        // Initialize the Hyperdrive instance.
        console.log("Initializing StethHyperdrive...");
        uint256 contribution = 1e18;
        WETH.deposit{ value: contribution }();
        WETH.approve(address(hyperdrive), contribution);
        hyperdrive.initialize(contribution, 0.05e18, msg.sender, true);

        // Ensure that the Hyperdrive instance was initialized properly.
        console.log("Verifying deployment...");
        IHyperdrive.PoolConfig memory config_ = hyperdrive.getPoolConfig();
        require(config_.baseToken == WETH);
        require(config_.initialSharePrice == initialSharePrice);
        IHyperdrive.PoolInfo memory info = hyperdrive.getPoolInfo();
        require(
            info.shareReserves - contribution.divDown(initialSharePrice) <= 1e5
        );
        require(info.sharePrice == initialSharePrice);
        console.log("StethHyperdrive was deployed successfully.");

        vm.stopBroadcast();

        console.log("Deployed StethHyperdrive to: %s", address(hyperdrive));
    }
}
