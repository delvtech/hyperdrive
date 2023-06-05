// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

interface Pot {
    function chi() external view returns (uint256);

    function rho() external view returns (uint256);

    function dsr() external view returns (uint256);
}

interface DsrManager {
    function dai() external view returns (address);

    function pot() external view returns (address);

    function pieOf(address) external view returns (uint256);

    function daiBalance(address) external returns (uint256);

    function join(address, uint256) external;

    function exit(address, uint256) external;

    function exitAll(address) external;
}
