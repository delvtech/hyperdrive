/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { console2 as console } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import "forge-std/Vm.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";

import { stdToml } from "forge-std/StdToml.sol";
import { ParseUtils } from "./ParseUtils.sol";

contract PoolDeploymentConfig is ParseUtils {
    using stdToml for string;
    using FixedPointMath for *;

    VmSafe private constant vm =
        VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct PoolDeployment {
        string rpcName;
        uint256 chainId;
        PoolInitialization init;
        PoolTokens tokens;
        PoolBounds bounds;
        PoolAccess access;
        IHyperdrive.Fees fees;
        IHyperdrive.Options options;
    }

    function loadFromTOML(
        PoolDeployment storage p,
        string memory toml
    ) internal {
        p.rpcName = toml.readString("$.rpcName");
        p.chainId = toml.readUint("$.chainId");
        string memory currentKey = "$";
        _parsePoolInitializationFromTOML(p, toml, currentKey);
        _parsePoolTokensFromTOML(p, toml, currentKey);
        _parsePoolBoundsFromTOML(p, toml, currentKey);
        _parsePoolAccessFromTOML(p, toml, currentKey);
        _parsePoolFeesFromTOML(p, toml, currentKey);
        _parsePoolOptionsFromTOML(p, toml, currentKey);
        p.fees.flat = p.fees.flat.mulDivDown(
            p.bounds.positionDuration,
            365 days
        );
    }

    struct PoolInitialization {
        string name;
        address factory;
        address coordinator;
        address registry;
        bytes32 deploymentId;
        bytes32 salt;
        uint256 contribution;
        uint256 fixedAPR;
        uint256 timeStretchAPR;
    }

    function _parsePoolInitializationFromTOML(
        PoolDeployment storage p,
        string memory toml,
        string memory baseKey
    ) internal {
        uint256 fixedAPR = parseUintWithUnits(
            toml,
            string.concat(baseKey, ".fixedAPR")
        );
        p.init = PoolInitialization({
            name: toml.readString(string.concat(baseKey, ".name")),
            factory: toml.readAddress(string.concat(baseKey, ".factory")),
            coordinator: toml.readAddress(
                string.concat(baseKey, ".coordinator")
            ),
            registry: toml.readAddress(string.concat(baseKey, ".registry")),
            deploymentId: bytes32(
                toml.readUint(string.concat(baseKey, ".deploymentId"))
            ),
            salt: bytes32(toml.readUint(string.concat(baseKey, ".salt"))),
            contribution: parseUintWithUnits(
                toml,
                string.concat(baseKey, ".contribution")
            ),
            fixedAPR: fixedAPR,
            // optional: set default to 'fixedAPR'
            timeStretchAPR: parseWithDefault(
                toml,
                string.concat(baseKey, ".timeStretchAPR"),
                fixedAPR
            )
        });
    }

    struct PoolTokens {
        address base;
        address shares;
    }

    function _parsePoolTokensFromTOML(
        PoolDeployment storage p,
        string memory toml,
        string memory baseKey
    ) internal {
        if (vm.keyExistsToml(toml, string.concat(baseKey, ".tokens"))) {
            p.tokens = PoolTokens({
                base: toml.readAddress(string.concat(baseKey, ".tokens.base")),
                shares: toml.readAddress(
                    string.concat(baseKey, ".tokens.shares")
                )
            });
        }
    }

    struct PoolBounds {
        uint256 minimumShareReserves;
        uint256 minimumTransactionAmount;
        uint256 positionDuration;
        uint256 checkpointDuration;
        uint256 timeStretch;
    }

    function _parsePoolBoundsFromTOML(
        PoolDeployment storage p,
        string memory toml,
        string memory baseKey
    ) internal {
        p.bounds = PoolBounds({
            minimumShareReserves: parseUintWithUnits(
                toml,
                string.concat(baseKey, ".bounds.minimumShareReserves")
            ),
            minimumTransactionAmount: parseUintWithUnits(
                toml,
                string.concat(baseKey, ".bounds.minimumTransactionAmount")
            ),
            positionDuration: parseUintWithUnits(
                toml,
                string.concat(baseKey, ".bounds.positionDuration")
            ),
            checkpointDuration: parseUintWithUnits(
                toml,
                string.concat(baseKey, ".bounds.checkpointDuration")
            ),
            timeStretch: parseWithDefault(
                toml,
                string.concat(baseKey, ".bounds.timeStretch"),
                0
            )
        });
    }

    struct PoolAccess {
        address admin;
        address governance;
        address feeCollector;
        address sweepCollector;
    }

    function _parsePoolAccessFromTOML(
        PoolDeployment storage p,
        string memory toml,
        string memory baseKey
    ) internal {
        baseKey = string.concat(baseKey, ".access");
        p.access = PoolAccess({
            admin: toml.readAddress(string.concat(baseKey, ".admin")),
            governance: toml.readAddress(string.concat(baseKey, ".governance")),
            feeCollector: toml.readAddress(
                string.concat(baseKey, ".feeCollector")
            ),
            sweepCollector: toml.readAddress(
                string.concat(baseKey, ".sweepCollector")
            )
        });
    }

    function _parsePoolFeesFromTOML(
        PoolDeployment storage p,
        string memory toml,
        string memory baseKey
    ) internal {
        p.fees = IHyperdrive.Fees({
            curve: parseUintWithUnits(
                toml,
                string.concat(baseKey, ".fees.curve")
            ),
            flat: parseUintWithUnits(
                toml,
                string.concat(baseKey, ".fees.flat")
            ),
            governanceLP: parseUintWithUnits(
                toml,
                string.concat(baseKey, ".fees.governanceLP")
            ),
            governanceZombie: parseUintWithUnits(
                toml,
                string.concat(baseKey, ".fees.governanceZombie")
            )
        });
    }

    function _parsePoolOptionsFromTOML(
        PoolDeployment storage p,
        string memory toml,
        string memory baseKey
    ) internal {
        p.options = IHyperdrive.Options({
            destination: toml.readAddress(
                string.concat(baseKey, ".options.destination")
            ),
            asBase: toml.readBool(string.concat(baseKey, ".options.asBase")),
            extraData: toml.readBytes(
                string.concat(baseKey, ".options.extraData")
            )
        });
    }
}
