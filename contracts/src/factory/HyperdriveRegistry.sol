// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveRegistry } from "../interfaces/IHyperdriveRegistry.sol";

contract HyperdriveRegistry is IHyperdriveRegistry {

    address governance;

    mapping(address hyperdrive => mapping(bytes32 key => DataSlot)) hyperdriveInfo;

    constructor() {
        governance = msg.sender;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert IHyperdrive.Unauthorized();
        _;
    }

    /// @notice Allows governance to transfer the governance role.
    /// @param _governance The new governance address.
    function updateGovernance(address _governance) external onlyGovernance {
        governance = _governance;
        emit GovernanceUpdated(_governance);
    }

    /// @notice Allows governance set arbitrary info for a hyperdrive instance.
    /// @param _hyperdrive The hyperdrive instance address.
    /// @param _key The info key.
    function updateHyperdriveInfo(address _hyperdrive, bytes32 _key, bytes32 _data)
        external onlyGovernance
    {
        hyperdriveInfo[_hyperdrive][_key] = DataSlot(block.timestamp, _data);
        emit HyperdriveInfoUpdated(_hyperdrive, _key, _data);
    }

}
