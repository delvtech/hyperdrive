// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../interfaces/IHyperdrive.sol";

/// @author DELV
/// @title Copy
/// @notice A library that contains copy functions for structs.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library Copy {
    function copy(
        IHyperdrive.PoolInfo memory _info
    ) internal pure returns (IHyperdrive.PoolInfo memory) {
        return
            IHyperdrive.PoolInfo({
                shareReserves: _info.shareReserves,
                bondReserves: _info.bondReserves,
                lpTotalSupply: _info.lpTotalSupply,
                sharePrice: _info.sharePrice,
                longsOutstanding: _info.longsOutstanding,
                longAverageMaturityTime: _info.longAverageMaturityTime,
                longBaseVolume: _info.longBaseVolume,
                shortsOutstanding: _info.shortsOutstanding,
                shortAverageMaturityTime: _info.shortAverageMaturityTime,
                shortBaseVolume: _info.shortBaseVolume,
                withdrawalSharesReadyToWithdraw: _info
                    .withdrawalSharesReadyToWithdraw,
                withdrawalSharesProceeds: _info.withdrawalSharesProceeds
            });
    }
}
