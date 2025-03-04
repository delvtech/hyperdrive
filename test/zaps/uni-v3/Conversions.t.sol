// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC4626 } from "../../../contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "../../../contracts/src/interfaces/ILido.sol";
import { ISwapRouter } from "../../../contracts/src/interfaces/ISwapRouter.sol";
import { IWETH } from "../../../contracts/src/interfaces/IWETH.sol";
import { ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { UniV3Zap } from "../../../contracts/src/zaps/UniV3Zap.sol";
import { UniV3ZapTest } from "./UniV3Zap.t.sol";

contract MockUniV3Zap is UniV3Zap {
    constructor(
        string memory _name,
        ISwapRouter _swapRouter,
        IWETH _weth
    ) UniV3Zap(_name, _swapRouter, _weth) {}

    function convertToShares(
        IHyperdrive _hyperdrive,
        uint256 _baseAmount
    ) external view returns (uint256) {
        return _convertToShares(_hyperdrive, _baseAmount);
    }
}

contract ConversionsTest is UniV3ZapTest {
    /// @dev The mock zap contract.
    MockUniV3Zap internal mock;

    /// @dev Set up the mock zap contract.
    function setUp() public override {
        // Run the higher-level setup logic.
        super.setUp();

        // Instantiate the zap contract.
        mock = new MockUniV3Zap(NAME, SWAP_ROUTER, IWETH(WETH));
    }

    /// @notice Ensure that share conversions work properly for the legacy sDAI
    ///         contract.
    function test_convertToShares_sDaiLegacy() external view {
        uint256 shareAmount = mock.convertToShares(
            IHyperdrive(LEGACY_SDAI_HYPERDRIVE),
            ONE
        );
        assertEq(IERC4626(SDAI).convertToShares(ONE), shareAmount);
    }

    /// @notice Ensure that share conversions work properly for the legacy stETH
    ///         contract.
    function test_convertToShares_stETHLegacy() external view {
        uint256 shareAmount = mock.convertToShares(
            IHyperdrive(LEGACY_STETH_HYPERDRIVE),
            ONE
        );
        assertEq(ILido(STETH).getSharesByPooledEth(ONE), shareAmount);
    }

    /// @notice Ensure that share conversions work properly for the Hyperdrive
    ///         instances that aren't legacy instances.
    function test_convertToShares_nonLegacy() external view {
        uint256 shareAmount = mock.convertToShares(
            IHyperdrive(RETH_HYPERDRIVE),
            ONE
        );
        assertEq(RETH_HYPERDRIVE.convertToShares(ONE), shareAmount);
    }
}
