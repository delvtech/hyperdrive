// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "./IERC20.sol";

/// @author DELV
/// @title IMoonwell
/// @notice The interface file for Moonwell
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
interface IMoonwell is IERC20 {

    function underlying(address) external view returns (address);

    /// @notice Total amount of reserves of the underlying held in this market
    function totalReserves() external view returns (uint256);

    /// @notice Total number of tokens in circulation
    function totalSupply() external view returns (uint256);

    /// @notice Returns the current per-second supply interest rate for this mToken
    /// @return The supply interest rate per timestamp, scaled by 1e18
    function supplyRatePerTimestamp() external view returns (uint);

}