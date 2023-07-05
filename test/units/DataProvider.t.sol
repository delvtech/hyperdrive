// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { DataProvider } from "contracts/src/DataProvider.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";

contract MockProvider {
    function get() external pure returns (uint256) {
        _revert(abi.encode(42));
    }

    fallback() external {}

    /// @dev Reverts with the provided bytes. This is useful in getters used
    ///      with the force-revert delegatecall pattern.
    /// @param _bytes The bytes to revert with.
    function _revert(bytes memory _bytes) internal pure {
        revert IHyperdrive.ReturnData(_bytes);
    }
}

contract DataProviderTest is Test {
    DataProvider provider;

    function setUp() public {
        MockProvider mock = new MockProvider();
        provider = new DataProvider(address(mock));
    }

    function testRevertsOnUnderlyingSuccess() public {
        (bool success, bytes memory data) = address(provider).call{ value: 0 }(
            ""
        );

        if (success) {
            revert("Expected revert");
        }

        assert(data.length == 4);
        assert(bytes4(data) == bytes4(keccak256("UnexpectedSuccess()")));
    }

    function testCanFetchData() public {
        (bool success, bytes memory data) = address(provider).call{ value: 0 }(
            abi.encodeWithSignature("get()")
        );

        assert(success);

        assert(data.length == 32);
        assert(uint256(bytes32(data)) == 42);
    }
}
