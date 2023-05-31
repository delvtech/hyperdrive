// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { StethHyperdrive } from "contracts/src/instances/StethHyperdrive.sol";
import { StethHyperdriveDataProvider } from "contracts/src/instances/StethHyperdriveDataProvider.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { IWETH } from "contracts/src/interfaces/IWETH.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { BaseTest } from "test/utils/BaseTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

contract StethHyperdriveTest is BaseTest {
    using FixedPointMath for uint256;

    // FIXME:
    //
    // - [x] Write a `setUp` function that initiates a mainnet fork.
    // - [x] Create wrappers for the Lido contract and WETH9.
    // - [x] Deploy a Hyperdrive instance that interacts with Lido.
    // - [ ] Set up balances so that transfers of WETH and stETH can be tested.
    // - [ ] Test the `deposit` flow.
    // - [ ] Test the `withdraw` flow.
    // - [ ] Ensure that interest accrues correctly. Is there a way to warp
    //       between mainnet blocks?

    ILido internal constant LIDO =
        ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWETH internal constant WETH =
        IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    StethHyperdrive internal hyperdrive;

    function setUp() public override __mainnet_fork(16_685_972) {
        super.setUp();

        // Deploy the Hyperdrive data provider and instance.
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: IERC20(WETH),
            initialSharePrice: LIDO.getTotalPooledEther().divDown(
                LIDO.getTotalShares()
            ),
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: HyperdriveUtils.calculateTimeStretch(0.05e18),
            governance: address(0),
            feeCollector: address(0),
            fees: IHyperdrive.Fees({ curve: 0, flat: 0, governance: 0 }),
            oracleSize: 10,
            updateGap: 1 hours
        });
        StethHyperdriveDataProvider dataProvider = new StethHyperdriveDataProvider(
                config,
                bytes32(0),
                address(0),
                LIDO
            );
        hyperdrive = new StethHyperdrive(
            config,
            address(dataProvider),
            bytes32(0),
            address(0),
            LIDO
        );
    }
}
