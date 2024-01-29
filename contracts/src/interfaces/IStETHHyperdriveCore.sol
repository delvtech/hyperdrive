// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC20 } from "./IERC20.sol";
import { IHyperdriveCore } from "./IHyperdriveCore.sol";

interface IStETHHyperdriveCore is IHyperdriveCore {
    /// @notice Transfers the contract's balance of a target token to the fee
    ///         collector address.
    /// @dev Some yield sources (e.g. Morpho) pay rewards directly to this
    ///      contract, but we can't handle distributing them internally. With
    ///      this in mind, we sweep the tokens to the fee collector address to
    ///      then redistribute to users.
    /// @dev WARN: It is unlikely but possible that there is a selector overlap
    ///      with 'transferFrom'. Any integrating contracts should be checked
    ///      for that, as it may result in an unexpected call from this address.
    /// @param _target The target token to sweep.
    function sweep(IERC20 _target) external;
}
