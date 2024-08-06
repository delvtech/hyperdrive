// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC20 } from "./IERC20.sol";

interface IRestakeManager {
    /**
     * @notice Returns the ezETH token contract address
     * @dev Getter for public state variable of the ezETH token contract address
     */
    function ezETH() external view returns (address);

    /**
     * @notice Returns the renzo oracle contract address
     * @dev Getter for public state variable of the renzo oracle contract address
     */
    function renzoOracle() external view returns (address);

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

interface IRenzoOracle {
    function lookupTokenValue(
        IERC20 _token,
        uint256 _balance
    ) external view returns (uint256);

    function lookupTokenAmountFromValue(
        IERC20 _token,
        uint256 _value
    ) external view returns (uint256);

    function lookupTokenValues(
        IERC20[] memory _tokens,
        uint256[] memory _balances
    ) external view returns (uint256);

    function calculateMintAmount(
        uint256 _currentValueInProtocol,
        uint256 _newValueAdded,
        uint256 _existingEzETHSupply
    ) external pure returns (uint256);

    function calculateRedeemAmount(
        uint256 _ezETHBeingBurned,
        uint256 _existingEzETHSupply,
        uint256 _currentValueInProtocol
    ) external pure returns (uint256);
}

interface IDepositQueue {
    function depositETHFromProtocol() external payable;

    function totalEarned(address tokenAddress) external view returns (uint256);
}
