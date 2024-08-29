// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { RsETHLineaHyperdriveCoreDeployer } from "../../../contracts/src/deployers/rseth-linea/RsETHLineaHyperdriveCoreDeployer.sol";
import { RsETHLineaHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/rseth-linea/RsETHLineaHyperdriveDeployerCoordinator.sol";
import { RsETHLineaTarget0Deployer } from "../../../contracts/src/deployers/rseth-linea/RsETHLineaTarget0Deployer.sol";
import { RsETHLineaTarget1Deployer } from "../../../contracts/src/deployers/rseth-linea/RsETHLineaTarget1Deployer.sol";
import { RsETHLineaTarget2Deployer } from "../../../contracts/src/deployers/rseth-linea/RsETHLineaTarget2Deployer.sol";
import { RsETHLineaTarget3Deployer } from "../../../contracts/src/deployers/rseth-linea/RsETHLineaTarget3Deployer.sol";
import { RsETHLineaTarget4Deployer } from "../../../contracts/src/deployers/rseth-linea/RsETHLineaTarget4Deployer.sol";
import { HyperdriveFactory } from "../../../contracts/src/factory/HyperdriveFactory.sol";
import { RsETHLineaConversions } from "../../../contracts/src/instances/rseth-linea/RsETHLineaConversions.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IRsETHLineaHyperdrive } from "../../../contracts/src/interfaces/IRsETHLineaHyperdrive.sol";
import { IRSETHPoolV2 } from "../../../contracts/src/interfaces/IRSETHPoolV2.sol";
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

contract RsETHLineaHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;
    using stdStorage for StdStorage;

    // The Kelp DAO deposit contract on Linea. The rsETH/ETH price is used as
    // the vault share price.
    IRSETHPoolV2 internal constant RSETH_POOL =
        IRSETHPoolV2(0x057297e44A3364139EDCF3e1594d6917eD7688c2);

    // The address of wrsETH on Linea.
    IERC20 internal constant WRSETH =
        IERC20(0xD2671165570f41BBB3B0097893300b6EB6101E6C);

    // Whale accounts.
    address internal WRSETH_WHALE =
        address(0x4DCb388488622e47683EAd1a147947140a31e485);
    address[] internal vaultSharesTokenWhaleAccounts = [WRSETH_WHALE];

    // The configuration for the instance testing suite.
    InstanceTestConfig internal __testConfig =
        InstanceTestConfig({
            name: "Hyperdrive",
            kind: "RsETHLineaHyperdrive",
            decimals: 18,
            baseTokenWhaleAccounts: new address[](0),
            vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
            baseToken: IERC20(ETH),
            vaultSharesToken: WRSETH,
            shareTolerance: 0,
            minimumShareReserves: 1e15,
            minimumTransactionAmount: 1e15,
            positionDuration: POSITION_DURATION,
            fees: IHyperdrive.Fees({
                curve: 0,
                flat: 0,
                governanceLP: 0,
                governanceZombie: 0
            }),
            enableBaseDeposits: true,
            enableShareDeposits: true,
            enableBaseWithdraws: false,
            enableShareWithdraws: true,
            baseWithdrawError: abi.encodeWithSelector(
                IHyperdrive.UnsupportedToken.selector
            ),
            isRebasing: false,
            // NOTE: Base  withdrawals are disabled, so the tolerances are zero.
            //
            // The base test tolerances.
            roundTripLpInstantaneousWithBaseTolerance: 0,
            roundTripLpWithdrawalSharesWithBaseTolerance: 0,
            roundTripLongInstantaneousWithBaseUpperBoundTolerance: 0,
            roundTripLongInstantaneousWithBaseTolerance: 0,
            roundTripLongMaturityWithBaseUpperBoundTolerance: 0,
            roundTripLongMaturityWithBaseTolerance: 0,
            roundTripShortInstantaneousWithBaseUpperBoundTolerance: 0,
            roundTripShortInstantaneousWithBaseTolerance: 0,
            roundTripShortMaturityWithBaseTolerance: 0,
            // The share test tolerances.
            closeLongWithSharesTolerance: 100,
            closeShortWithSharesTolerance: 100,
            roundTripLpInstantaneousWithSharesTolerance: 100,
            roundTripLpWithdrawalSharesWithSharesTolerance: 1e4,
            roundTripLongInstantaneousWithSharesUpperBoundTolerance: 1e3,
            roundTripLongInstantaneousWithSharesTolerance: 1e4,
            roundTripLongMaturityWithSharesUpperBoundTolerance: 100,
            roundTripLongMaturityWithSharesTolerance: 3e3,
            roundTripShortInstantaneousWithSharesUpperBoundTolerance: 1e3,
            roundTripShortInstantaneousWithSharesTolerance: 1e3,
            roundTripShortMaturityWithSharesTolerance: 1e4
        });

    /// @dev Instantiates the instance testing suite with the configuration.
    constructor() InstanceTest(__testConfig) {}

    /// @dev Forge function that is invoked to setup the testing environment.
    function setUp() public override __linea_fork(8_431_727) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy RsETHLineaHyperdrive instances.
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
        return RsETHLineaConversions.convertToShares(RSETH_POOL, baseAmount);
    }

    /// @dev Converts share amount to the equivalent amount in base.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        return RsETHLineaConversions.convertToBase(RSETH_POOL, shareAmount);
    }

    /// @dev Deploys the rsETH Linea deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new RsETHLineaHyperdriveDeployerCoordinator(
                    string.concat(__testConfig.name, "DeployerCoordinator"),
                    _factory,
                    address(new RsETHLineaHyperdriveCoreDeployer(RSETH_POOL)),
                    address(new RsETHLineaTarget0Deployer(RSETH_POOL)),
                    address(new RsETHLineaTarget1Deployer(RSETH_POOL)),
                    address(new RsETHLineaTarget2Deployer(RSETH_POOL)),
                    address(new RsETHLineaTarget3Deployer(RSETH_POOL)),
                    address(new RsETHLineaTarget4Deployer(RSETH_POOL)),
                    RSETH_POOL
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    function getSupply() internal view override returns (uint256, uint256) {
        return (address(RSETH_POOL).balance, WRSETH.totalSupply());
    }

    /// @dev Fetches the token balance information of an account.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (account.balance, WRSETH.balanceOf(account));
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
        if (asBase) {
            // Ensure that the total supply increased the same.
            (uint256 totalBaseAfter, uint256 totalSharesAfter) = getSupply();
            assertEq(totalBaseAfter, totalBaseBefore + amountPaid);
            assertEq(
                totalSharesAfter,
                totalSharesBefore + hyperdrive.convertToShares(amountPaid)
            );

            // Ensure that the trader's ETH balance decreased and that
            // Hyperdrive's stayed the same.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(
                trader.balance,
                traderBalancesBefore.ETHBalance - amountPaid
            );

            // Ensure that the trader's base balance decreased and that
            // Hyperdrive's stayed the same.
            (
                uint256 hyperdriveBaseAfter,
                uint256 hyperdriveSharesAfter
            ) = getTokenBalances(address(hyperdrive));
            (
                uint256 traderBaseAfter,
                uint256 traderSharesAfter
            ) = getTokenBalances(trader);
            assertEq(hyperdriveBaseAfter, hyperdriveBalancesBefore.baseBalance);
            assertEq(
                traderBaseAfter,
                traderBalancesBefore.baseBalance - amountPaid
            );

            // Ensure that the shares balances were updated correctly.
            assertApproxEqAbs(
                hyperdriveSharesAfter,
                hyperdriveBalancesBefore.sharesBalance +
                    hyperdrive.convertToShares(amountPaid),
                2
            );
            assertEq(traderSharesAfter, traderBalancesBefore.sharesBalance);
        } else {
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
            (
                uint256 traderBaseAfter,
                uint256 traderSharesAfter
            ) = getTokenBalances(trader);
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
            address(IRsETHLineaHyperdrive(address(hyperdrive)).rsETHPool()),
            address(RSETH_POOL)
        );
        (, uint256 totalShares) = getTokenBalances(address(hyperdrive));
        assertEq(hyperdrive.totalShares(), totalShares);
    }

    /// Helpers ///

    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Get the last price.
        uint256 lastPrice = RSETH_POOL.getRate();

        // Accrue interest in the Kelp DAO Linea market. We do this by
        // overwriting the Kelp DAO deposit pool's last price.
        (lastPrice, ) = lastPrice.calculateInterest(variableRate, timeDelta);
        bytes32 lastPriceLocation = bytes32(uint256(1));
        vm.store(
            address(RSETH_POOL.rsETHOracle()),
            lastPriceLocation,
            bytes32(lastPrice)
        );
    }
}
