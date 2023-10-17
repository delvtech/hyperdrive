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

        console.log("Starting pool config:");
        _logConfig();
        console.log("");

        console.log("Starting pool info:");
        _logInfo();
        console.log("");

        {
            uint256 bondAmount = 110_000e18;
            BASE.mint(msg.sender, bondAmount);
            BASE.approve(address(HYPERDRIVE), bondAmount);
            (, uint256 basePaid) = HYPERDRIVE.openShort(
                bondAmount,
                type(uint256).max,
                0,
                msg.sender,
                true,
                new bytes(0)
            );
            BASE.burn(msg.sender, bondAmount - basePaid);
        }

        {
            uint256 basePaid = 300_000e18;
            BASE.mint(msg.sender, basePaid);
            BASE.approve(address(HYPERDRIVE), basePaid);
            HYPERDRIVE.openLong(basePaid, 0, 0, msg.sender, true, new bytes(0));
        }

        console.log("Ending pool info:");
        _logInfo();
        console.log("");

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
            0,
            msg.sender,
            true,
            new bytes(0)
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
            true,
            new bytes(0)
        );
        console.log(
            "sender=%s: Closed the long position: baseProceeds=%s",
            msg.sender,
            baseProceeds.toString(18)
        );
    }

    function _testLp() internal {
        // Add liquidity.
        console.log("sender=%s: Adding liquidity...", msg.sender);
        BASE.mint(msg.sender, 10_000e18);
        BASE.approve(address(HYPERDRIVE), 10_000e18);
        uint256 lpShares = HYPERDRIVE.addLiquidity(
            10_000e18,
            0,
            type(uint256).max,
            msg.sender,
            true,
            new bytes(0)
        );
        console.log(
            "sender=%s: Added liquidity: lpShares=%s",
            msg.sender,
            lpShares.toString(18)
        );

        // Removing liquidity.
        console.log("sender=%s: Removing liquidity...", msg.sender);
        (uint256 proceeds, uint256 withdrawalShares) = HYPERDRIVE
            .removeLiquidity(lpShares, 0, msg.sender, true, new bytes(0));
        console.log(
            "sender=%s: Removed liquidity: proceeds=%s, withdrawalShares=%s",
            msg.sender,
            proceeds.toString(18),
            withdrawalShares.toString(18)
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
            0,
            msg.sender,
            true,
            new bytes(0)
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
            true,
            new bytes(0)
        );
        console.log(
            "sender=%s: Closed the short position: baseProceeds=%s",
            msg.sender,
            baseProceeds.toString(18)
        );
    }

    function _logConfig() internal view {
        IHyperdrive.PoolConfig memory config = HYPERDRIVE.getPoolConfig();
        console.log(
            "intialSharePrice: %s",
            config.initialSharePrice.toString(18)
        );
        console.log(
            "minimumShareReserves: %s",
            config.minimumShareReserves.toString(18)
        );
        console.log(
            "minimumTransactionAmount: %s",
            config.minimumTransactionAmount.toString(18)
        );
        console.log(
            "positionDuration: %s",
            config.positionDuration.toString(18)
        );
        console.log(
            "checkpointDuration: %s",
            config.checkpointDuration.toString(18)
        );
        console.log("timeStretch: %s", config.timeStretch.toString(18));
        console.log("governance: %s", config.governance);
        console.log("feeCollector: %s", config.feeCollector);
        console.log("curve fee: %s", config.fees.curve.toString(18));
        console.log("flat fee: %s", config.fees.flat.toString(18));
        console.log("governance fee: %s", config.fees.governance.toString(18));
        console.log("oracleSize: %s", config.oracleSize.toString(18));
        console.log("updateGap: %s", config.updateGap.toString(18));
    }

    function _logInfo() internal view {
        IHyperdrive.PoolInfo memory info = HYPERDRIVE.getPoolInfo();
        console.log("shareReserves: %s", info.shareReserves.toString(18));
        console.log("bondReserves: %s", info.bondReserves.toString(18));
        console.log("sharePrice: %s", info.sharePrice.toString(18));
        console.log("longsOutstanding: %s", info.longsOutstanding.toString(18));
        console.log(
            "shortsOutstanding: %s",
            info.shortsOutstanding.toString(18)
        );
    }
}
