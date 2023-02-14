// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Vm.sol";

import { Test } from "forge-std/Test.sol";
import { Hyperdrive } from "contracts/Hyperdrive.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
import { ERC20PresetFixedSupply } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";

library TestLib {
    // @notice Generates a matrix of all of the different combinations of
    //         inputs for each row.
    // @dev In order to generate the full testing matrix, we need to generate
    //      cases for each value that use all of the input values. In order
    //      to do this, we segment the set of test cases into subsets for each
    //      entry
    // @param inputs A matrix of uint256 values that defines the inputs that
    //        will be used to generate combinations for each row. Increasing the
    //        number of inputs dramatically increases the amount of test cases
    //        that will be generated, so it's important to limit the amount of
    //        inputs to a small number of meaningful values. We use uint256 for
    //        generality, since uint256 can be converted to small width types.
    // @return The full testing matrix.
    function matrix(
        uint256[][] memory inputs
    ) internal pure returns (uint256[][] memory result) {
        // Compute the divisors that will be used to compute the intervals for
        // every input row.
        uint256 base = 1;
        uint256[] memory intervalDivisors = new uint256[](inputs.length);
        for (uint256 i = 0; i < inputs.length; i++) {
            base *= inputs[i].length;
            intervalDivisors[i] = base;
        }
        // Generate the testing matrix.
        result = new uint256[][](base);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = new uint256[](inputs.length);
            for (uint256 j = 0; j < inputs.length; j++) {
                // The idea behind this calculation is that we split the set of
                // test cases into sections and assign one input value to each
                // section. For the first row, we'll create {inputs[0].length}
                // sections and assign these values to sections linearly. For
                // row 1, we'll create inputs[0].length * inputs[1].length
                // sections, and we'll assign the 0th input to the first
                // section, the 1st input to the second section, and continue
                // this process (wrapping around once we run out of input values
                // to allocate).
                //
                // The proof that each row of this procedure is unique is easy
                // using induction. Proving that every row is unique also shows
                // that the full test matrix has been covered.
                result[i][j] = inputs[j][
                    (i / (result.length / intervalDivisors[j])) %
                        inputs[j].length
                ];
            }
        }
        return result;
    }

    function logArray(
        string memory prelude,
        uint256[] memory array
    ) internal view {
        console2.log(prelude, "[");
        for (uint256 i = 0; i < array.length; i++) {
            if (i < array.length - 1) {
                console2.log("        ", array[i], ",");
            } else {
                console2.log("        ", array[i]);
            }
        }
        console2.log("    ]");
        console2.log("");
    }

    function addressToU256(address _addr) internal pure returns (uint256 _num) {
        assembly {
            _num := _addr
        }
    }

    function u256ToAddress(uint256 _num) internal pure returns (address _addr) {
        assembly {
            _addr := _num
        }
    }

    function eq(bytes memory b1, bytes memory b2) public pure returns (bool) {
        return
            keccak256(abi.encodePacked(b1)) == keccak256(abi.encodePacked(b2));
    }

    function neq(bytes memory b1, bytes memory b2) public pure returns (bool) {
        return
            keccak256(abi.encodePacked(b1)) != keccak256(abi.encodePacked(b2));
    }
}

contract BaseTest is Test {
    using FixedPointMath for uint256;

    address alice;
    address bob;
    address eve;

    address minter;
    address deployer;

    function setUp() public virtual {
        alice = createUser("alice");
        bob = createUser("bob");
        eve = createUser("eve");
        deployer = createUser("deployer");
        minter = createUser("minter");
    }

    // creates a user
    function createUser(string memory name) public returns (address _user) {
        _user = address(uint160(uint256(keccak256(abi.encode(name)))));
        vm.label(_user, name);
        vm.deal(_user, 100 ether);
    }
}
