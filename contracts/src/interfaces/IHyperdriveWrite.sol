// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IMultiTokenWrite } from "./IMultiTokenWrite.sol";

interface IHyperdriveWrite is IMultiTokenWrite {
    function checkpoint(uint256 _checkpointTime) external;

    function setPauser(address _who, bool _status) external;

    function pause(bool _status) external;

    function initialize(
        uint256 _contribution,
        uint256 _apr,
        address _destination,
        bool _asUnderlying,
        bytes memory _extraData
    ) external payable returns (uint256 lpShares);

    function addLiquidity(
        uint256 _contribution,
        uint256 _minApr,
        uint256 _maxApr,
        address _destination,
        bool _asUnderlying,
        bytes memory _extraData
    ) external payable returns (uint256 lpShares);

    function removeLiquidity(
        uint256 _shares,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying,
        bytes memory _extraData
    ) external returns (uint256 baseProceeds, uint256 withdrawalShares);

    function redeemWithdrawalShares(
        uint256 _shares,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying,
        bytes memory _extraData
    ) external returns (uint256 proceeds, uint256 sharesRedeemed);

    function openLong(
        uint256 _baseAmount,
        uint256 _minOutput,
        uint256 _minSharePrice,
        address _destination,
        bool _asUnderlying,
        bytes memory _extraData
    ) external payable returns (uint256 maturityTime, uint256 bondProceeds);

    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying,
        bytes memory _extraData
    ) external returns (uint256);

    function openShort(
        uint256 _bondAmount,
        uint256 _maxDeposit,
        uint256 _minSharePrice,
        address _destination,
        bool _asUnderlying,
        bytes memory _extraData
    ) external payable returns (uint256 maturityTime, uint256 traderDeposit);

    function closeShort(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying,
        bytes memory _extraData
    ) external returns (uint256);

    function setGovernance(address _who) external;

    function collectGovernanceFee(
        bool _asUnderlying,
        bytes memory _extraData
    ) external returns (uint256 proceeds);
}
