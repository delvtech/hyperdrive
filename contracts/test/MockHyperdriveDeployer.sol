// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC20 } from "../src/interfaces/IERC20.sol";
import { IHyperdrive } from "../src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../src/interfaces/IHyperdriveDeployerCoordinator.sol";
import { IHyperdriveTargetDeployer } from "../src/interfaces/IHyperdriveTargetDeployer.sol";
import { VERSION, NUM_TARGETS } from "../src/libraries/Constants.sol";
import { MockHyperdrive } from "./MockHyperdrive.sol";

contract MockHyperdriveDeployer is IHyperdriveDeployerCoordinator {
    string public constant name = "MockHyperdriveDeployer";

    string public constant kind = "MockHyperdriveDeployer";

    string public constant version = VERSION;

    mapping(address => mapping(bytes32 => address)) internal _deployments;

    function deployHyperdrive(
        bytes32 _deploymentId,
        string memory,
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory,
        bytes32
    ) external returns (address) {
        IHyperdrive.PoolConfig memory _config;

        // Copy struct info to PoolConfig
        _config.baseToken = _deployConfig.baseToken;
        _config.linkerFactory = _deployConfig.linkerFactory;
        _config.linkerCodeHash = _deployConfig.linkerCodeHash;
        _config.minimumShareReserves = _deployConfig.minimumShareReserves;
        _config.minimumTransactionAmount = _deployConfig
            .minimumTransactionAmount;
        _config.positionDuration = _deployConfig.positionDuration;
        _config.checkpointDuration = _deployConfig.checkpointDuration;
        _config.timeStretch = _deployConfig.timeStretch;
        _config.governance = _deployConfig.governance;
        _config.feeCollector = _deployConfig.feeCollector;
        _config.fees = _deployConfig.fees;
        _config.initialVaultSharePrice = 1e18; // TODO: Make setter

        // Deploy Hyperdrive and record the address.
        address hyperdrive = address(new MockHyperdrive(_config));
        _deployments[msg.sender][_deploymentId] = hyperdrive;

        return hyperdrive;
    }

    // HACK: This function doesn't return anything because MockHyperdrive
    // deploys the target contracts in it's constructor.
    function deployTarget(
        bytes32,
        IHyperdrive.PoolDeployConfig memory,
        bytes memory,
        uint256,
        bytes32
    ) external pure returns (address target) {
        return address(0);
    }

    function initialize(
        bytes32 _deploymentId,
        address _lp,
        uint256 _contribution,
        uint256 _apr,
        IHyperdrive.Options memory _options
    ) external payable returns (uint256) {
        IHyperdrive hyperdrive = IHyperdrive(
            _deployments[msg.sender][_deploymentId]
        );
        IERC20 baseToken = IERC20(hyperdrive.baseToken());
        baseToken.transferFrom(_lp, address(this), _contribution);
        baseToken.approve(address(hyperdrive), _contribution);
        return hyperdrive.initialize(_contribution, _apr, _options);
    }

    function getNumberOfTargets() external pure returns (uint256) {
        return NUM_TARGETS;
    }
}

// HACK: This contract doesn't return anything because MockHyperdrive deploys
// the target contracts in it's constructor.
contract MockHyperdriveTargetDeployer is IHyperdriveTargetDeployer {
    function deployTarget(
        IHyperdrive.PoolConfig memory,
        bytes memory,
        bytes32
    ) external pure returns (address) {
        return address(0);
    }
}
