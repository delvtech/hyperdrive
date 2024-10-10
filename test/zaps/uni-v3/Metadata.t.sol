// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { UNI_V3_ZAP_KIND, VERSION } from "../../../contracts/src/libraries/Constants.sol";
import { UniV3ZapTest } from "./UniV3Zap.t.sol";

contract MetadataTest is UniV3ZapTest {
    /// @notice Ensure that the name is set up correctly.
    function test_name() external view {
        assertEq(zap.name(), NAME);
    }

    /// @notice Ensure that the kind is set up correctly.
    function test_kind() external view {
        assertEq(zap.kind(), UNI_V3_ZAP_KIND);
    }

    /// @notice Ensure that the version is set up correctly.
    function test_version() external view {
        assertEq(zap.version(), VERSION);
    }
}
