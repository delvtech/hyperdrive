// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

interface IXRenzoDeposit {
    function getMintRate()
        external
        view
        returns (uint256 lastPrice, uint256 lastPriceTimestamp);
}
