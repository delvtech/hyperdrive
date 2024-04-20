/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { console2 as console } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import "forge-std/Vm.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";

import { stdToml } from "forge-std/StdToml.sol";

contract ParseUtils {
    using stdToml for string;
    using FixedPointMath for *;

    VmSafe private constant vm =
        VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

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
        return (bytes(s1).length == bytes(s2).length &&
            keccak256(abi.encodePacked(s1)) == keccak256(abi.encodePacked(s2)));
    }
}
