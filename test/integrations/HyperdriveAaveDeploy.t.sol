// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IPool } from "@aave/interfaces/IPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AaveHyperdriveDeployer, IPool } from "contracts/src/factory/AaveHyperdriveDeployer.sol";
import { AaveHyperdriveFactory } from "contracts/src/factory/AaveHyperdriveFactory.sol";
import { AaveHyperdriveDataProvider } from "contracts/src/instances/AaveHyperdriveDataProvider.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";

contract HyperdriveDSRTest is HyperdriveTest {
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
        factory = new AaveHyperdriveFactory(
            alice,
            simpleDeployer,
            bob,
            IHyperdrive.Fees(0, 0, 0)
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
    }

    function test_hyperdrive_aave_deploy_and_init() external {
        setUp();
        // We've just copied the values used by the original tests to ensure this runs

        vm.startPrank(alice);
        bytes32[] memory aToken = new bytes32[](1);
        aToken[0] = bytes32(uint256(uint160(address(aDai))));
        dai.approve(address(factory), type(uint256).max);
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: dai,
            initialSharePrice: FixedPointMath.ONE_18,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: FixedPointMath.ONE_18.divDown(
                22.186877016851916266e18
            ),
            governance: address(0),
            fees: IHyperdrive.Fees(0, 0, 0),
            oracleSize: 2,
            updateGap: 0
        });
        hyperdrive = factory.deployAndInitialize(
            config,
            bytes32(0),
            address(0),
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
