// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

contract ScenarioTest is HyperdriveTest {
    using HyperdriveUtils for *;

    // FIXME: Update the comment once we write the test
    //
    // This tests a scenario in which a large short is opened and then a large
    // long is opened. The system to should end up in a solvent state.
    function test__largeShortAndLong() external {}
}
