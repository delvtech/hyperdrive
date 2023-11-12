// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626HyperdriveDeployer } from "contracts/src/instances/ERC4626HyperdriveDeployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { ERC4626HyperdriveDeployer } from "contracts/src/instances/ERC4626HyperdriveDeployer.sol";
import { ERC4626Target0Deployer } from "contracts/src/instances/ERC4626Target0Deployer.sol";
import { ERC4626Target1Deployer } from "contracts/src/instances/ERC4626Target1Deployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { MockERC4626Hyperdrive } from "contracts/test/MockERC4626Hyperdrive.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";
import { HyperdriveUtils } from "../utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";
import { ERC4626ValidationTest } from "./ERC4626Validation.t.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";

contract UsdcERC4626 is ERC4626ValidationTest {
    using FixedPointMath for *;
    using Lib for *;

    function setUp() public override {
        super.setUp();
        vm.startPrank(deployer);
        decimals = 6;
        underlyingToken = IERC20(
            address(new ERC20Mintable("usdc", "USDC", 6, address(this), false))
        );
        token = IERC4626(
            address(
                new MockERC4626(
                    ERC20Mintable(address(underlyingToken)),
                    "yearn usdc",
                    "yUSDC",
                    0,
                    address(0),
                    false
                )
            )
        );
        uint256 monies = 1_000_000_000e6;
        ERC20Mintable(address(underlyingToken)).mint(deployer, monies);
        ERC20Mintable(address(underlyingToken)).mint(alice, monies);
        ERC20Mintable(address(underlyingToken)).mint(bob, monies);

        // Initialize deployer contracts and forwarder
        target0Deployer = address(new ERC4626Target0Deployer());
        target1Deployer = address(new ERC4626Target1Deployer());
        hyperdriveDeployer = address(
            new ERC4626HyperdriveDeployer(target0Deployer, target1Deployer)
        );

        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ForwarderFactory();

        // Hyperdrive factory to produce ERC4626 instances for UsdcERC4626.
        factory = new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                defaultPausers: defaults,
                feeCollector: bob,
                fees: IHyperdrive.Fees(0, 0, 0),
                maxFees: IHyperdrive.Fees(1e18, 1e18, 1e18),
                linkerFactory: address(forwarderFactory),
                linkerCodeHash: forwarderFactory.ERC20LINK_HASH()
            })
        );

        // Config changes required to support ERC4626 with the correct initial share price.
        IHyperdrive.PoolConfig memory config = testConfig(FIXED_RATE);
        config.baseToken = underlyingToken;
        config.initialSharePrice = token.convertToAssets(ONE);
        config.minimumTransactionAmount = 1e6;
        config.minimumShareReserves = 1e6;
        uint256 contribution = 7_500e6;
        vm.stopPrank();
        vm.startPrank(alice);

        factory.updateHyperdriveDeployer(hyperdriveDeployer, true);

        // Set approval to allow initial contribution to factory.
        underlyingToken.approve(address(factory), type(uint256).max);

        // Deploy and set hyperdrive instance.
        hyperdrive = factory.deployAndInitialize(
            config,
            abi.encode(address(token), new address[](0)),
            contribution,
            FIXED_RATE,
            new bytes(0),
            hyperdriveDeployer
        );

        // Setup maximum approvals so transfers don't require further approval.
        underlyingToken.approve(address(hyperdrive), type(uint256).max);
        underlyingToken.approve(address(token), type(uint256).max);
        token.approve(address(hyperdrive), type(uint256).max);
        vm.stopPrank();

        // Start recording events.
        vm.recordLogs();
    }

    function advanceTimeWithYield(
        uint256 timeDelta,
        int256 variableRate
    ) public override {
        vm.warp(block.timestamp + timeDelta);
        (, int256 interest) = HyperdriveUtils.calculateCompoundInterest(
            underlyingToken.balanceOf(address(token)),
            variableRate,
            timeDelta
        );
        if (interest > 0) {
            ERC20Mintable(address(underlyingToken)).mint(
                address(token),
                uint256(interest)
            );
        } else if (interest < 0) {
            ERC20Mintable(address(underlyingToken)).burn(
                address(token),
                uint256(-interest)
            );
        }
    }
}
