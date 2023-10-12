// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { Script } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { ERC4626HyperdriveDeployer } from "contracts/src/factory/ERC4626HyperdriveDeployer.sol";
import { ERC4626HyperdriveFactory } from "contracts/src/factory/ERC4626HyperdriveFactory.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";
import { MockHyperdriveMath } from "contracts/test/MockHyperdriveMath.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

/// @author DELV
/// @title DevnetMigration
/// @notice This script deploys a mock ERC4626 yield source and a Hyperdrive
///         factory on top of it. For convenience, it also deploys a Hyperdrive
///         pool with a 1 week duration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract DevnetMigration is Script {
    using stdJson for string;
    using HyperdriveUtils for *;

    function setUp() external {}

    function run() external {
        vm.startBroadcast();

        // Deploy the base token and yield source.
        ERC20Mintable baseToken = new ERC20Mintable();
        MockERC4626 pool = new MockERC4626(
            baseToken,
            "Delvnet Yield Source",
            "DELV",
            0.05e18 // initial rate of 5%
        );

        // Deploy the Hyperdrive factory.
        ERC4626HyperdriveFactory factory;
        {
            address[] memory defaultPausers = new address[](1);
            defaultPausers[0] = msg.sender;
            HyperdriveFactory.FactoryConfig
                memory factoryConfig = HyperdriveFactory.FactoryConfig({
                    governance: msg.sender,
                    hyperdriveGovernance: msg.sender,
                    feeCollector: msg.sender,
                    fees: IHyperdrive.Fees({
                        curve: 0.1e18, // 10%
                        flat: 0.0005e18, // 0.05%
                        governance: 0.15e18 // 15%
                    }),
                    maxFees: IHyperdrive.Fees({
                        curve: 0.3e18, // 30%
                        flat: 0.0015e18, // 0.15%
                        governance: 0.30e18 // 30%
                    }),
                    defaultPausers: defaultPausers
                });
            ForwarderFactory forwarderFactory = new ForwarderFactory();
            ERC4626HyperdriveDeployer deployer = new ERC4626HyperdriveDeployer(
                IERC4626(address(pool))
            );
            factory = new ERC4626HyperdriveFactory(
                factoryConfig,
                deployer,
                address(forwarderFactory),
                forwarderFactory.ERC20LINK_HASH(),
                IERC4626(address(pool)),
                new address[](0)
            );
        }

        // Deploy and initialize a 1 week pool for the devnet.
        IHyperdrive hyperdrive;
        {
            uint256 contribution = 100_000_000e18;
            uint256 fixedRate = 0.05e18;
            baseToken.mint(msg.sender, contribution);
            baseToken.approve(address(factory), contribution);
            IHyperdrive.PoolConfig memory poolConfig = IHyperdrive.PoolConfig({
                baseToken: IERC20(address(baseToken)),
                initialSharePrice: 1e18,
                minimumShareReserves: 10e18,
                minimumTransactionAmount: 0.001e18,
                // FIXME: This is a shot in the dark, and I should update this
                // value after some more testing.
                negativeInterestTolerance: 1e9,
                positionDuration: 1 weeks,
                checkpointDuration: 1 hours,
                timeStretch: 0.05e18.calculateTimeStretch(),
                governance: msg.sender,
                feeCollector: msg.sender,
                fees: IHyperdrive.Fees({
                    curve: 0.1e18, // 10%
                    flat: 0.0005e18, // 0.05%
                    governance: 0.15e18 // 15%
                }),
                oracleSize: 10,
                updateGap: 1 hours
            });
            hyperdrive = factory.deployAndInitialize(
                poolConfig,
                new bytes32[](0),
                contribution,
                fixedRate
            );
        }

        // Deploy the MockHyperdriveMath contract.
        MockHyperdriveMath mockHyperdriveMath = new MockHyperdriveMath();

        vm.stopBroadcast();

        // Writes the addresses to a file.
        string memory result = "result";
        vm.serializeAddress(result, "baseToken", address(baseToken));
        vm.serializeAddress(result, "hyperdriveFactory", address(factory));
        // TODO: This is deprecated and should be removed by 0.0.11.
        vm.serializeAddress(result, "mockHyperdrive", address(hyperdrive));
        result = vm.serializeAddress(
            result,
            "mockHyperdriveMath",
            address(mockHyperdriveMath)
        );
        result.write("./artifacts/script_addresses.json");
    }
}
