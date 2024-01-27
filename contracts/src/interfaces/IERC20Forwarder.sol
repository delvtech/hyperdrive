// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC20 } from "./IERC20.sol";
import { IMultiToken } from "./IMultiToken.sol";

interface IERC20Forwarder is IERC20 {
    /// Errors ///

    error ExpiredDeadline();

    error InvalidSignature();

    error RestrictedZeroAddress();

    /// Functions ///

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function nonces(address user) external view returns (uint256);

    function token() external view returns (IMultiToken);

    function tokenId() external view returns (uint256);

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    // solhint-disable-next-line func-name-mixedcase
    function PERMIT_TYPEHASH() external view returns (bytes32);
}
