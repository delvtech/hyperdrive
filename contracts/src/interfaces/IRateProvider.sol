// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

interface IRateProvider {
    function getChi() external view returns (uint256);

    function getRho() external view returns (uint256);

    function getSSR() external view returns (uint256);

    function getConversionRate() external view returns (uint256);
}
