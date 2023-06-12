// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { Errors } from "./libraries/Errors.sol";

/// @author DELV
/// @title DataProvider
/// @notice Implements a fallback function that serves as a generalized getter.
///         This helps contracts stay under the code size limit.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract DataProvider {
    address internal immutable dataProvider;

    /// @notice Initializes the data provider.
    /// @param _dataProvider The address of the data provider.
    constructor(address _dataProvider) {
        dataProvider = _dataProvider;
    }

    // solhint-disable payable-fallback
    // solhint-disable no-complex-fallback
    /// @notice Fallback function that delegates calls to the data provider.
    /// @param _data The data to be passed to the data provider.
    /// @return The return data from the data provider.
    fallback(bytes calldata _data) external returns (bytes memory) {
        // Delegatecall into the data provider. We use a force-revert
        // delegatecall pattern to ensure that no state changes were made
        // during the call to the data provider.
        // solhint-disable avoid-low-level-calls
        (bool success, bytes memory returndata) = dataProvider.delegatecall(
            _data
        );
        if (success) {
            revert Errors.UnexpectedSuccess();
        }
        bytes4 selector = bytes4(returndata);
        if (selector != Errors.ReturnData.selector) {
            assembly {
                revert(add(returndata, 32), mload(returndata))
            }
        }

        assembly {
            mstore(add(returndata, 0x4), sub(mload(returndata), 4))
            returndata := add(returndata, 0x4)
        }

        returndata = abi.decode(returndata, (bytes));

        return returndata;
    }
}
