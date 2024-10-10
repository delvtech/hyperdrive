// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IUniV3Zap } from "../../../contracts/src/interfaces/IUniV3Zap.sol";
import { UniV3ZapTest } from "./UniV3Zap.t.sol";

contract ReceiveTest is UniV3ZapTest {
    /// @dev This test ensures that ether can't be sent to the UniV3Zap outside
    ///      of the context of a zap.
    function test_receive_failure() external {
        (bool success, bytes memory data) = address(zap).call{ value: 1 ether }(
            ""
        );
        assertFalse(success);
        assertEq(
            data,
            abi.encodeWithSelector(IUniV3Zap.InvalidTransfer.selector)
        );
    }
}
