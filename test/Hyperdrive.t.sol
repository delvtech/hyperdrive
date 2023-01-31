// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { ERC20PresetFixedSupply } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import { Test } from "forge-std/Test.sol";
import { Hyperdrive } from "contracts/Hyperdrive.sol";
import { ERC20Mintable } from "contracts/tokens/ERC20Mintable.sol";

contract HyperdriveTest is Test {
    address alice = address(uint160(uint256(keccak256("alice"))));

    ERC20PresetFixedSupply baseToken;
    ERC20Mintable lpToken;
    Hyperdrive hyperdrive;

    function setUp() public {
        vm.prank(alice);

        // Instantiate the tokens.
        baseToken = new ERC20PresetFixedSupply(
            "DAI Stablecoin",
            "DAI",
            10.0e18,
            alice
        );
        lpToken = new ERC20Mintable("Hyperdrive LP", "hLP");

        // Instantiate Hyperdrive.
        hyperdrive = new Hyperdrive(
            baseToken,
            lpToken,
            365 days,
            22.186877016851916266e18
        );

        // Transfer admin control of the LP token to Hyperdrive.
        lpToken.changeAdmin(address(hyperdrive));
    }
}
