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
            fees: IHyperdrive.Fees({
                curve: 0,
                flat: 0,
                governanceLP: 0,
                governanceZombie: 0
            }),
            enableBaseDeposits: false,
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
            closeLongWithSharesTolerance: 20,
            closeShortWithSharesTolerance: 100,
            roundTripLpInstantaneousWithSharesTolerance: 100,
            roundTripLpWithdrawalSharesWithSharesTolerance: 1e3,
            roundTripLongInstantaneousWithSharesUpperBoundTolerance: 1e3,
            roundTripLongInstantaneousWithSharesTolerance: 1e4,
            roundTripLongMaturityWithSharesUpperBoundTolerance: 100,
            roundTripLongMaturityWithSharesTolerance: 3e3,
            roundTripShortInstantaneousWithSharesUpperBoundTolerance: 1e3,
            roundTripShortInstantaneousWithSharesTolerance: 1e3,
            roundTripShortMaturityWithSharesTolerance: 1e3
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
