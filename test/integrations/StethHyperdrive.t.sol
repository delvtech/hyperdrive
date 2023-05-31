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
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

contract StethHyperdriveTest is HyperdriveTest {
    using FixedPointMath for uint256;

    // FIXME:
    //
    // - [x] Write a `setUp` function that initiates a mainnet fork. - [x] Create wrappers for the Lido contract and WETH9.
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

    address internal STETH_WHALE = 0x1982b2F5814301d4e9a8b0201555376e62F82428;
    address internal WETH_WHALE = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;

    function setUp() public override __mainnet_fork(17_376_154) {
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
        hyperdrive = IHyperdrive(
            address(
                new StethHyperdrive(
                    config,
                    address(dataProvider),
                    bytes32(0),
                    address(0),
                    LIDO
                )
            )
        );

        // FIXME: DRY this up.
        //
        // Send stETH and wETH to the test accounts.
        uint256 stethBalance = IERC20(LIDO).balanceOf(STETH_WHALE);
        whaleTransfer(STETH_WHALE, IERC20(LIDO), stethBalance / 3, alice);
        whaleTransfer(STETH_WHALE, IERC20(LIDO), stethBalance / 3, bob);
        whaleTransfer(STETH_WHALE, IERC20(LIDO), stethBalance / 3, celine);
        uint256 wethBalance = IERC20(LIDO).balanceOf(STETH_WHALE);
        whaleTransfer(STETH_WHALE, IERC20(LIDO), wethBalance / 3, alice);
        whaleTransfer(STETH_WHALE, IERC20(LIDO), wethBalance / 3, bob);
        whaleTransfer(STETH_WHALE, IERC20(LIDO), wethBalance / 3, celine);

        // FIXME: DRY this up.
        //
        // Approve the Hyperdrive to spend stETH and wETH.
        vm.startPrank(alice);
        IERC20(LIDO).approve(address(hyperdrive), type(uint256).max);
        IERC20(WETH).approve(address(hyperdrive), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(bob);
        IERC20(LIDO).approve(address(hyperdrive), type(uint256).max);
        IERC20(WETH).approve(address(hyperdrive), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(celine);
        IERC20(LIDO).approve(address(hyperdrive), type(uint256).max);
        IERC20(WETH).approve(address(hyperdrive), type(uint256).max);
        vm.stopPrank();

        // Alice initializes the pool.
        vm.startPrank(alice);
        initialize(alice, 0.05e18, 10_000e18);
        vm.stopPrank();
    }

    function test__deposit() external {
        vm.startPrank(bob);

        // FIXME: Comment this.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        uint256 hyperdriveSharesBefore = LIDO.sharesOf(address(hyperdrive));

        // Bob opens a long.
        uint256 basePaid = 100e18;
        openLong(bob, basePaid);

        // We ensure that the amount of stETH shares increases and that the
        // total amount of pooled ETH increases.

        // FIXME: Verify that the share balance of the contract equals the
        // share reserves of the contract.
        uint256 expectedShares = basePaid.mulDivDown(
            totalSharesBefore,
            totalPooledEtherBefore
        );
        assertEq(
            LIDO.sharesOf(address(hyperdrive)),
            hyperdriveSharesBefore + expectedShares
        );
        assertEq(LIDO.getTotalShares(), totalSharesBefore + expectedShares);

        // FIXME: Update the comments.
        assertEq(LIDO.getTotalPooledEther(), totalPooledEtherBefore + 100e18);
    }

    function test__withdraw() external {}

    function test__pricePerShare() external {}

    // FIXME: We should add another test that verifies that the correct amount
    // of interest is accrued as stETH updates it's internal state.
}
