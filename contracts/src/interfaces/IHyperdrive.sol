// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "./IMultiToken.sol";

interface IHyperdrive is IMultiToken {
    function initialize(
        uint256 _contribution,
        uint256 _apr,
        address _destination,
        bool _asUnderlying
    ) external;

    function addLiquidity(
        uint256 _contribution,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256);

    function removeLiquidity(
        uint256 _shares,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256, uint256, uint256);

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
}
