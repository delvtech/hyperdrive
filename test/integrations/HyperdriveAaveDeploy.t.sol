// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { VmSafe } from "forge-std/Vm.sol";
import { IPool } from "@aave/interfaces/IPool.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { AaveHyperdriveDeployer, IPool } from "contracts/src/factory/AaveHyperdriveDeployer.sol";
import { AaveHyperdriveFactory } from "contracts/src/factory/AaveHyperdriveFactory.sol";
import { AaveHyperdriveDataProvider } from "contracts/src/instances/AaveHyperdriveDataProvider.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../utils/HyperdriveUtils.sol";
import { Lib } from "../utils/Lib.sol";

contract HyperdriveAaveTest is HyperdriveTest {
    using FixedPointMath for *;

    AaveHyperdriveFactory factory;
    IERC20 dai = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
    IPool pool = IPool(address(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2));
    IERC20 aDai = IERC20(address(0x018008bfb33d285247A21d44E50697654f754e63));

    function setUp() public override __mainnet_fork(16_685_972) {
        vm.startPrank(deployer);

        AaveHyperdriveDeployer simpleDeployer = new AaveHyperdriveDeployer(
            pool
        );
        address[] memory defaults = new address[](1);
        defaults[0] = bob;

        forwarderFactory = new ForwarderFactory();
        factory = new AaveHyperdriveFactory(
            alice,
            simpleDeployer,
            bob,
            bob,
            IHyperdrive.Fees(0, 0, 0),
            defaults,
            address(forwarderFactory),
            forwarderFactory.ERC20LINK_HASH()
        );

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

    // We've just copied the values used by the original tests to ensure this runs
    function test_hyperdrive_aave_deploy_and_init() external {
        vm.startPrank(alice);
        dai.approve(address(factory), type(uint256).max);
        uint256 apr = 1e16; // 1% apr
        uint256 contribution = 2_500e18;
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: dai,
            initialSharePrice: FixedPointMath.ONE_18,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: HyperdriveUtils.calculateTimeStretch(apr),
            governance: governance,
            feeCollector: feeCollector,
            fees: IHyperdrive.Fees(0.05e18, 0.0005e18, 0.15e18),
            oracleSize: 2,
            updateGap: 0
        });
        hyperdrive = factory.deployAndInitialize(
            config,
            new bytes32[](0),
            contribution,
            apr
        );

        // The initial price per share is one so we should have that the
        // shares in the alice account are 1
        uint256 createdShares = hyperdrive.balanceOf(
            AssetId._LP_ASSET_ID,
            alice
        );

        // lp shares should equal number of share reserves initialized with
        assertEq(createdShares, contribution);

        // Verify that the correct events were emitted.
        bytes32[] memory expectedExtraData = new bytes32[](1);
        address aToken = pool
            .getReserveData(address(hyperdrive.getPoolConfig().baseToken))
            .aTokenAddress;
        expectedExtraData[0] = bytes32(uint256(uint160(aToken)));
        verifyFactoryEvents(
            factory,
            alice,
            contribution,
            apr,
            expectedExtraData
        );
    }

    // We've just copied the values used by the original tests to ensure this runs
    function testEnsureNonZeroInit() public {
        vm.startPrank(alice);
        dai.approve(address(factory), type(uint256).max);
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: IERC20(address(0)),
            initialSharePrice: FixedPointMath.ONE_18,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: FixedPointMath.ONE_18.divDown(
                22.186877016851916266e18
            ),
            governance: address(0),
            feeCollector: address(0),
            fees: IHyperdrive.Fees(0, 0, 0),
            oracleSize: 2,
            updateGap: 0
        });

        vm.expectRevert();
        hyperdrive = factory.deployAndInitialize(
            config,
            new bytes32[](0),
            2500e18,
            //1% apr
            1e16
        );
    }
}
