// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { HyperdriveMath } from "../../contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveStorage } from "../../contracts/src/HyperdriveStorage.sol";
import { FixedPointMath } from  "../../contracts/src/libraries/FixedPointMath.sol";

abstract contract HyperdrivePresentValue is HyperdriveStorage {
    using FixedPointMath for uint256;

    function getPresentValueParams(
        uint256 _sharePrice
    )
        external
        view
        returns (HyperdriveMath.PresentValueParams memory presentValue)
    {
        return _getPresentValueParams(_sharePrice);
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
