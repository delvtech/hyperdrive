// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

/// @author DELV
/// @title DevnetSmokeTest
/// @notice This script executes a smoke test against a Hyperdrive devnet.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract DevnetSmokeTest is Script {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    IHyperdrive internal HYPERDRIVE = IHyperdrive(vm.envAddress("HYPERDRIVE"));
    ERC20Mintable internal BASE = ERC20Mintable(vm.envAddress("BASE"));

    function setUp() external {}

    function run() external {
        // Execute all transactions with the ETH_FROM address.
        vm.startBroadcast(msg.sender);

        // Execute the smoke tests.
        _testLong();
        _testShort();

        vm.stopBroadcast();
    }

    function _testLong() internal {
        // Open a long.
        console.log("sender=%s: Opening a long position...", msg.sender);
        BASE.mint(msg.sender, 10_000e18);
        BASE.approve(address(HYPERDRIVE), 10_000e18);
        (uint256 maturityTime, uint256 bondAmount) = HYPERDRIVE.openLong(
            10_000e18,
            0,
            msg.sender,
            true
        );
        console.log(
            "sender=%s: Opened a long position: maturity=%s, amount=%s",
            msg.sender,
            maturityTime,
            bondAmount.toString(18)
        );

        // Close the long.
        console.log("sender=%s: Closing the long position...");
        uint256 baseProceeds = HYPERDRIVE.closeLong(
            maturityTime,
            bondAmount,
            0,
            msg.sender,
            true
        );
        console.log(
            "sender=%s: Closed the long position: baseProceeds=%s",
            msg.sender,
            baseProceeds.toString(18)
        );
    }

    function _testShort() internal {
        // Open a short.
        console.log("sender=%s: Opening a short position...", msg.sender);
        BASE.mint(msg.sender, 10_000e18);
        BASE.approve(address(HYPERDRIVE), 10_000e18);
        (uint256 maturityTime, uint256 bondAmount) = HYPERDRIVE.openShort(
            10_000e18,
            type(uint256).max,
            msg.sender,
            true
        );
        console.log(
            "sender=%s: Opened a short position: maturity=%s, amount=%s",
            msg.sender,
            maturityTime,
            bondAmount.toString(18)
        );

        // Close the short.
        console.log("sender=%s: Closing the short position...");
        uint256 baseProceeds = HYPERDRIVE.closeShort(
            maturityTime,
            bondAmount,
            0,
            msg.sender,
            true
        );
        console.log(
            "sender=%s: Closed the short position: baseProceeds=%s",
            msg.sender,
            baseProceeds.toString(18)
        );
    }

    function createUser(string memory name) internal returns (address _user) {
        _user = address(uint160(uint256(keccak256(abi.encode(name)))));
        vm.label(_user, name);
        vm.deal(_user, 10000 ether);
    }
}
