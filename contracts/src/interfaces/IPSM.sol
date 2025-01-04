// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import "./IERC20.sol";

interface IPSM {
    // convertToBase = USDS in, SUSDS out
    // convertToShares = SUSDS in, USDS out
    function previewSwapExactIn(
        address assetIn,
        address assetOut,
        uint256 amountIn
    ) external view returns (uint256);

    function rateProvider() external view returns (address);

    function susds() external view returns (IERC20);

    function usds() external view returns (IERC20);

    function totalAssets() external view returns (uint256);

    function totalShares() external view returns (uint256);

    function swapExactIn(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        uint256 referralCode
    ) external returns (uint256 amountOut);
}
