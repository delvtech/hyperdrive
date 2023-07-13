/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { HyperdriveMath } from "../../contracts/src/libraries/HyperdriveMath.sol";

library HyperdriveMathMock {
    function calculatePresentValue(
        HyperdriveMath.PresentValueParams memory _params
    ) internal pure returns (uint256) {
        return _calculatePresentValue(
            _params.shareReserves,
            _params.bondReserves,
            _params.sharePrice,
            _params.initialSharePrice,
            _params.timeStretch,
            _params.longsOutstanding,
            _params.longAverageTimeRemaining,
            _params.shortsOutstanding,
            _params.shortAverageTimeRemaining,
            _params.shortBaseVolume
        );
    }

    function _calculatePresentValue(
        uint256 z,
        uint256 y,
        uint256 c,
        uint256 mu,
        uint256 ts,
        uint256 ol,
        uint256 tavg_L,
        uint256 os,
        uint256 tavg_S,
        uint256 vol
    ) internal pure returns (uint256) {
        return z + y;
    }
}
