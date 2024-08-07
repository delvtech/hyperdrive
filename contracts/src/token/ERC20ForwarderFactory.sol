// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20Forwarder } from "../interfaces/IERC20Forwarder.sol";
import { IERC20ForwarderFactory } from "../interfaces/IERC20ForwarderFactory.sol";
import { IMultiToken } from "../interfaces/IMultiToken.sol";
import { ERC20_FORWARDER_FACTORY_KIND, VERSION } from "../libraries/Constants.sol";
import { ERC20Forwarder } from "./ERC20Forwarder.sol";

/// @author DELV
/// @title ERC20ForwarderFactory
/// @notice Our MultiToken contract consists of fungible sub-tokens that
///         are similar to ERC20 tokens. In order to support ERC20 compatibility
///         we can deploy interfaces which are ERC20s.
/// @dev This factory deploys them using create2 so that the multi token can do
///      cheap verification of the interfaces before they access sensitive
///      functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC20ForwarderFactory is IERC20ForwarderFactory {
    /// @notice The ERC20 forwarder factory's name.
    string public name;

    /// @notice The ERC20 forwarder factory's kind.
    string public constant kind = ERC20_FORWARDER_FACTORY_KIND;

    /// @notice The ERC20 forwarder factory's version.
    string public constant version = VERSION;

    /// @notice The transient MultiToken addressed used in deployment.
    IMultiToken private _token = IMultiToken(address(1));

    /// @notice The transient token ID addressed used in deployment.
    uint256 private _tokenId = 1;

    /// @notice The hash of the bytecode of the ERC20 forwarder contract.
    bytes32 public constant ERC20LINK_HASH =
        keccak256(type(ERC20Forwarder).creationCode);

    /// @notice Initializes the ERC20 forwarder factory.
    /// @param _name The name of the ERC20 forwarder factory.
    constructor(string memory _name) {
        name = _name;
    }

    /// @notice Uses create2 to deploy a forwarder at a predictable address as
    ///         part of our ERC20 multitoken implementation.
    /// @param __token The MultiToken targeted by this factory.
    /// @param __tokenId The sub-token ID targeted by this factory.
    /// @return Returns the address of the deployed forwarder.
    function create(
        IMultiToken __token,
        uint256 __tokenId
    ) external returns (IERC20Forwarder) {
        // Set the transient state variables before deploy.
        _tokenId = __tokenId;
        _token = __token;

        // The salt is the _tokenId hashed with the multi token.
        bytes32 salt = keccak256(abi.encode(__token, __tokenId));

        // Deploy using create2 with that salt.
        ERC20Forwarder deployed = new ERC20Forwarder{ salt: salt }();

        // As a consistency check we check that this is in the right address.
        if (!(address(deployed) == getForwarder(__token, __tokenId))) {
            revert IERC20ForwarderFactory.InvalidForwarderAddress();
        }

        // Reset the transient state.
        _token = IMultiToken(address(1));
        _tokenId = 1;

        // Return the deployed forwarder.
        return deployed;
    }

    /// @notice Gets the MultiToken and token ID that should be targeted by the
    ///         calling forwarder.
    /// @dev The target MultiToken and token ID are transient state variables
    ///      that are set during deployment.
    /// @return The target MultiToken.
    /// @return The target token ID.
    function getDeployDetails() external view returns (IMultiToken, uint256) {
        return (_token, _tokenId);
    }

    /// @notice Helper to calculate expected forwarder contract addresses.
    /// @param __token The target MultiToken of the forwarder.
    /// @param __tokenId The target token ID of the forwarder.
    /// @return The expected address of the forwarder.
    function getForwarder(
        IMultiToken __token,
        uint256 __tokenId
    ) public view virtual returns (address) {
        // Get the salt and hash to predict the address.
        bytes32 salt = keccak256(abi.encode(__token, __tokenId));
        bytes32 addressBytes = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, ERC20LINK_HASH)
        );

        // Beautiful type safety from the solidity language.
        return address(uint160(uint256(addressBytes)));
    }
}
