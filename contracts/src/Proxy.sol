// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { IProxy } from "./interfaces/IProxy.sol";

/// @author DELV
/// @title Proxy
/// @notice A proxy contract that can delegate read and write functions.
/// @dev This contract delegates write access to an extras contract for
///      selectors that meet the criteria defined in `_isExtrasSelector`. If the
///      selector fails this check, we delegate to the data provider contract
///      with read access.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract Proxy is IProxy {
    address public immutable extras;
    address public immutable dataProvider;

    /// @notice Initializes the Hyperdrive proxy.
    /// @param _extras The address of extras contract.
    /// @param _dataProvider The address of the data provider contract.
    constructor(address _extras, address _dataProvider) {
        extras = _extras;
        dataProvider = _dataProvider;
    }

    // solhint-disable payable-fallback
    // solhint-disable no-complex-fallback
    /// @notice Fallback function that delegates to the extras and data provider
    ///         contracts.
    /// @param _data The calldata to forward in the delegated call.
    /// @return returndata The return data from the delegated call.
    fallback(bytes calldata _data) external returns (bytes memory returndata) {
        // If the function selector is one of the selectors delegated to the
        // extras contract, delegate execution to the extras contract.
        bool success;
        if (_isExtrasSelector(bytes4(_data))) {
            (success, returndata) = extras.delegatecall(_data);
            if (!success) {
                assembly {
                    revert(add(returndata, 32), mload(returndata))
                }
            }
            return returndata;
        }

        // Delegatecall into the data provider. We use a force-revert
        // delegatecall pattern to ensure that no state changes were made
        // during the call.
        // solhint-disable avoid-low-level-calls
        (success, returndata) = dataProvider.delegatecall(_data);
        if (success) {
            revert IHyperdrive.UnexpectedSuccess();
        }
        bytes4 selector = bytes4(returndata);
        if (selector != IHyperdrive.ReturnData.selector) {
            assembly {
                revert(add(returndata, 32), mload(returndata))
            }
        }

        // Data returned by the data provider is encoded as the error
        // `ReturnData(bytes)`, so we unwrap the contents and return them.
        assembly {
            mstore(add(returndata, 0x4), sub(mload(returndata), 4))
            returndata := add(returndata, 0x4)
        }

        returndata = abi.decode(returndata, (bytes));

        return returndata;
    }

    /// @dev Checks if the given selector is delegated to the extras contract.
    /// @param _selector The selector to check.
    /// @return A flag indicating if the selector is delegated to the extras
    ///         contract
    function _isExtrasSelector(
        bytes4 _selector
    ) internal pure virtual returns (bool);
}
