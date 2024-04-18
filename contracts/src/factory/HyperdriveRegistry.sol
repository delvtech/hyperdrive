// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdriveGovernedRegistry } from "../interfaces/IHyperdriveGovernedRegistry.sol";
import { IHyperdriveRegistry } from "../interfaces/IHyperdriveRegistry.sol";
import { VERSION } from "../libraries/Constants.sol";

contract HyperdriveRegistry is
    IHyperdriveRegistry,
    IHyperdriveGovernedRegistry
{
    /// @notice The registry's name.
    string public name;

    /// @notice The registry's version.
    string public constant version = VERSION;

    /// @notice The registry's governance address.
    address public governance;

    /// @notice A mapping from hyperdrive instances to info associated with
    ///         those instances.
    mapping(address hyperdrive => uint256 data) internal _hyperdriveInfo;

    /// @notice Instantiates the hyperdrive registry.
    /// @param _name The registry's name.
    constructor(string memory _name) {
        governance = msg.sender;
        name = _name;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) {
            revert IHyperdriveGovernedRegistry.Unauthorized();
        }
        _;
    }

    /// @inheritdoc IHyperdriveGovernedRegistry
    function updateGovernance(
        address _governance
    ) external override onlyGovernance {
        governance = _governance;
        emit GovernanceUpdated(_governance);
    }

    /// @inheritdoc IHyperdriveGovernedRegistry
    function setHyperdriveInfo(
        address _hyperdriveInstance,
        uint256 _data
    ) external override onlyGovernance {
        _hyperdriveInfo[_hyperdriveInstance] = _data;
        emit HyperdriveInfoUpdated(_hyperdriveInstance, _data);
    }

    /// @inheritdoc IHyperdriveRegistry
    function getHyperdriveInfo(
        address _hyperdriveInstance
    ) external view override returns (uint256) {
        return _hyperdriveInfo[_hyperdriveInstance];
    }
}
