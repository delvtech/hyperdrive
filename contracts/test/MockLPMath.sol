// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { LPMath } from "contracts/src/libraries/LPMath.sol";

contract MockLPMath {
    function calculatePresentValue(
        LPMath.PresentValueParams memory _params
    ) external pure returns (uint256) {
        return LPMath.calculatePresentValue(_params);
    }
}
