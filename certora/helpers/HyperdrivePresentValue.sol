// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { HyperdriveMath } from "../../contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveStorage } from "../../contracts/src/HyperdriveStorage.sol";
import { FixedPointMath } from  "../../contracts/src/libraries/FixedPointMath.sol";

abstract contract HyperdrivePresentValue is HyperdriveStorage {
    using FixedPointMath for uint256;

    function getPresentValue(uint256 _sharePrice) external view returns (uint256) {
        
        HyperdriveMath.PresentValueParams memory params = HyperdriveMath
            .PresentValueParams({
                shareReserves: _marketState.shareReserves,
                bondReserves: _marketState.bondReserves,
                sharePrice: _sharePrice,
                initialSharePrice: _initialSharePrice,
                timeStretch: _timeStretch,
                longsOutstanding: _marketState.longsOutstanding,
                longAverageTimeRemaining: calculateTimeRemaining(
                    uint256(_marketState.longAverageMaturityTime).divUp(
                        1e36
                    ) // scale to seconds
                ),
                shortsOutstanding: _marketState.shortsOutstanding,
                shortAverageTimeRemaining: calculateTimeRemaining(
                    uint256(_marketState.shortAverageMaturityTime).divUp(
                        1e36
                    ) // scale to seconds
                ),
                shortBaseVolume: _marketState.shortBaseVolume
            });
        return HyperdriveMath.calculatePresentValue(params);
    }

    function calculateTimeRemaining(
        uint256 _maturityTime
    ) private view returns (uint256 timeRemaining) {
        uint256 latestCheckpoint = latestCheckpoint();
        timeRemaining = _maturityTime > latestCheckpoint
            ? _maturityTime - latestCheckpoint
            : 0;
        timeRemaining = (timeRemaining).divDown(_positionDuration);
    }

    function latestCheckpoint()
        private
        view
        returns (uint256 latestCheckpoint)
    {
        latestCheckpoint =
            block.timestamp -
            (block.timestamp % _checkpointDuration);
    }
}
