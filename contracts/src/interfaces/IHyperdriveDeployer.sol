// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "./IHyperdrive.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IHyperdriveDeployer {
    function deploy(
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20 _baseToken,
        uint256 _initialSharePrice,
        uint256 _checkpointsPerTerm,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        IHyperdrive.Fees memory _fees,
        address _governance,
        uint256 _oracleSize,
        uint256 _updateGap,
        bytes32[] memory _extraData
    ) external returns (address);
}
