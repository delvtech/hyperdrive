// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { IHyperdriveExtras } from "./interfaces/IHyperdriveExtras.sol";
import { IHyperdriveProxy } from "./interfaces/IHyperdriveProxy.sol";

/// @author DELV
/// @title HyperdriveProxy
/// @notice The Hyperdrive proxy contract. This contract delegates write access
///         to a pre-defined set of functions in a HyperdriveExtras logic
///         contract. In addition to this, it also delegates read access to the
///         HyperdriveDataProvider.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveProxy is IHyperdriveProxy {
    address public immutable extras;
    address public immutable dataProvider;

    // FIXME: Update the documentation
    //
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
    /// @return The return data from the delegated call.
    fallback(bytes calldata _data) external returns (bytes memory) {
        // FIXME: Add the routing logic to HyperdriveExtras.

        // Delegatecall into the data provider. We use a force-revert
        // delegatecall pattern to ensure that no state changes were made
        // during the call to the data provider.
        // solhint-disable avoid-low-level-calls
        (bool success, bytes memory returndata) = dataProvider.delegatecall(
            _data
        );
        if (success) {
            revert IHyperdrive.UnexpectedSuccess();
        }
        bytes4 selector = bytes4(returndata);
        if (selector != IHyperdrive.ReturnData.selector) {
            assembly {
                revert(add(returndata, 32), mload(returndata))
            }
        }

        // Since the useful value is returned in error ReturnData(bytes), the selector for ReturnData
        // must be removed before returning the value
        assembly {
            mstore(add(returndata, 0x4), sub(mload(returndata), 4))
            returndata := add(returndata, 0x4)
        }

        returndata = abi.decode(returndata, (bytes));

        return returndata;
    }
}
