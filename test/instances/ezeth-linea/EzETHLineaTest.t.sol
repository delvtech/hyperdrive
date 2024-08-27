// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { EzETHLineaHyperdriveCoreDeployer } from "../../../contracts/src/deployers/ezeth-linea/EzETHLineaHyperdriveCoreDeployer.sol";
import { EzETHLineaHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/ezeth-linea/EzETHLineaHyperdriveDeployerCoordinator.sol";
import { EzETHLineaTarget0Deployer } from "../../../contracts/src/deployers/ezeth-linea/EzETHLineaTarget0Deployer.sol";
import { EzETHLineaTarget1Deployer } from "../../../contracts/src/deployers/ezeth-linea/EzETHLineaTarget1Deployer.sol";
import { EzETHLineaTarget2Deployer } from "../../../contracts/src/deployers/ezeth-linea/EzETHLineaTarget2Deployer.sol";
import { EzETHLineaTarget3Deployer } from "../../../contracts/src/deployers/ezeth-linea/EzETHLineaTarget3Deployer.sol";
import { EzETHLineaTarget4Deployer } from "../../../contracts/src/deployers/ezeth-linea/EzETHLineaTarget4Deployer.sol";
import { HyperdriveFactory } from "../../../contracts/src/factory/HyperdriveFactory.sol";
import { EzETHLineaConversions } from "../../../contracts/src/instances/ezeth-linea/EzETHLineaConversions.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IEzETHLineaHyperdrive } from "../../../contracts/src/interfaces/IEzETHLineaHyperdrive.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IXRenzoDeposit } from "../../../contracts/src/interfaces/IXRenzoDeposit.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { ETH } from "../../../contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { LPMath } from "../../../contracts/src/libraries/LPMath.sol";
import { ERC20ForwarderFactory } from "../../../contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract EzETHLineaHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;
    using stdStorage for StdStorage;

    // The Linea xRenzoDeposit contract.
    IXRenzoDeposit internal constant X_RENZO_DEPOSIT =
        IXRenzoDeposit(0x4D7572040B84b41a6AA2efE4A93eFFF182388F88);

    // The address of the ezETH on Linea.
    IERC20 internal constant EZETH =
        IERC20(0x2416092f143378750bb29b79eD961ab195CcEea5);

    // Whale accounts.
    address internal EZETH_WHALE =
        address(0x0684FC172a0B8e6A65cF4684eDb2082272fe9050);
    address[] internal vaultSharesTokenWhaleAccounts = [EZETH_WHALE];

    // The configuration for the instance testing suite.
    InstanceTestConfig internal __testConfig =
        InstanceTestConfig({
            name: "Hyperdrive",
            kind: "EzETHLineaHyperdrive",
            decimals: 18,
            baseTokenWhaleAccounts: new address[](0),
            vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
            baseToken: IERC20(ETH),
            vaultSharesToken: EZETH,
            shareTolerance: 0,
            minimumShareReserves: 1e15,
            minimumTransactionAmount: 1e15,
            positionDuration: POSITION_DURATION,
            enableBaseDeposits: false,
            enableShareDeposits: true,
            enableBaseWithdraws: false,
            enableShareWithdraws: true,
            baseWithdrawError: abi.encodeWithSelector(
                IHyperdrive.UnsupportedToken.selector
            ),
            isRebasing: false,
            fees: IHyperdrive.Fees({
                curve: 0,
                flat: 0,
                governanceLP: 0,
                governanceZombie: 0
            })
        });

    /// @dev Instantiates the instance testing suite with the configuration.
    constructor() InstanceTest(__testConfig) {}

    /// @dev Forge function that is invoked to setup the testing environment.
    function setUp() public override __linea_fork(8_431_727) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy EzETHLineaHyperdrive instances.
    ///      This is empty since the instance gets all of it's information from
    ///      the deployer coordinators and deployers.
    /// @return The empty extra data.
    function getExtraData() internal pure override returns (bytes memory) {
        return new bytes(0);
    }

    /// @dev Converts base amount to the equivalent about in shares.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        return
            EzETHLineaConversions.convertToShares(X_RENZO_DEPOSIT, baseAmount);
    }

    /// @dev Converts share amount to the equivalent amount in base.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        return
            EzETHLineaConversions.convertToBase(X_RENZO_DEPOSIT, shareAmount);
    }

    /// @dev Deploys the ezETH Linea deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new EzETHLineaHyperdriveDeployerCoordinator(
                    string.concat(__testConfig.name, "DeployerCoordinator"),
                    _factory,
                    address(
                        new EzETHLineaHyperdriveCoreDeployer(X_RENZO_DEPOSIT)
                    ),
                    address(new EzETHLineaTarget0Deployer(X_RENZO_DEPOSIT)),
                    address(new EzETHLineaTarget1Deployer(X_RENZO_DEPOSIT)),
                    address(new EzETHLineaTarget2Deployer(X_RENZO_DEPOSIT)),
                    address(new EzETHLineaTarget3Deployer(X_RENZO_DEPOSIT)),
                    address(new EzETHLineaTarget4Deployer(X_RENZO_DEPOSIT)),
                    X_RENZO_DEPOSIT
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    function getSupply() internal view override returns (uint256, uint256) {
        return (0, EZETH.totalSupply());
    }

    /// @dev Fetches the token balance information of an account.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (account.balance, EZETH.balanceOf(account));
    }

    /// @dev Verifies that deposit accounting is correct when opening positions.
    function verifyDeposit(
        address trader,
        uint256 amountPaid,
        bool asBase,
        uint256 totalBaseBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view override {
        // Base deposits are not supported for this instance.
        if (asBase) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Ensure that the total supply stayed the same.
        (uint256 totalBaseAfter, uint256 totalSharesAfter) = getSupply();
        assertEq(totalBaseAfter, totalBaseBefore);
        assertEq(totalSharesAfter, totalSharesBefore);

        // Ensure that the ETH balances didn't change.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(bob.balance, traderBalancesBefore.ETHBalance);

        // Ensure that the base balances didn't change.
        (
            uint256 hyperdriveBaseAfter,
            uint256 hyperdriveSharesAfter
        ) = getTokenBalances(address(hyperdrive));
        (uint256 traderBaseAfter, uint256 traderSharesAfter) = getTokenBalances(
            trader
        );
        assertEq(hyperdriveBaseAfter, hyperdriveBalancesBefore.baseBalance);
        assertEq(traderBaseAfter, traderBalancesBefore.baseBalance);

        // Ensure that the shares balances were updated correctly.
        assertApproxEqAbs(
            hyperdriveSharesAfter,
            hyperdriveBalancesBefore.sharesBalance +
                hyperdrive.convertToShares(amountPaid),
            2
        );
        assertApproxEqAbs(
            traderSharesAfter,
            traderBalancesBefore.sharesBalance -
                hyperdrive.convertToShares(amountPaid),
            2
        );
    }

    /// @dev Verifies that withdrawal accounting is correct when closing positions.
    function verifyWithdrawal(
        address trader,
        uint256 baseProceeds,
        bool asBase,
        uint256 totalBaseBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view override {
        // Base withdrawals are not supported for this instance.
        if (asBase) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Ensure that the total supply stayed the same.
        (uint256 totalBaseAfter, uint256 totalSharesAfter) = getSupply();
        assertEq(totalBaseAfter, totalBaseBefore);
        assertEq(totalSharesAfter, totalSharesBefore);

        // Ensure that the ETH balances didn't change.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(bob.balance, traderBalancesBefore.ETHBalance);

        // Ensure that the base balances didn't change.
        (
            uint256 hyperdriveBaseAfter,
            uint256 hyperdriveSharesAfter
        ) = getTokenBalances(address(hyperdrive));
        (uint256 traderBaseAfter, uint256 traderSharesAfter) = getTokenBalances(
            trader
        );
        assertEq(hyperdriveBaseAfter, hyperdriveBalancesBefore.baseBalance);
        assertEq(traderBaseAfter, traderBalancesBefore.baseBalance);

        // Ensure that the shares balances were updated correctly.
        assertApproxEqAbs(
            hyperdriveSharesAfter,
            hyperdriveBalancesBefore.sharesBalance -
                hyperdrive.convertToShares(baseProceeds),
            2
        );
        assertApproxEqAbs(
            traderSharesAfter,
            traderBalancesBefore.sharesBalance +
                hyperdrive.convertToShares(baseProceeds),
            2
        );
    }

    /// Getters ///

    function test_getters() external view {
        assertEq(
            address(IEzETHLineaHyperdrive(address(hyperdrive)).xRenzoDeposit()),
            address(X_RENZO_DEPOSIT)
        );
        (, uint256 totalShares) = getTokenBalances(address(hyperdrive));
        assertEq(hyperdrive.totalShares(), totalShares);
    }

    /// LP ///

    function test_round_trip_lp_instantaneous(uint256 _contribution) external {
        // Bob adds liquidity with vault shares.
        _contribution = hyperdrive.convertToShares(
            _contribution.normalizeToRange(0.01e18, 1_000e18)
        );
        uint256 lpShares = addLiquidity(bob, _contribution, false);

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob removes his liquidity with vault shares as the target asset.
        (
            uint256 vaultSharesProceeds,
            uint256 withdrawalShares
        ) = removeLiquidity(bob, lpShares, false);
        uint256 baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);
        assertEq(withdrawalShares, 0);

        // Bob should receive approximately as many vault shares as he
        // contributed since no time as passed and the fees are zero.
        assertApproxEqAbs(vaultSharesProceeds, _contribution, 1);

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            false,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_round_trip_lp_withdrawal_shares(
        uint256 _contribution,
        uint256 _variableRate
    ) external {
        // Bob adds liquidity with vault shares.
        _contribution = hyperdrive.convertToShares(
            _contribution.normalizeToRange(0.01e18, 1_000e18)
        );
        uint256 lpShares = addLiquidity(bob, _contribution, false);

        // Alice opens a large short.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 shortAmount = hyperdrive.calculateMaxShort();
        openShort(alice, shortAmount, false);

        // Bob removes his liquidity with vault shares as the target asset.
        (
            uint256 vaultSharesProceeds,
            uint256 withdrawalShares
        ) = removeLiquidity(bob, lpShares, false);
        assertGt(withdrawalShares, 0);

        // The term passes and interest accrues.
        _variableRate = _variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, int256(_variableRate));
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

        // Bob should be able to redeem all of his withdrawal shares for
        // approximately the LP share price.
        uint256 lpSharePrice = hyperdrive.getPoolInfo().lpSharePrice;
        uint256 withdrawalSharesRedeemed;
        (
            vaultSharesProceeds,
            withdrawalSharesRedeemed
        ) = redeemWithdrawalShares(bob, withdrawalShares, false);
        uint256 baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);
        assertEq(withdrawalSharesRedeemed, withdrawalShares);

        // Bob should receive base approximately equal in value to his present
        // value.
        assertApproxEqAbs(
            baseProceeds,
            withdrawalShares.mulDown(lpSharePrice),
            1_000
        );
    }

    /// Long ///

    function test_open_long_nonpayable() external {
        vm.startPrank(bob);

        // Ensure that sending ETH to `openLong` fails with `asBase` as true.
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openLong{ value: 2e18 }(
            1e18,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Ensure that sending ETH to `openLong` fails with `asBase` as false.
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openLong{ value: 0.5e18 }(
            1e18,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: false,
                extraData: new bytes(0)
            })
        );
    }

    function test_round_trip_long_instantaneous(
        uint256 _vaultSharesPaid
    ) external {
        // Bob opens a long with vault shares.
        _vaultSharesPaid = hyperdrive.convertToShares(
            _vaultSharesPaid.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                hyperdrive.calculateMaxLong()
            )
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            _vaultSharesPaid,
            false
        );

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with vault shares as the target asset.
        uint256 vaultSharesProceeds = closeLong(
            bob,
            maturityTime,
            longAmount,
            false
        );
        uint256 baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

        // NOTE: We add a slight buffer since the fees are zero.
        //
        // Bob should receive less base than he paid since no time as passed.
        assertLt(vaultSharesProceeds, _vaultSharesPaid + 1_000);
        assertApproxEqAbs(vaultSharesProceeds, _vaultSharesPaid, 1e9);

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            false,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_round_trip_long_maturity(
        uint256 _vaultSharesPaid,
        uint256 _variableRate
    ) external {
        // Bob opens a long with vault shares.
        _vaultSharesPaid = hyperdrive.convertToShares(
            _vaultSharesPaid.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                hyperdrive.calculateMaxLong()
            )
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            _vaultSharesPaid,
            false
        );

        // Advance the time and accrue a large amount of interest.
        _variableRate = _variableRate.normalizeToRange(0, 1000e18);
        advanceTime(POSITION_DURATION, int256(_variableRate));

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with vault shares as the target asset.
        uint256 vaultSharesProceeds = closeLong(
            bob,
            maturityTime,
            longAmount,
            false
        );
        uint256 baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

        // Bob should receive almost exactly his bond amount.
        assertLe(baseProceeds, longAmount);
        assertApproxEqAbs(baseProceeds, longAmount, 3_000);

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            false,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// Short ///

    function test_open_short_nonpayable() external {
        vm.startPrank(bob);

        // Ensure that sending ETH to `openLong` fails.
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openShort{ value: 2e18 }(
            1e18,
            1e18,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Ensure that Bob receives a refund when he opens a short with "asBase"
        // set to false and sends ether to the contract.
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openShort{ value: 0.5e18 }(
            1e18,
            1e18,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: false,
                extraData: new bytes(0)
            })
        );
    }

    function test_round_trip_short_instantaneous(
        uint256 _shortAmount
    ) external {
        // Bob opens a short with vault shares.
        _shortAmount = _shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        (uint256 maturityTime, uint256 vaultSharesPaid) = openShort(
            bob,
            _shortAmount,
            false
        );

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with vault shares as the target asset.
        uint256 vaultSharesProceeds = closeShort(
            bob,
            maturityTime,
            _shortAmount,
            false
        );
        uint256 baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

        // Bob should receive approximately as many vault shares as he paid
        // since no time as passed and the fees are zero.
        assertLt(vaultSharesProceeds, vaultSharesPaid + 1_000);
        assertApproxEqAbs(vaultSharesProceeds, vaultSharesPaid, 1e9);

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            false,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_round_trip_short_maturity(
        uint256 _shortAmount,
        uint256 _variableRate
    ) external {
        // Bob opens a short with vault shares.
        _shortAmount = _shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        (uint256 maturityTime, ) = openShort(bob, _shortAmount, false);

        // The term passes and some interest accrues.
        _variableRate = _variableRate.normalizeToRange(0, 2.5e18);
        advanceTime(POSITION_DURATION, int256(_variableRate));

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with vault shares as the target asset.
        uint256 vaultSharesProceeds = closeShort(
            bob,
            maturityTime,
            _shortAmount,
            false
        );
        uint256 baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

        // Bob should receive almost exactly the interest that accrued on the
        // bonds that were shorted.
        assertApproxEqAbs(
            baseProceeds,
            _shortAmount.mulDown(_variableRate),
            1_000
        );

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            false,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// Helpers ///

    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Get the last price.
        (uint256 lastPrice, ) = X_RENZO_DEPOSIT.getMintRate();

        // Accrue interest in the Renzo Linea market. We do this by overwriting
        // the xRenzoDeposit contract's last price.
        (lastPrice, ) = lastPrice.calculateInterest(variableRate, timeDelta);
        bytes32 lastPriceLocation = bytes32(uint256(152));
        vm.store(
            address(X_RENZO_DEPOSIT),
            lastPriceLocation,
            bytes32(lastPrice)
        );
    }
}
