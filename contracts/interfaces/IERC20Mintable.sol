// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Mintable is IERC20 {
    /// @notice Mints tokens to a target.
    /// @param _target The target of the mint.
    /// @param _amount The amount to mint.
    function mint(address _target, uint256 _amount) external;

    /// @notice Burns tokens from a target.
    /// @param _source The source of the burn.
    /// @param _amount The amount to burn.
    function burn(address _source, uint256 _amount) external;
}
