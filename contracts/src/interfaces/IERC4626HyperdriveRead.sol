// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC4626 } from "./IERC4626.sol";
import { IHyperdriveRead } from "./IHyperdriveRead.sol";

interface IERC4626HyperdriveRead is IHyperdriveRead {
    /// @notice Gets the ERC4626 compatible vault used as this pool's yield
    ///         source.
    /// @return The ERC4626 compatible yield source.
    function vault() external view returns (IERC4626);
}
