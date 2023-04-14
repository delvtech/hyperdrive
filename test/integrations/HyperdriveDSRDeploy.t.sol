// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { MakerDsrHyperdriveDeployer } from "contracts/src/factory/MakerDsrHyperdriveDeployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { DsrManager } from "contracts/test/MockMakerDsrHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FixedPointMath} from "contracts/src/libraries/FixedPointMath.sol";
import "forge-std/console.sol";

contract HyperdriveDSRTest is HyperdriveTest {
    using FixedPointMath for *;

    HyperdriveFactory factory;
    IERC20 dai = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
    DsrManager manager = DsrManager(
        address(0x373238337Bfe1146fb49989fc222523f83081dDb)
    );

    function setUp() public override __mainnet_fork(16_685_972) {
        vm.stopPrank();
        vm.startPrank(deployer);

        MakerDsrHyperdriveDeployer simpleDeployer = new MakerDsrHyperdriveDeployer(manager);
        factory = new HyperdriveFactory(
            alice, 
            simpleDeployer,
            bob
        );  

        vm.stopPrank();

        address daiWhale = 0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8;

        whaleTransfer(daiWhale, dai, alice);

        vm.stopPrank();
        vm.startPrank(alice);
        dai.approve(address(hyperdrive), type(uint256).max);

        vm.stopPrank();
        vm.startPrank(bob);
        dai.approve(address(hyperdrive), type(uint256).max);
        vm.stopPrank();
    }

    function test_dsr_factory_should_be_mainnet_deployable() external {

        MakerDsrHyperdriveDeployer simpleDeployer = new MakerDsrHyperdriveDeployer(manager);
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(simpleDeployer)
        }
        console.log("DSR factory codesize: ", codeSize);
        assertGt(codeSize, 0, "Must have code");
        assertLt(codeSize, 24576, "Not Mainnet deployable");
    }


    function test_hyperdrive_dsr_deploy_and_init() external {
        setUp();
        // We've just copied the values used by the original tests to ensure this runs

        vm.prank(alice);
        bytes32[] memory empty = new bytes32[](0);
        dai.approve(address(factory), type(uint256).max);
        vm.prank(alice);
        hyperdrive = factory.deployAndImplement(
            bytes32(0),
            address(0),
            dai,
            0,
            365,
            1 days,
            FixedPointMath.ONE_18.divDown(22.186877016851916266e18),
            IHyperdrive.Fees(0, 0, 0),
            empty,
            2500e18,
            //1% apr
            1e16
        );

        // The initial price per share is one so we should have that the 
        // shares in the alice account are 1
        uint256 createdShares = hyperdrive.balanceOf(
            AssetId._LP_ASSET_ID,
            alice
        );
        assertEq(createdShares, 2808790684246250377500);
    }
}