// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Vm.sol";

import { Test } from "forge-std/Test.sol";
import { Hyperdrive } from "contracts/Hyperdrive.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
import { ERC20PresetFixedSupply } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";

library HyperdriveTestUtils {
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
    function generateTestingMatrix(
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
}

contract HyperdriveTest is Test {
    ERC20PresetFixedSupply baseToken;
    Hyperdrive hyperdrive;

    address alice;
    address bob;

    address minter;
    address deployer;

    function setUp() public virtual {
        alice = createUser("alice");
        bob = createUser("bob");
        deployer = createUser("deployer");
        minter = createUser("minter");

        vm.startPrank(deployer);

        bytes32 linkerCodeHash = bytes32(0);
        ForwarderFactory forwarderFactory = new ForwarderFactory();
        baseToken = new ERC20PresetFixedSupply(
            "DAI Stablecoin",
            "DAI",
            100000000e18,
            minter
        );

        hyperdrive = new Hyperdrive(
            linkerCodeHash,
            address(forwarderFactory),
            baseToken,
            182.5 days,
            22.186877016851916266e18
        );

        vm.stopPrank();

        vm.startPrank(minter);
        baseToken.transfer(alice, 1000e18);
        baseToken.transfer(bob, 1000e18);
        vm.stopPrank();

        vm.startPrank(alice);
        baseToken.approve(address(hyperdrive), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        baseToken.approve(address(hyperdrive), type(uint256).max);
        vm.stopPrank();
    }

    // creates a user
    function createUser(string memory name) public returns (address _user) {
        _user = address(uint160(uint256(keccak256(abi.encode(name)))));
        vm.label(_user, name);
        vm.deal(_user, 100 ether);
    }

    function show() public view {
        console2.log();
        console2.log("Hyperdrive :: %s", address(hyperdrive));
        console2.log("\tbaseToken \t\t= %s", address(hyperdrive.baseToken()));

        uint256 positionDuration = hyperdrive.positionDuration();
        uint256 timeStretch = hyperdrive.timeStretch();
        uint256 initialSharePrice = hyperdrive.initialSharePrice();
        uint256 sharePrice = hyperdrive.sharePrice();
        uint256 shareReserves = hyperdrive.shareReserves();
        uint256 bondReserves = hyperdrive.bondReserves();
        uint256 longsOutstanding = hyperdrive.longsOutstanding();
        uint256 shortsOutstanding = hyperdrive.shortsOutstanding();

        console2.log("\tpositionDuration \t= %s", positionDuration);
        console2.log("\ttimeStretch \t\t= %s", timeStretch);
        console2.log("\tinitialSharePrice \t= %s", initialSharePrice);
        console2.log("\tsharePrice \t\t= %s", sharePrice);
        console2.log("\tshareReserves \t\t= %s", shareReserves);
        console2.log("\tbondReserves \t\t= %s", bondReserves);
        console2.log("\tlongsOutstanding \t= %s", longsOutstanding);
        console2.log("\tshortsOutstanding \t= %s", shortsOutstanding);

        if (shareReserves > 0 || bondReserves > 0) {
            uint256 totalSupply = hyperdrive.totalSupply(0);
            uint256 apr = HyperdriveMath.calculateAPRFromReserves(
                shareReserves,
                bondReserves,
                totalSupply,
                initialSharePrice,
                positionDuration,
                timeStretch
            );
            console2.log("\tAPR \t\t\t= %s", apr);
        }

        console2.log("-----------------------------------");
    }
}
