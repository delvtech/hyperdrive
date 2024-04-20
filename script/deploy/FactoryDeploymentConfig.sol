/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { console2 as console } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import "forge-std/Vm.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ParseUtils } from "./ParseUtils.sol";
import { stdToml } from "forge-std/StdToml.sol";

contract FactoryDeploymentConfig is ParseUtils {
    using stdToml for string;
    using FixedPointMath for *;

    VmSafe private constant vm =
        VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev Specification for the factory deployment.
    struct FactoryDeployment {
        string rpcName;
        uint256 chainId;
        FactoryAccess access;
        FactoryBounds bounds;
        FactoryTokens tokens;
    }

    function loadFromTOML(
        FactoryDeployment storage f,
        string memory toml
    ) internal {
        f.rpcName = toml.readString("$.rpcName");
        f.chainId = toml.readUint("$.chainId");
        _parseFactoryAccessFromTOML(f, toml);
        _parseFactoryBoundsFromTOML(f, toml);
        _parseFactoryTokensFromTOML(f, toml);
    }

    /// @dev Priviledged account specification.
    struct FactoryAccess {
        address admin;
        address governance;
        address[] defaultPausers;
        address feeCollector;
        address sweepCollector;
    }

    function _parseFactoryAccessFromTOML(
        FactoryDeployment storage f,
        string memory toml
    ) internal {
        f.access = FactoryAccess({
            admin: toml.readAddress("$.access.admin"),
            governance: toml.readAddress("$.access.governance"),
            defaultPausers: toml.readAddressArray("$.access.defaultPausers"),
            feeCollector: toml.readAddress("$.access.feeCollector"),
            sweepCollector: toml.readAddress("$.access.sweepCollector")
        });
    }

    /// @dev Parameter ranges for the factory's pools.
    struct FactoryBounds {
        uint256 checkpointDurationResolution;
        uint256 minCheckpointDuration;
        uint256 maxCheckpointDuration;
        uint256 minPositionDuration;
        uint256 maxPositionDuration;
        uint256 minFixedAPR;
        uint256 maxFixedAPR;
        uint256 minTimeStretchAPR;
        uint256 maxTimeStretchAPR;
        IHyperdrive.Fees minFees;
        IHyperdrive.Fees maxFees;
    }

    function _parseFactoryBoundsFromTOML(
        FactoryDeployment storage f,
        string memory toml
    ) internal {
        f.bounds = FactoryBounds({
            checkpointDurationResolution: parseUintWithUnits(
                toml,
                "$.checkpointDuration.resolution"
            ),
            minCheckpointDuration: parseUintWithUnits(
                toml,
                "$.checkpointDuration.min"
            ),
            maxCheckpointDuration: parseUintWithUnits(
                toml,
                "$.checkpointDuration.max"
            ),
            minPositionDuration: parseUintWithUnits(
                toml,
                "$.positionDuration.min"
            ),
            maxPositionDuration: parseUintWithUnits(
                toml,
                "$.positionDuration.max"
            ),
            minFixedAPR: parseUintWithUnits(toml, "$.fixedAPR.min"),
            maxFixedAPR: parseUintWithUnits(toml, "$.fixedAPR.max"),
            minTimeStretchAPR: parseUintWithUnits(toml, "$.timeStretchAPR.min"),
            maxTimeStretchAPR: parseUintWithUnits(toml, "$.timeStretchAPR.max"),
            minFees: IHyperdrive.Fees({
                curve: parseUintWithUnits(toml, "$.fees.curve.min"),
                flat: parseUintWithUnits(toml, "$.fees.flat.min"),
                governanceLP: parseUintWithUnits(
                    toml,
                    "$.fees.governanceLP.min"
                ),
                governanceZombie: parseUintWithUnits(
                    toml,
                    "$.fees.governanceZombie.min"
                )
            }),
            maxFees: IHyperdrive.Fees({
                curve: parseUintWithUnits(toml, "$.fees.curve.max"),
                flat: parseUintWithUnits(toml, "$.fees.flat.max"),
                governanceLP: parseUintWithUnits(
                    toml,
                    "$.fees.governanceLP.max"
                ),
                governanceZombie: parseUintWithUnits(
                    toml,
                    "$.fees.governanceZombie.max"
                )
            })
        });
    }

    struct FactoryTokens {
        address ezeth;
        address lseth;
        address reth;
        address steth;
    }

    function _parseFactoryTokensFromTOML(
        FactoryDeployment storage f,
        string memory toml
    ) internal {
        f.tokens = FactoryTokens({
            ezeth: parseWithDefault(toml, "$.tokens.ezeth", address(0)),
            lseth: parseWithDefault(toml, "$.tokens.lseth", address(0)),
            reth: parseWithDefault(toml, "$.tokens.reth", address(0)),
            steth: parseWithDefault(toml, "$.tokens.steth", address(0))
        });
    }
}
