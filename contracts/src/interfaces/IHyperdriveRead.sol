// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./IHyperdrive.sol";
import { IMultiTokenRead } from "./IMultiTokenRead.sol";

interface IHyperdriveRead is IMultiTokenRead {
    function baseToken() external view returns (address);

    function getCheckpoint(
        uint256 _checkpointId
    ) external view returns (IHyperdrive.Checkpoint memory);

    function withdrawPool()
        external
        view
        returns (IHyperdrive.WithdrawPool memory);

    function getPoolConfig()
        external
        view
        returns (IHyperdrive.PoolConfig memory);

    function getMarketState()
        external
        view
        returns (IHyperdrive.MarketState memory);

    function getPoolFees() external view returns (uint256);

    function getPoolInfo() external view returns (IHyperdrive.PoolInfo memory);

    function load(
        uint256[] calldata _slots
    ) external view returns (bytes32[] memory);
}
