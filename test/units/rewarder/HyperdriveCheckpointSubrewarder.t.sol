// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { VmSafe } from "forge-std/Vm.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdriveCheckpointSubrewarder } from "contracts/src/interfaces/IHyperdriveCheckpointSubrewarder.sol";
import { IHyperdriveRegistry } from "contracts/src/interfaces/IHyperdriveRegistry.sol";
import { IHyperdriveGovernedRegistry } from "contracts/src/interfaces/IHyperdriveGovernedRegistry.sol";
import { HyperdriveRegistry } from "contracts/src/factory/HyperdriveRegistry.sol";
import { HyperdriveCheckpointRewarder } from "contracts/src/rewarder/HyperdriveCheckpointRewarder.sol";
import { HyperdriveCheckpointSubrewarder } from "contracts/src/rewarder/HyperdriveCheckpointSubrewarder.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { BaseTest } from "test/utils/BaseTest.sol";
import { Lib } from "test/utils/Lib.sol";

// FIXME: Fill this in.
//
// FIXME: Add integration tests for the full checkpoint -> rewarder -> subrewarder
//        pipeline.
contract HyperdriveCheckpointSubrewarderTest is BaseTest {
    using Lib for *;

    event AdminUpdated(address indexed admin);

    event RegistryUpdated(IHyperdriveRegistry indexed registry);

    event RewardTokenUpdated(IERC20 indexed rewardToken);

    event SourceUpdated(address indexed source);

    event TraderRewardAmountUpdated(uint256 indexed traderRewardAmount);

    event MinterRewardAmountUpdated(uint256 indexed minterRewardAmount);

    string internal constant NAME = "HyperdriveCheckpointRewarder";

    IHyperdriveCheckpointSubrewarder internal subrewarder;
    ERC20Mintable internal token;

    function setUp() public override {
        // Run BaseTests's setUp.
        super.setUp();

        // Deploy the registry.
        vm.stopPrank();
        vm.startPrank(alice);
        IHyperdriveGovernedRegistry registry = IHyperdriveGovernedRegistry(
            new HyperdriveRegistry("HyperdriveRegistry")
        );
        address[] memory instances = new address[](3);
        uint128[] memory data = new uint128[](3);
        address[] memory factories = new address[](3);
        instances[0] = address(0xdeadbeef);
        instances[1] = address(0xbeefbabe);
        instances[2] = address(0xdecaf);
        data[0] = 1;
        data[1] = 1;
        data[2] = 1;
        factories[0] = address(0);
        factories[1] = address(0);
        factories[2] = address(0);
        registry.setInstanceInfo(instances, data, factories);

        // Deploy a mintable reward token.
        token = new ERC20Mintable(
            "Reward",
            "REWARD",
            18,
            address(0),
            false,
            type(uint256).max
        );

        // Deploy the hyperdrive checkpoint subrewarder.
        vm.stopPrank();
        vm.startPrank(alice);
        address source = address(0xc0ffee);
        subrewarder = IHyperdriveCheckpointSubrewarder(
            new HyperdriveCheckpointSubrewarder(
                NAME,
                bob, // rewarder
                source, // source
                registry, // registry
                IERC20(address(token)), // reward token
                2e18, // minter reward amount
                1e18 // trader reward amount
            )
        );

        // Fund the source wallet.
        vm.stopPrank();
        vm.startPrank(source);
        token.mint(source, 100e18);
        token.approve(address(subrewarder), 100e18);

        // Ensure that the admin and name were set correctly.
        assertTrue(subrewarder.name().eq(NAME));
        assertEq(subrewarder.admin(), alice);
        assertEq(subrewarder.rewarder(), bob);
        assertEq(subrewarder.source(), source);
        assertEq(address(subrewarder.registry()), address(registry));
        assertEq(address(subrewarder.rewardToken()), address(token));
        assertEq(subrewarder.minterRewardAmount(), 2e18);
        assertEq(subrewarder.traderRewardAmount(), 1e18);
    }

    function test_updateAdmin_failure_onlyAdmin() external {
        // Ensure that `updateAdmin` can't be called by an address that isn't
        // the admin.
        address newAdmin = bob;
        vm.stopPrank();
        vm.startPrank(newAdmin);
        vm.expectRevert(IHyperdriveCheckpointSubrewarder.Unauthorized.selector);
        subrewarder.updateAdmin(newAdmin);
    }

    function test_updateAdmin_success() external {
        // Ensure that the admin can successfully update the admin address.
        address newAdmin = bob;
        vm.stopPrank();
        vm.startPrank(subrewarder.admin());
        vm.expectEmit(true, true, true, true);
        emit AdminUpdated(bob);
        subrewarder.updateAdmin(newAdmin);

        // Ensure that the admin was updated successfully.
        assertEq(subrewarder.admin(), newAdmin);
    }

    function test_updateSource_failure_onlyAdmin() external {
        // Ensure that `updateSource` can't be called by an address that isn't
        // the admin.
        address newSource = address(0x666);
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveCheckpointSubrewarder.Unauthorized.selector);
        subrewarder.updateSource(newSource);
    }

    function test_updateSource_success() external {
        // Ensure that the admin can successfully update the source address.
        address newSource = address(0x666);
        vm.stopPrank();
        vm.startPrank(subrewarder.admin());
        vm.expectEmit(true, true, true, true);
        emit SourceUpdated(newSource);
        subrewarder.updateSource(newSource);

        // Ensure that the source was updated successfully.
        assertEq(address(subrewarder.source()), address(newSource));
    }

    function test_updateRewardToken_failure_onlyAdmin() external {
        // Ensure that `updateRewardToken` can't be called by an address that isn't
        // the admin.
        IERC20 newRewardToken = IERC20(address(0xabe));
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveCheckpointSubrewarder.Unauthorized.selector);
        subrewarder.updateRewardToken(newRewardToken);
    }

    function test_updateRewardToken_success() external {
        // Ensure that the admin can successfully update the reward token address.
        IERC20 newRewardToken = IERC20(address(0xabe));
        vm.stopPrank();
        vm.startPrank(subrewarder.admin());
        vm.expectEmit(true, true, true, true);
        emit RewardTokenUpdated(newRewardToken);
        subrewarder.updateRewardToken(newRewardToken);

        // Ensure that the reward token was updated successfully.
        assertEq(address(subrewarder.rewardToken()), address(newRewardToken));
    }

    function test_updateRegistry_failure_onlyAdmin() external {
        // Ensure that `updateRegistry` can't be called by an address that isn't
        // the admin.
        IHyperdriveRegistry newRegistry = IHyperdriveRegistry(address(0xabe));
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveCheckpointSubrewarder.Unauthorized.selector);
        subrewarder.updateRegistry(newRegistry);
    }

    function test_updateRegistry_success() external {
        // Ensure that the admin can successfully update the registry address.
        IHyperdriveRegistry newRegistry = IHyperdriveRegistry(address(0xabe));
        vm.stopPrank();
        vm.startPrank(subrewarder.admin());
        vm.expectEmit(true, true, true, true);
        emit RegistryUpdated(newRegistry);
        subrewarder.updateRegistry(newRegistry);

        // Ensure that the registry was updated successfully.
        assertEq(address(subrewarder.registry()), address(newRegistry));
    }

    function test_updateMinterRewardAmount_failure_onlyAdmin() external {
        // Ensure that `updateMinterRewardAmount` can't be called by an address
        // that isn't the admin.
        uint256 newMinterRewardAmount = 5e18;
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveCheckpointSubrewarder.Unauthorized.selector);
        subrewarder.updateMinterRewardAmount(newMinterRewardAmount);
    }

    function test_updateMinterRewardAmount_success() external {
        // Ensure that the admin can successfully update the minter reward amount.
        uint256 newMinterRewardAmount = 5e18;
        vm.stopPrank();
        vm.startPrank(subrewarder.admin());
        vm.expectEmit(true, true, true, true);
        emit MinterRewardAmountUpdated(newMinterRewardAmount);
        subrewarder.updateMinterRewardAmount(newMinterRewardAmount);

        // Ensure that the minter reward amount was updated successfully.
        assertEq(subrewarder.minterRewardAmount(), newMinterRewardAmount);
    }

    function test_updateTraderRewardAmount_failure_onlyAdmin() external {
        // Ensure that `updateTraderRewardAmount` can't be called by an address
        // that isn't the admin.
        uint256 newTraderRewardAmount = 5e18;
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveCheckpointSubrewarder.Unauthorized.selector);
        subrewarder.updateTraderRewardAmount(newTraderRewardAmount);
    }

    function test_updateTraderRewardAmount_success() external {
        // Ensure that the admin can successfully update the trader reward amount.
        uint256 newTraderRewardAmount = 5e18;
        vm.stopPrank();
        vm.startPrank(subrewarder.admin());
        vm.expectEmit(true, true, true, true);
        emit TraderRewardAmountUpdated(newTraderRewardAmount);
        subrewarder.updateTraderRewardAmount(newTraderRewardAmount);

        // Ensure that the trader reward amount was updated successfully.
        assertEq(subrewarder.traderRewardAmount(), newTraderRewardAmount);
    }

    function test_processReward_failure_onlyRewarder() external {
        // Ensure that `processReward` can't be called by an address
        // that isn't the rewarder.
        vm.stopPrank();
        vm.startPrank(celine);
        vm.expectRevert(IHyperdriveCheckpointSubrewarder.Unauthorized.selector);
        subrewarder.processReward(address(0xdeadbeef), celine, 0, true);
    }

    function test_processReward_failure_underfundedSource() external {
        // Increase the minter reward to a value greater than the source's
        // balance.
        vm.stopPrank();
        vm.startPrank(subrewarder.admin());
        subrewarder.updateMinterRewardAmount(
            token.balanceOf(subrewarder.source()) * 2
        );

        // Ensure that `processReward` will fail if the source doesn't have a
        // sufficient balance for the reward.
        vm.stopPrank();
        vm.startPrank(address(subrewarder.rewarder()));
        vm.expectRevert();
        subrewarder.processReward(address(0xdeadbeef), celine, 0, false);
    }

    function test_processReward_success_unregisteredInstance() external {
        // Get the balance of the source account and the claimant before
        // processing the reward.
        uint256 sourceBalanceBefore = token.balanceOf(subrewarder.source());
        uint256 claimantBalanceBefore = token.balanceOf(celine);

        // Ensure that `processReward` succeeds without any tokens being
        // transferred if the instance hasn't been registered in the registry.
        vm.stopPrank();
        vm.startPrank(address(subrewarder.rewarder()));
        (IERC20 rewardToken, uint256 rewardAmount) = subrewarder.processReward(
            address(0xdead),
            celine,
            0,
            false
        );
        assertEq(address(rewardToken), address(subrewarder.rewardToken()));
        assertEq(rewardAmount, 0);

        // Ensure that the token balances haven't changed.
        assertEq(token.balanceOf(subrewarder.source()), sourceBalanceBefore);
        assertEq(token.balanceOf(celine), claimantBalanceBefore);
    }

    function test_processReward_success_minterRewardAmount() external {
        // Get the balance of the source account and the claimant before
        // processing the reward.
        uint256 sourceBalanceBefore = token.balanceOf(subrewarder.source());
        uint256 claimantBalanceBefore = token.balanceOf(celine);

        // Ensure that `processReward` succeeds if the instance has been
        // registered in the registry.
        vm.stopPrank();
        vm.startPrank(address(subrewarder.rewarder()));
        (IERC20 rewardToken, uint256 rewardAmount) = subrewarder.processReward(
            address(0xdeadbeef),
            celine,
            0,
            false
        );
        assertEq(address(rewardToken), address(subrewarder.rewardToken()));
        assertEq(rewardAmount, subrewarder.minterRewardAmount());

        // Ensure that the token balances were updated correctly.
        assertEq(
            token.balanceOf(subrewarder.source()),
            sourceBalanceBefore - rewardAmount
        );
        assertEq(token.balanceOf(celine), claimantBalanceBefore + rewardAmount);
    }

    function test_processReward_success_traderRewardAmount() external {
        // Get the balance of the source account and the claimant before
        // processing the reward.
        uint256 sourceBalanceBefore = token.balanceOf(subrewarder.source());
        uint256 claimantBalanceBefore = token.balanceOf(celine);

        // Ensure that `processReward` succeeds if the instance has been
        // registered in the registry.
        vm.stopPrank();
        vm.startPrank(address(subrewarder.rewarder()));
        (IERC20 rewardToken, uint256 rewardAmount) = subrewarder.processReward(
            address(0xdeadbeef),
            celine,
            0,
            true
        );
        assertEq(address(rewardToken), address(subrewarder.rewardToken()));
        assertEq(rewardAmount, subrewarder.traderRewardAmount());

        // Ensure that the token balances were updated correctly.
        assertEq(
            token.balanceOf(subrewarder.source()),
            sourceBalanceBefore - rewardAmount
        );
        assertEq(token.balanceOf(celine), claimantBalanceBefore + rewardAmount);
    }
}
