// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { IHyperdrive } from "./IHyperdrive.sol";

interface IMorphoBlueHyperdrive is IHyperdrive {
    struct MorphoBlueParams {
        IMorpho morpho;
        address collateralToken;
        address oracle;
        address irm;
        uint256 lltv;
    }

    /// @notice Gets the vault used as this pool's yield source.
    /// @return The compatible yield source.
    function vault() external view returns (address);
}
