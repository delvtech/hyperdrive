// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

interface IFiatTokenProxy {
    function implementation() external view returns (address);
}
