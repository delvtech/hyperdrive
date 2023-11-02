// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

interface IProxy {
    function dataProvider() external view returns (address);

    function extras() external view returns (address);
}
