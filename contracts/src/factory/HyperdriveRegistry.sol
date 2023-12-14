// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveRegistry } from "../interfaces/IHyperdriveRegistry.sol";

contract HyperdriveRegistry is IHyperdriveRegistry {

    address public governance;

    mapping(address hyperdrive => uint256 data) _hyperdriveInfo;

    constructor() {
        governance = msg.sender;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert IHyperdrive.Unauthorized();
        _;
    }

    /// @inheritdoc IHyperdriveRegistry
    function updateGovernance(address _governance) external override onlyGovernance {
        governance = _governance;
        emit GovernanceUpdated(_governance);
    }

    /// @inheritdoc IHyperdriveRegistry
    function setHyperdriveInfo(address _hyperdriveInstance, uint256 _data)
        external override onlyGovernance
    {
        _hyperdriveInfo[_hyperdriveInstance] = _data;
        emit HyperdriveInfoUpdated(_hyperdriveInstance, _data);
    }

    /// @inheritdoc IHyperdriveRegistry
    function getHyperdriveInfo(address _hyperdriveInstance) external view override returns (uint256) {
        return _hyperdriveInfo[_hyperdriveInstance];
    }

}
