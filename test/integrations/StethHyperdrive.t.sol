// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

// FIXME
import "forge-std/console.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { StethHyperdrive } from "contracts/src/instances/StethHyperdrive.sol";
import { StethHyperdriveDataProvider } from "contracts/src/instances/StethHyperdriveDataProvider.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { IWETH } from "contracts/src/interfaces/IWETH.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

contract StethHyperdriveTest is HyperdriveTest {
    using FixedPointMath for uint256;

    // FIXME:
    //
    // - [x] Write a `setUp` function that initiates a mainnet fork. - [x] Create wrappers for the Lido contract and WETH9.
    // - [x] Deploy a Hyperdrive instance that interacts with Lido.
    // - [x] Set up balances so that transfers of WETH and stETH can be tested.
    // - [x] Test the `deposit` flow.
    // - [x] Test the `withdraw` flow.
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
        vm.startPrank(deployer);
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

        // Fund the test accounts with stETH and WETH.
        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = celine;
        fundAccounts(IERC20(LIDO), STETH_WHALE, accounts);
        fundAccounts(IERC20(WETH), WETH_WHALE, accounts);

        // Alice initializes the pool.
        vm.startPrank(alice);
        initialize(alice, 0.05e18, 10_000e18);
    }

    // FIXME: Try making this a fuzz test.
    function test__depositWeth() external {
        // Get some balance information before the deposit.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a long by depositing WETH.
        uint256 basePaid = 100e18;
        openLong(bob, basePaid);

        // Ensure that the amount of pooled ether increased by the base paid.
        assertEq(LIDO.getTotalPooledEther(), totalPooledEtherBefore + basePaid);

        // Ensure that the WETH balances were updated correctly.
        assertEq(
            WETH.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.wethBalance
        );
        assertEq(WETH.balanceOf(bob), bobBalancesBefore.wethBalance - basePaid);

        // Ensure that the stETH balances were updated correctly.
        assertEq(
            LIDO.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.stethBalance + basePaid
        );
        assertEq(LIDO.balanceOf(bob), bobBalancesBefore.stethBalance);

        // Ensure that the stETH shares were updated correctly.
        uint256 expectedShares = basePaid.mulDivDown(
            totalSharesBefore,
            totalPooledEtherBefore
        );
        assertEq(LIDO.getTotalShares(), totalSharesBefore + expectedShares);
        assertEq(
            LIDO.sharesOf(address(hyperdrive)),
            hyperdriveBalancesBefore.stethShares + expectedShares
        );
        assertEq(LIDO.sharesOf(bob), bobBalancesBefore.stethShares);
    }

    // FIXME: Try making this a fuzz test.
    function test__depositSteth() external {
        // Get some balance information before the deposit.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob opens a long by depositing stETH.
        uint256 basePaid = 100e18;
        openLong(bob, basePaid, false);

        // Ensure that the amount of pooled ether stays the same.
        assertEq(LIDO.getTotalPooledEther(), totalPooledEtherBefore);

        // Ensure that the WETH balances were updated correctly.
        assertEq(
            WETH.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.wethBalance
        );
        assertEq(WETH.balanceOf(bob), bobBalancesBefore.wethBalance);

        // Ensure that the stETH balances were updated correctly.
        assertEq(
            LIDO.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.stethBalance + basePaid
        );
        assertEq(
            LIDO.balanceOf(bob),
            bobBalancesBefore.stethBalance - basePaid
        );

        // Ensure that the stETH shares were updated correctly.
        uint256 expectedShares = basePaid.mulDivDown(
            totalSharesBefore,
            totalPooledEtherBefore
        );
        assertEq(LIDO.getTotalShares(), totalSharesBefore);
        assertEq(
            LIDO.sharesOf(address(hyperdrive)),
            hyperdriveBalancesBefore.stethShares + expectedShares
        );
        assertEq(
            LIDO.sharesOf(bob),
            bobBalancesBefore.stethShares - expectedShares
        );
    }

    // FIXME: Try making this a fuzz test.
    function test__withdrawWeth() external {
        // Bob opens a long.
        uint256 basePaid = 100e18;
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Bob attempts to close his long with WETH as the target asset. This
        // fails since WETH isn't supported as a withdrawal asset.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.UnsupportedToken.selector);
        hyperdrive.closeLong(maturityTime, longAmount, 0, bob, true);
    }

    // FIXME: Try making this a fuzz test.
    function test__withdrawSteth() external {
        // Bob opens a long.
        uint256 basePaid = 100e18;
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Get some balance information before the withdrawal.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with stETH as the target asset.
        uint256 baseProceeds = closeLong(bob, maturityTime, longAmount, false);

        // Ensure that the amount of pooled ether stays the same.
        assertEq(LIDO.getTotalPooledEther(), totalPooledEtherBefore);

        // Ensure that the WETH balances were updated correctly.
        assertEq(
            WETH.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.wethBalance
        );
        assertEq(WETH.balanceOf(bob), bobBalancesBefore.wethBalance);

        // Ensure that the stETH balances were updated correctly.
        assertApproxEqAbs(
            LIDO.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.stethBalance - baseProceeds,
            1
        );
        assertApproxEqAbs(
            LIDO.balanceOf(bob),
            bobBalancesBefore.stethBalance + baseProceeds,
            1
        );

        // Ensure that the stETH shares were updated correctly.
        uint256 expectedShares = baseProceeds.mulDivDown(
            totalSharesBefore,
            totalPooledEtherBefore
        );
        assertApproxEqAbs(LIDO.getTotalShares(), totalSharesBefore, 1);
        assertApproxEqAbs(
            LIDO.sharesOf(address(hyperdrive)),
            hyperdriveBalancesBefore.stethShares - expectedShares,
            1
        );
        assertApproxEqAbs(
            LIDO.sharesOf(bob),
            bobBalancesBefore.stethShares + expectedShares,
            1
        );
    }

    function test__pricePerShare() external {
        // FIXME: We should do the obligatory check against the yield source's
        //        state, but it would also be good to verify that the price per
        //        share matches the amount of shares that will be minted when
        //        a deposit is made.
    }

    // FIXME: We should add another test that verifies that the correct amount
    // of interest is accrued as stETH updates it's internal state.
    //
    // We can probably do this by overwriting the state that holds the pooled
    // ether and the total shares so that we can simulate interest accruing.
    // We should also test negative interest cases.

    // FIXME: Test the flow with stuck tokens.

    // FIXME: Test the receive function to ensure that non-WETH senders can't
    //        send ETH to the contract.

    function fundAccounts(
        IERC20 token,
        address source,
        address[] memory accounts
    ) internal {
        uint256 sourceBalance = token.balanceOf(source);
        for (uint256 i = 0; i < accounts.length; i++) {
            // Transfer the tokens to the account.
            whaleTransfer(
                source,
                token,
                sourceBalance / accounts.length,
                accounts[i]
            );

            // Approve Hyperdrive on behalf of the account.
            vm.startPrank(accounts[i]);
            token.approve(address(hyperdrive), type(uint256).max);
        }
    }

    struct AccountBalances {
        uint256 stethShares;
        uint256 stethBalance;
        uint256 wethBalance;
    }

    function getAccountBalances(
        address account
    ) internal view returns (AccountBalances memory) {
        return
            AccountBalances({
                stethShares: LIDO.sharesOf(account),
                stethBalance: LIDO.balanceOf(account),
                wethBalance: WETH.balanceOf(account)
            });
    }
}
