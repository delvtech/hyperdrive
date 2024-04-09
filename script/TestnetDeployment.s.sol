// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { console2 as console } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { ERC4626HyperdriveDeployerCoordinator } from "contracts/src/deployers/erc4626/ERC4626HyperdriveDeployerCoordinator.sol";
import { ERC4626HyperdriveCoreDeployer } from "contracts/src/deployers/erc4626/ERC4626HyperdriveCoreDeployer.sol";
import { ERC4626Target0Deployer } from "contracts/src/deployers/erc4626/ERC4626Target0Deployer.sol";
import { ERC4626Target1Deployer } from "contracts/src/deployers/erc4626/ERC4626Target1Deployer.sol";
import { ERC4626Target2Deployer } from "contracts/src/deployers/erc4626/ERC4626Target2Deployer.sol";
import { ERC4626Target3Deployer } from "contracts/src/deployers/erc4626/ERC4626Target3Deployer.sol";
import { ERC4626Target4Deployer } from "contracts/src/deployers/erc4626/ERC4626Target4Deployer.sol";
import { StETHHyperdriveDeployerCoordinator } from "contracts/src/deployers/steth/StETHHyperdriveDeployerCoordinator.sol";
import { StETHHyperdriveCoreDeployer } from "contracts/src/deployers/steth/StETHHyperdriveCoreDeployer.sol";
import { StETHTarget0Deployer } from "contracts/src/deployers/steth/StETHTarget0Deployer.sol";
import { StETHTarget1Deployer } from "contracts/src/deployers/steth/StETHTarget1Deployer.sol";
import { StETHTarget2Deployer } from "contracts/src/deployers/steth/StETHTarget2Deployer.sol";
import { StETHTarget3Deployer } from "contracts/src/deployers/steth/StETHTarget3Deployer.sol";
import { StETHTarget4Deployer } from "contracts/src/deployers/steth/StETHTarget4Deployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { HyperdriveRegistry } from "contracts/src/factory/HyperdriveRegistry.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";
import { MockLido } from "contracts/test/MockLido.sol";

contract TestDeploymentScript is Script {
    address internal constant GOVERNANCE_ADDRESS =
        address(0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b);

    address internal constant ADMIN_ADDRESS =
        address(0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8);

    function setUp() external {}

    function run() external {
        vm.startBroadcast();

        // DAI address
        ERC20Mintable dai = new ERC20Mintable(
            "DAI",
            "DAI",
            18,
            ADMIN_ADDRESS,
            true,
            10_000e18
        );
        console.log("dai = %s", address(dai));

        // sDAI address
        MockERC4626 sDai = new MockERC4626(
            dai,
            "Savings DAI",
            "SDAI",
            0.13e18,
            ADMIN_ADDRESS,
            true,
            10_000e18
        );
        console.log("sDai = %s", address(sDai));

        // Lido address
        MockLido lido = new MockLido(0.035e18, ADMIN_ADDRESS, true, 500e18);
        console.log("lido = %s", address(lido));

        // Set minting as a public capability on all tokens and vaults and allow
        // the vault to burn tokens.
        dai.setUserRole(address(sDai), 1, true);
        dai.setRoleCapability(1, bytes4(keccak256("burn(uint256)")), true);
        dai.setPublicCapability(bytes4(keccak256("mint(uint256)")), true);
        sDai.setPublicCapability(bytes4(keccak256("mint(uint256)")), true);
        lido.setPublicCapability(bytes4(keccak256("mint(uint256)")), true);

        // Deploy an ERC20ForwarderFactory.
        ERC20ForwarderFactory forwarderFactory = new ERC20ForwarderFactory();

        // Deploy the HyperdriveFactory.
        HyperdriveFactory factory = new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: GOVERNANCE_ADDRESS,
                hyperdriveGovernance: GOVERNANCE_ADDRESS,
                defaultPausers: new address[](0),
                feeCollector: GOVERNANCE_ADDRESS,
                sweepCollector: GOVERNANCE_ADDRESS,
                checkpointDurationResolution: 8 hours,
                minCheckpointDuration: 24 hours,
                maxCheckpointDuration: 24 hours,
                minPositionDuration: 7 days,
                maxPositionDuration: 7 days,
                minFixedAPR: 0.01e18,
                maxFixedAPR: 0.2e18,
                minTimeStretchAPR: 0.01e18,
                maxTimeStretchAPR: 0.1e18,
                minFees: IHyperdrive.Fees({
                    curve: 0.001e18,
                    flat: 0.0001e18,
                    governanceLP: 0.15e18,
                    governanceZombie: 0.03e18
                }),
                maxFees: IHyperdrive.Fees({
                    curve: 0.01e18,
                    flat: 0.001e18,
                    governanceLP: 0.15e18,
                    governanceZombie: 0.03e18
                }),
                linkerFactory: address(forwarderFactory),
                linkerCodeHash: forwarderFactory.ERC20LINK_HASH()
            })
        );
        console.log("factory = %s", address(factory));

        // Deploy the ERC4626 deployer coordinator.
        ERC4626HyperdriveDeployerCoordinator erc4626HyperdriveDeployerCoordinator = new ERC4626HyperdriveDeployerCoordinator(
                address(factory),
                address(new ERC4626HyperdriveCoreDeployer()),
                address(new ERC4626Target0Deployer()),
                address(new ERC4626Target1Deployer()),
                address(new ERC4626Target2Deployer()),
                address(new ERC4626Target3Deployer()),
                address(new ERC4626Target4Deployer())
            );
        console.log(
            "erc4626 deployer coordinator = %s",
            address(erc4626HyperdriveDeployerCoordinator)
        );

        // Deploy the stETH deployer coordinator.
        StETHHyperdriveDeployerCoordinator stethHyperdriveDeployerCoordinator = new StETHHyperdriveDeployerCoordinator(
                address(factory),
                address(new StETHHyperdriveCoreDeployer()),
                address(new StETHTarget0Deployer()),
                address(new StETHTarget1Deployer()),
                address(new StETHTarget2Deployer()),
                address(new StETHTarget3Deployer()),
                address(new StETHTarget4Deployer()),
                ILido(address(lido))
            );
        console.log(
            "steth deployer coordinator = %s",
            address(stethHyperdriveDeployerCoordinator)
        );

        // Deploy the hyperdrive registry.
        HyperdriveRegistry registry = new HyperdriveRegistry();
        registry.updateGovernance(ADMIN_ADDRESS);
        console.log("hyperdrive registry = %s", address(registry));

        vm.stopBroadcast();
    }
}
