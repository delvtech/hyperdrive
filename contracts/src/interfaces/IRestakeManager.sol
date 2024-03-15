// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC20 } from "./IERC20.sol";

interface IRestakeManager {
    /**
     * @notice Returns the ezETH token contract address
     */
    function ezETH() external view returns (address);

    /**
     * @notice  Allows a user to deposit ETH into the protocol and get back ezETH
     * @dev     Convenience function to deposit without a referral ID and backwards compatibility
     */
    function depositETH() external payable;

    /// @dev This function calculates the TVLs for each operator delegator by individual token, total for each OD, and total for the protocol.
    /// @return operatorDelegatorTokenTVLs Each OD's TVL indexed by operatorDelegators array by collateralTokens array
    /// @return operatorDelegatorTVLs Each OD's Total TVL in order of operatorDelegators array
    /// @return totalTVL The total TVL across all operator delegators.
    function calculateTVLs()
        external
        view
        returns (uint256[][] memory, uint256[] memory, uint256);
}
