// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IMultiTokenWrite } from "./IMultiTokenWrite.sol";

interface IHyperdriveWrite is IMultiTokenWrite {
    function checkpoint(uint256 _checkpointTime) external;

    function setPauser(address who, bool status) external;

    function pause(bool status) external;

    function initialize(
        uint256 _contribution,
        uint256 _apr,
        address _destination,
        bool _asUnderlying
    ) external;

    function addLiquidity(
        uint256 _contribution,
        uint256 _minApr,
        uint256 _maxApr,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256);

    function removeLiquidity(
        uint256 _shares,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256, uint256);

    function redeemWithdrawalShares(
        uint256 _shares,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256 _proceeds);

    function openLong(
        uint256 _baseAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256);

    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256);

    function openShort(
        uint256 _bondAmount,
        uint256 _maxDeposit,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256);

    function closeShort(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256);

    function setGovernance(address who) external;
}
