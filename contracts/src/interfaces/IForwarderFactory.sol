// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC20Forwarder } from "./IERC20Forwarder.sol";
import { IMultiToken } from "./IMultiToken.sol";

interface IForwarderFactory {
    /// Errors ///

    error InvalidForwarderAddress();

    /// Functions ///

    function create(
        IMultiToken _token,
        uint256 _tokenId
    ) external returns (IERC20Forwarder);

    function getDeployDetails() external view returns (IMultiToken, uint256);

    function getForwarder(
        IMultiToken _token,
        uint256 _tokenId
    ) external view returns (address);

    function ERC20LINK_HASH() external pure returns (bytes32);
}
