// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "test/mocks/MockFixedPointMath.sol";
import "test/3rdPartyLibs/LogExpMath.sol";
import "test/3rdPartyLibs/BalancerErrors.sol";
import "forge-std/console2.sol";


contract FixedPointMathTest is Test {
    function test_pow() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        uint256 x = 300000000000000000000000;
        uint256 y = 977464155968402951;
        uint256 result = mockFixedPointMath.pow(x, y);
        uint256 expected = LogExpMath.pow(x, y);
        assertApproxEqAbs(result, expected, 1e5 wei);

        x = 180000000000000000000000;
        y = 977464155968402951;
        result = mockFixedPointMath.pow(x, y);
        expected = LogExpMath.pow(x, y);
        assertApproxEqAbs(result, expected, 1e5 wei);

        x = 165891671009915386326945;
        y = 1023055417320413264;
        result = mockFixedPointMath.pow(x, y);
        expected = LogExpMath.pow(x, y);
        assertApproxEqAbs(result, expected, 1e5 wei);

        x = 77073744241129234405745;
        y = 1023055417320413264;
        result = mockFixedPointMath.pow(x, y);
        expected = LogExpMath.pow(x, y);
        assertApproxEqAbs(result, expected, 1e5 wei);

        x = 18458206546438581254928;
        y = 1023055417320413264;
        result = mockFixedPointMath.pow(x, y);
        expected = LogExpMath.pow(x, y);
        assertApproxEqAbs(result, expected, 1e5 wei);
    }

    function differential_fuzz_test_pow(uint256 x, uint256 y) public {
        vm.assume(x > 0);
        vm.assume(y > 0);
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        uint256 result = mockFixedPointMath.pow(x, y);
        uint256 expected = LogExpMath.pow(x, y);
        assertApproxEqAbs(result, expected, 1e5 wei);
    }
}
