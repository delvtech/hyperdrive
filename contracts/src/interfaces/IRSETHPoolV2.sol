// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IRSETHPoolV2 {
    function rsETHOracle() external view returns (address);

    function wrsETH() external view returns (address);

    function getRate() external view returns (uint256);
}
