// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { MultiTokenDataProvider } from "./MultiTokenDataProvider.sol";
import { HyperdriveStorage } from "./HyperdriveStorage.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { AssetId } from "./libraries/AssetId.sol";

/// @author DELV
/// @title HyperdriveDataProvider
/// @notice The Hyperdrive data provider.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveDataProvider is
    HyperdriveStorage,
    MultiTokenDataProvider
{
    /// Yield Source ///

    ///@notice Loads the share price from the yield source
    ///@return sharePrice The current share price.
    function _pricePerShare()
        internal
        view
        virtual
        returns (uint256 sharePrice);

    /// Getters ///

    /// @notice Gets a specified checkpoint.
    /// @param _checkpointId The checkpoint ID.
    /// @return The checkpoint.
    function getCheckpoint(
        uint256 _checkpointId
    ) external view returns (IHyperdrive.Checkpoint memory) {
        _revert(abi.encode(checkpoints[_checkpointId]));
    }

    /// @notice Gets info about the pool's reserves and other state that is
    ///         important to evaluate potential trades.
    /// @return The PoolInfo struct.
    function getPoolInfo() external view returns (IHyperdrive.PoolInfo memory) {
        IHyperdrive.PoolInfo memory poolInfo = IHyperdrive.PoolInfo({
            shareReserves: marketState.shareReserves,
            bondReserves: marketState.bondReserves,
            lpTotalSupply: _totalSupply[AssetId._LP_ASSET_ID],
            sharePrice: _pricePerShare(),
            longsOutstanding: marketState.longsOutstanding,
            longAverageMaturityTime: marketState.longAverageMaturityTime,
            shortsOutstanding: marketState.shortsOutstanding,
            shortAverageMaturityTime: marketState.shortAverageMaturityTime,
            shortBaseVolume: marketState.shortBaseVolume,
            withdrawalSharesReadyToWithdraw: withdrawPool.readyToWithdraw,
            withdrawalSharesProceeds: withdrawPool.proceeds
        });
        _revert(abi.encode(poolInfo));
    }

    /// @notice Allows plugin data libs to provide getters or other complex
    ///         logic instead of the main.
    /// @param _slots The storage slots the caller wants the data from
    /// @return A raw array of loaded data
    function load(
        uint256[] calldata _slots
    ) external view returns (bytes32[] memory) {
        bytes32[] memory loaded = new bytes32[](_slots.length);

        // Iterate on requested loads and then do them
        for (uint256 i = 0; i < _slots.length; i++) {
            uint256 slot = _slots[i];
            bytes32 data;
            assembly ("memory-safe") {
                data := sload(slot)
            }
            loaded[i] = data;
        }

        _revert(abi.encode(loaded));
    }
}
