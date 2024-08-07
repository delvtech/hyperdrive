// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC20Forwarder } from "./IERC20Forwarder.sol";
import { IMultiToken } from "./IMultiToken.sol";

interface IERC20ForwarderFactory {
    /// Errors ///

    /// @notice Thrown when a forwarder is deployed to an unexpected address.
    error InvalidForwarderAddress();

    /// Functions ///

    /// @notice Uses create2 to deploy a forwarder at a predictable address as
    ///         part of our ERC20 multitoken implementation.
    /// @param _token The MultiToken targeted by this factory.
    /// @param _tokenId The sub-token ID targeted by this factory.
    /// @return Returns the address of the deployed forwarder.
    function create(
        IMultiToken _token,
        uint256 _tokenId
    ) external returns (IERC20Forwarder);

    /// Getters ///

    /// @notice Gets the ERC20 forwarder factory's name.
    function name() external view returns (string memory);

    /// @notice Gets the ERC20 forwarder factory's kind.
    function kind() external pure returns (string memory);

    /// @notice Gets the ERC20 forwarder factory's version.
    function version() external pure returns (string memory);

    /// @notice Gets the MultiToken and token ID that should be targeted by the
    ///         calling forwarder.
    /// @return The target MultiToken.
    /// @return The target token ID.
    function getDeployDetails() external view returns (IMultiToken, uint256);

    /// @notice Helper to calculate expected forwarder contract addresses.
    /// @param _token The target MultiToken of the forwarder.
    /// @param _tokenId The target token ID of the forwarder.
    /// @return The expected address of the forwarder.
    function getForwarder(
        IMultiToken _token,
        uint256 _tokenId
    ) external view returns (address);

    /// @notice Gets the hash of the bytecode of the ERC20 forwarder contract.
    /// @return The hash of the bytecode of the ERC20 forwarder contract.
    // solhint-disable-next-line func-name-mixedcase
    function ERC20LINK_HASH() external pure returns (bytes32);
}
