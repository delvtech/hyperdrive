// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

library Errors {
    /// @dev Throws an InsufficientLiquidity error. We do this in a helper
    ///      function to reduce the code size.
    function throwInsufficientLiquidityError() internal pure {
        revert IHyperdrive.InsufficientLiquidity();
    }
}
