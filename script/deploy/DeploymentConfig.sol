/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { console2 as console } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import "forge-std/Vm.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";

import { stdToml } from "forge-std/StdToml.sol";

contract DeploymentConfig {
    using stdToml for string;
    using FixedPointMath for *;

    mapping(string => NetworkDeployment) deployments;

    VmSafe private constant vm =
        VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// HyperdriveFactoryConfig components.

    /// @dev Linker contract details
    struct Linker {
        address factory;
        bytes32 codeHash;
    }

    /// PoolDeployConfig components.

    struct PoolDeployment {
        PoolInitialization init;
        PoolTokens tokens;
        PoolBounds bounds;
        PoolAccess access; // optional
        IHyperdrive.Fees fees;
        IHyperdrive.Options options;
    }

    struct NetworkDeployment {
        Network network;
        FactoryAccess access;
        FactoryBounds bounds;
        PoolDeployment[] pools;
    }

    function loadFromTOML(
        string memory toml,
        address deployer
    ) internal returns (string memory name) {
        name = toml.readString("$.rpc_name");
        NetworkDeployment storage n = deployments[name];
        // parse network-level configuration
        _parseNetworkFromTOML(n, toml);
        _parseFactoryAccessFromTOML(n, toml);
        _parseFactoryBoundsFromTOML(n, toml);
        // iterate through the pools and parse their configuration
        uint256 idx = 0;
        string memory currentKey = string.concat(
            "$.pools.[",
            vm.toString(idx),
            "]"
        );
        while (vm.keyExistsToml(toml, currentKey)) {
            n.pools.push();
            _parsePoolInitializationFromTOML(n.pools[idx], toml, currentKey);
            _parsePoolTokensFromTOML(n.pools[idx], toml, currentKey);
            _parsePoolBoundsFromTOML(n.pools[idx], toml, currentKey);
            _parsePoolAccessFromTOML(n.pools[idx], toml, currentKey, n.access);
            _parsePoolFeesFromTOML(n.pools[idx], toml, currentKey);
            _parsePoolOptionsFromTOML(n.pools[idx], toml, currentKey, deployer);
            n.pools[idx].fees.flat = n.pools[idx].fees.flat.mulDivDown(
                n.pools[idx].bounds.positionDuration,
                365 days
            );
            idx += 1;
            currentKey = string.concat("$.pools.[", vm.toString(idx), "]");
        }
    }

    /// @dev Target network configuration.
    struct Network {
        string rpc_name;
        uint256 chainId;
    }

    function _parseNetworkFromTOML(
        NetworkDeployment storage n,
        string memory toml
    ) internal {
        n.network = Network({
            rpc_name: toml.readString("$.rpc_name"),
            chainId: toml.readUint("$.chainId")
        });
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
        NetworkDeployment storage n,
        string memory toml
    ) internal {
        n.access = FactoryAccess({
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
        NetworkDeployment storage n,
        string memory toml
    ) internal {
        n.bounds = FactoryBounds({
            checkpointDurationResolution: parseUintWithUnits(
                toml,
                "$.bounds.checkpointDuration.resolution"
            ),
            minCheckpointDuration: parseUintWithUnits(
                toml,
                "$.bounds.checkpointDuration.min"
            ),
            maxCheckpointDuration: parseUintWithUnits(
                toml,
                "$.bounds.checkpointDuration.max"
            ),
            minPositionDuration: parseUintWithUnits(
                toml,
                "$.bounds.positionDuration.min"
            ),
            maxPositionDuration: parseUintWithUnits(
                toml,
                "$.bounds.positionDuration.max"
            ),
            minFixedAPR: parseUintWithUnits(toml, "$.bounds.fixedAPR.min"),
            maxFixedAPR: parseUintWithUnits(toml, "$.bounds.fixedAPR.max"),
            minTimeStretchAPR: parseUintWithUnits(
                toml,
                "$.bounds.timeStretchAPR.min"
            ),
            maxTimeStretchAPR: parseUintWithUnits(
                toml,
                "$.bounds.timeStretchAPR.max"
            ),
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

    struct PoolInitialization {
        string name;
        string poolType;
        bytes32 deploymentId;
        bytes32 salt;
        uint256 contribution;
        uint256 fixedAPR;
        uint256 timeStretchAPR; // optional
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
            poolType: toml.readString(string.concat(baseKey, ".poolType")),
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

    // optional
    struct PoolAccess {
        address governance;
        address feeCollector;
        address sweepCollector;
    }

    function _parsePoolAccessFromTOML(
        PoolDeployment storage p,
        string memory toml,
        string memory baseKey,
        FactoryAccess storage f
    ) internal {
        baseKey = string.concat(baseKey, ".access");
        if (!vm.keyExistsToml(toml, baseKey)) {
            p.access = PoolAccess({
                governance: f.governance,
                feeCollector: f.feeCollector,
                sweepCollector: f.sweepCollector
            });
        }
        p.access = PoolAccess({
            governance: parseWithDefault(
                toml,
                string.concat(baseKey, ".governance"),
                f.governance
            ),
            feeCollector: parseWithDefault(
                toml,
                string.concat(baseKey, ".feeCollector"),
                f.feeCollector
            ),
            sweepCollector: parseWithDefault(
                toml,
                string.concat(baseKey, ".sweepCollector"),
                f.sweepCollector
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
        string memory baseKey,
        address deployer
    ) internal {
        p.options = IHyperdrive.Options({
            destination: parseWithDefault(
                toml,
                string.concat(baseKey, ".options.destination"),
                deployer
            ),
            asBase: toml.readBool(string.concat(baseKey, ".options.asBase")),
            extraData: toml.readBytes(
                string.concat(baseKey, ".options.extraData")
            )
        });
    }

    // bytes32 deploymentId;
    // bytes32 salt;
    // uint256 contribution;
    // uint256 fixedAPR;

    /// @dev Checks whether the key is is defined in the input TOML.
    /// - If the key is defined, return the value associated.
    /// - If the key is not defined, return the provided default value.
    function parseWithDefault(
        string memory toml,
        string memory key,
        address _default
    ) public view returns (address) {
        if (vm.keyExistsToml(toml, key)) return toml.readAddress(key);
        return _default;
    }

    /// @dev Checks whether the key is is defined in the input TOML.
    /// - If the key is defined, return the value associated.
    /// - If the key is not defined, return the provided default value.
    function parseWithDefault(
        string memory toml,
        string memory key,
        uint256 _default
    ) public view returns (uint256) {
        if (vm.keyExistsToml(toml, key)) return parseUintWithUnits(toml, key);
        return _default;
    }

    /// @dev Enables the use of `ether`, `bips`, `gwei`, `weeks`, `days`, and `minutes`
    /// as units in the configuration for uint256 fields by attempting to parse
    /// .unit and .value subkeys for the given base key. If not specified, the unmodified
    /// value is returned.
    function parseUintWithUnits(
        string memory toml,
        string memory baseKey
    ) public view returns (uint256) {
        // No unit specified, return the unmodified value at the baseKey.
        if (!vm.keyExistsToml(toml, string.concat(baseKey, ".unit")))
            return toml.readUint(baseKey);
        // `ether` = value * 1e18
        if (_isEther(toml, baseKey))
            return toml.readUint(string.concat(baseKey, ".value")) * 1e18;
        // `bips` = value * 1e14
        if (_isBips(toml, baseKey))
            return toml.readUint(string.concat(baseKey, ".value")) * 1e14;
        // `gwei` = value * 1e9
        if (_isGwei(toml, baseKey))
            return toml.readUint(string.concat(baseKey, ".value")) * 1e9;
        // `weeks` = value * 1 weeks
        if (_isWeeks(toml, baseKey))
            return toml.readUint(string.concat(baseKey, ".value")) * 1 weeks;
        // `days` = value * 1 days
        if (_isDays(toml, baseKey))
            return toml.readUint(string.concat(baseKey, ".value")) * 1 days;
        // `hours` = value * 1 hours
        if (_isHours(toml, baseKey))
            return toml.readUint(string.concat(baseKey, ".value")) * 1 hours;
        // `minutes` = value * 1 minutes
        if (_isMinutes(toml, baseKey))
            return toml.readUint(string.concat(baseKey, ".value")) * 1 minutes;
        // Something is odd here... revert.
        revert("unit could not be determined for uint field");
    }

    function _isEther(
        string memory toml,
        string memory baseKey
    ) internal pure returns (bool) {
        return
            strEquals(
                toml.readString(string.concat(baseKey, ".unit")),
                "ether"
            );
    }

    function _isBips(
        string memory toml,
        string memory baseKey
    ) internal pure returns (bool) {
        return
            strEquals(toml.readString(string.concat(baseKey, ".unit")), "bips");
    }

    function _isGwei(
        string memory toml,
        string memory baseKey
    ) internal pure returns (bool) {
        return
            strEquals(toml.readString(string.concat(baseKey, ".unit")), "gwei");
    }

    function _isWeeks(
        string memory toml,
        string memory baseKey
    ) internal pure returns (bool) {
        return
            strEquals(
                toml.readString(string.concat(baseKey, ".unit")),
                "weeks"
            );
    }

    function _isDays(
        string memory toml,
        string memory baseKey
    ) internal pure returns (bool) {
        return
            strEquals(toml.readString(string.concat(baseKey, ".unit")), "days");
    }

    function _isHours(
        string memory toml,
        string memory baseKey
    ) internal pure returns (bool) {
        return
            strEquals(
                toml.readString(string.concat(baseKey, ".unit")),
                "hours"
            );
    }

    function _isMinutes(
        string memory toml,
        string memory baseKey
    ) internal pure returns (bool) {
        return
            strEquals(
                toml.readString(string.concat(baseKey, ".unit")),
                "minutes"
            );
    }

    /// @dev Returns whether the two input strings are equivalent.
    function strEquals(
        string memory s1,
        string memory s2
    ) public pure returns (bool) {
        return
            keccak256(abi.encodePacked(s1)) == keccak256(abi.encodePacked(s2));
    }
}
