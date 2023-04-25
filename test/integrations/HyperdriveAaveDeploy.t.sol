// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { AaveHyperdriveDeployer, IPool } from "contracts/src/factory/AaveHyperdriveDeployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { IPool } from "@aave/interfaces/IPool.sol";

contract HyperdriveDSRTest is HyperdriveTest {
    using FixedPointMath for *;

    HyperdriveFactory factory;
    IERC20 dai = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
    IPool pool = IPool(address(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2));
    IERC20 aDai = IERC20(address(0xfC1E690f61EFd961294b3e1Ce3313fBD8aa4f85d));

    function setUp() public override __mainnet_fork(16_685_972) {
        vm.stopPrank();

        vm.startPrank(deployer);

        AaveHyperdriveDeployer simpleDeployer = new AaveHyperdriveDeployer(
            pool
        );
        factory = new HyperdriveFactory(alice, simpleDeployer, bob);

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

    function test_hyperdrive_aave_deploy_and_init() external {
        setUp();
        // We've just copied the values used by the original tests to ensure this runs

        vm.prank(alice);
        bytes32[] memory aToken = new bytes32[](1);
        // we do a little force convert
        bytes32 aTokenEncode;
        assembly ("memory-safe") {
            aTokenEncode := sload(aDai.slot)
        }
        aToken[0] = aTokenEncode;
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
            aToken,
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
