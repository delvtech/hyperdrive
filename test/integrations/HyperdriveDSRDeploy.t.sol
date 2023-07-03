// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { DsrHyperdriveDeployer } from "contracts/src/factory/DsrHyperdriveDeployer.sol";
import { DsrHyperdriveFactory } from "contracts/src/factory/DsrHyperdriveFactory.sol";
import { DsrHyperdriveDataProvider } from "contracts/src/instances/DsrHyperdriveDataProvider.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { DsrManager } from "contracts/test/MockDsrHyperdrive.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../utils/HyperdriveUtils.sol";

contract HyperdriveDSRTest is HyperdriveTest {
    using FixedPointMath for *;

    DsrHyperdriveFactory factory;
    IERC20 dai = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
    DsrManager manager =
        DsrManager(address(0x373238337Bfe1146fb49989fc222523f83081dDb));

    function setUp() public override __mainnet_fork(16_685_972) {
        vm.startPrank(deployer);

        // Deploy the DsrHyperdrive deployer and factory.
        DsrHyperdriveDeployer simpleDeployer = new DsrHyperdriveDeployer(
            manager
        );
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ForwarderFactory();
        factory = new DsrHyperdriveFactory(
            alice,
            simpleDeployer,
            bob,
            bob,
            IHyperdrive.Fees(0, 0, 0),
            defaults,
            address(forwarderFactory),
            forwarderFactory.ERC20LINK_HASH(),
            address(manager)
        );

        // Set up DAI balances for Alice and Bob.
        address daiWhale = 0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8;
        whaleTransfer(daiWhale, dai, alice);
        vm.stopPrank();
        vm.startPrank(alice);
        dai.approve(address(hyperdrive), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(bob);
        dai.approve(address(hyperdrive), type(uint256).max);
        vm.stopPrank();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_hyperdrive_dsr_deploy_and_init() external {
        setUp();
        // We've just copied the values used by the original tests to ensure this runs

        vm.startPrank(alice);
        bytes32[] memory empty = new bytes32[](0);
        dai.approve(address(factory), type(uint256).max);
        uint256 apr = 0.01e18; // 1% apr
        uint256 contribution = 2_500e18;
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: dai,
            initialSharePrice: FixedPointMath.ONE_18,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: HyperdriveUtils.calculateTimeStretch(apr),
            governance: address(0),
            feeCollector: address(0),
            fees: IHyperdrive.Fees(0, 0, 0),
            oracleSize: 2,
            updateGap: 0
        });
        hyperdrive = factory.deployAndInitialize(
            config,
            empty,
            contribution,
            apr
        );

        // The initial price per share is one so we should have that the
        // shares in the alice account are 1
        uint256 createdShares = hyperdrive.balanceOf(
            AssetId._LP_ASSET_ID,
            alice
        );

        // lp shares should equal number of shares reserves initialized with
        assertEq(createdShares, 2500e18);

        // Verify that the correct events were emitted.
        verifyFactoryEvents(
            factory,
            alice,
            contribution - 1e5,
            apr,
            new bytes32[](0)
        );
    }
}
