// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626HyperdriveDeployer } from "contracts/src/instances/ERC4626HyperdriveDeployer.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { ERC4626HyperdriveDeployer } from "contracts/src/instances/ERC4626HyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { MockERC4626Hyperdrive } from "contracts/test/MockERC4626Hyperdrive.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";
import { ERC4626ValidationTest } from "./ERC4626Validation.t.sol";

contract StethERC4626 is ERC4626ValidationTest {
    using FixedPointMath for *;

    function setUp() public override __mainnet_fork(17_376_154) {
        super.setUp();
        underlyingToken = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
        token = IERC4626(0xF9A98A9452485ed55cd3Ce5260C2b71c9807b11a);

        // Note this is wsteth so it could be somewhat problematic in the future
        // depending on whether or not tests interact with wsEth.
        address stethWhale = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        whaleTransfer(stethWhale, underlyingToken, alice);

        _setUp();
    }

    function advanceTimeWithYield(
        uint256 timeDelta,
        int256 variableRate
    ) public override {
        vm.warp(block.timestamp + timeDelta);

        // The Lido storage location that tracks buffered ether reserves. We can
        // simulate the accrual of interest by updating this value.
        bytes32 BUFFERED_ETHER_POSITION = keccak256("lido.Lido.bufferedEther");

        ILido LIDO = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

        // Accrue interest in Lido. Since the share price is given by
        // `getTotalPooledEther() / getTotalShares()`, we can simulate the
        // accrual of interest by multiplying the total pooled ether by the
        // variable rate plus one.
        uint256 bufferedEther = variableRate >= 0
            ? LIDO.getBufferedEther() +
                LIDO.getTotalPooledEther().mulDown(uint256(variableRate))
            : LIDO.getBufferedEther() -
                LIDO.getTotalPooledEther().mulDown(uint256(variableRate));
        vm.store(
            address(LIDO),
            BUFFERED_ETHER_POSITION,
            bytes32(bufferedEther)
        );
    }
}
