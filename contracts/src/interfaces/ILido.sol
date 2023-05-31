// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface ILido is IERC20 {
    function submit(address _referral) external payable returns (uint256);

    function transferShares(
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256);

    function getTotalPooledEther() external view returns (uint256);

    function getTotalShares() external view returns (uint256);

    function sharesOf(address _account) external view returns (uint256);
}
