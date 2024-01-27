// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC20 } from "./IERC20.sol";

interface ILido is IERC20 {
    function submit(address _referral) external payable returns (uint256);

    function transferShares(
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256);

    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256);

    function getSharesByPooledEth(
        uint256 _ethAmount
    ) external view returns (uint256);

    function getPooledEthByShares(
        uint256 _sharesAmount
    ) external view returns (uint256);

    function getBufferedEther() external view returns (uint256);

    function getTotalPooledEther() external view returns (uint256);

    function getTotalShares() external view returns (uint256);

    function sharesOf(address _account) external view returns (uint256);
}
