// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { ERC20PresetFixedSupply } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import { Test } from "forge-std/Test.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { Hyperdrive } from "contracts/Hyperdrive.sol";
import "contracts/libraries/FixedPointMath.sol";

contract HyperdriveTest is Test {
    address alice = address(uint160(uint256(keccak256("alice"))));

    ERC20PresetFixedSupply baseToken;
    Hyperdrive hyperdrive;

    function setUp() public {
        vm.prank(alice);

        // Instantiate the tokens.
        bytes32 linkerCodeHash = bytes32(0);
        ForwarderFactory forwarderFactory = new ForwarderFactory();
        baseToken = new ERC20PresetFixedSupply(
            "DAI Stablecoin",
            "DAI",
            10.0e18,
            alice
        );

        // Instantiate Hyperdrive.
        hyperdrive = new Hyperdrive({
            _linkerCodeHash: linkerCodeHash,
            _linkerFactoryAddress: address(forwarderFactory),
            _baseToken: baseToken,
            _initialSharePrice: FixedPointMath.ONE_18,
            _positionDuration: 365 days,
            _checkpointDuration: 1 days,
            _timeStretch: 22.186877016851916266e18
        });
    }
}
