// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { MORPHO_BLUE_HYPERDRIVE_KIND } from "../../libraries/Constants.sol";
import { MorphoBlueBase } from "./MorphoBlueBase.sol";

/// @author DELV
/// @title MorphoBlueTarget0
/// @notice MorphoBlueHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MorphoBlueTarget0 is HyperdriveTarget0, MorphoBlueBase {
    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _morpho The Morpho Blue pool.
    /// @param __colleratalToken The Morpho collateral token.
    /// @param __oracle The Morpho oracle.
    /// @param __irm The Morpho IRM.
    /// @param __lltv The Morpho LLTV.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IMorpho _morpho,
        address __colleratalToken,
        address __oracle,
        address __irm,
        uint256 __lltv
    )
        HyperdriveTarget0(_config)
        MorphoBlueBase(_morpho, __colleratalToken, __oracle, __irm, __lltv)
    {}

    /// @notice Returns the instance's kind.
    /// @return The instance's kind.
    function kind() external pure override returns (string memory) {
        _revert(abi.encode(MORPHO_BLUE_HYPERDRIVE_KIND));
    }

    // FIXME: Add a vault getter and a morpho interface.
}
