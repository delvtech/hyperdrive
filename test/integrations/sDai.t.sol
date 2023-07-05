// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { ERC4626HyperdriveDeployer } from "contracts/src/factory/ERC4626HyperdriveDeployer.sol";
import { ERC4626HyperdriveFactory } from "contracts/src/factory/ERC4626HyperdriveFactory.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { Mock4626, ERC20 } from "../mocks/Mock4626.sol";
import { MockERC4626Hyperdrive } from "../mocks/Mock4626Hyperdrive.sol";
import { HyperdriveUtils } from "../utils/HyperdriveUtils.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";

contract sDAIHyperdrive is HyperdriveTest {
    using FixedPointMath for *;

    ERC4626HyperdriveFactory factory;
    IERC20 dai = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
    IERC4626 sDai = IERC4626(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
    uint256 aliceShares;
    MockERC4626Hyperdrive mockHyperdrive;

    function setUp() override public __mainnet_fork(17_318_972) {
        alice = createUser("alice");
        bob = createUser("bob");

        vm.startPrank(deployer);

        // Deploy the ERC4626Hyperdrive factory and deployer.
        ERC4626HyperdriveDeployer simpleDeployer = new ERC4626HyperdriveDeployer(
                sDai
            );
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ForwarderFactory();
        factory = new ERC4626HyperdriveFactory(
            alice,
            simpleDeployer,
            bob,
            bob,
            IHyperdrive.Fees(0, 0, 0),
            defaults,
            address(forwarderFactory),
            forwarderFactory.ERC20LINK_HASH(),
            sDai
        );

        address daiWhale = 0x60FaAe176336dAb62e284Fe19B885B095d29fB7F;
        whaleTransfer(daiWhale, dai, alice);

        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: dai,
            initialSharePrice: FixedPointMath.ONE_18.divDown(sDai.convertToShares(FixedPointMath.ONE_18)),
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: FixedPointMath.ONE_18.divDown(
                22.186877016851916266e18
            ),
            governance: alice,
            feeCollector: bob,
            fees: IHyperdrive.Fees(0, 0, 0),
            oracleSize: 2,
            updateGap: 0
        });
        
        // Create a mock hyperdrive with functions available
        mockHyperdrive = new MockERC4626Hyperdrive(
            config,
            address(0),
            bytes32(0),
            address(0),
            sDai
        );

        vm.stopPrank();
        vm.startPrank(alice);
        dai.approve(address(hyperdrive), type(uint256).max);
        dai.approve(address(mockHyperdrive), type(uint256).max);
        dai.approve(address(sDai), type(uint256).max);
        aliceShares = sDai.deposit(10e18, alice);

        vm.stopPrank();
        vm.startPrank(bob);
        dai.approve(address(hyperdrive), type(uint256).max);
        dai.approve(address(mockHyperdrive), type(uint256).max);
        vm.stopPrank();

        // Start recording events.
        vm.recordLogs();
    }

    function test__base_token_is_dai() public {
        assertEq(
            address(hyperdrive.baseToken()),
            address(dai),
            "Wrong Basetoken set"
        );
    }


    
}
