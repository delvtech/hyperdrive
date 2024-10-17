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
import { EzETHLineaConversions } from "../../../contracts/src/instances/ezeth-linea/EzETHLineaConversions.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IEzETHLineaHyperdrive } from "../../../contracts/src/interfaces/IEzETHLineaHyperdrive.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IXRenzoDeposit } from "../../../contracts/src/interfaces/IXRenzoDeposit.sol";
import { ETH } from "../../../contracts/src/libraries/Constants.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract EzETHLineaHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The Linea xRenzoDeposit contract.
    IXRenzoDeposit internal constant X_RENZO_DEPOSIT =
        IXRenzoDeposit(0x4D7572040B84b41a6AA2efE4A93eFFF182388F88);

    /// @dev The address of the ezETH on Linea.
    IERC20 internal constant EZETH =
        IERC20(0x2416092f143378750bb29b79eD961ab195CcEea5);

    /// @dev Whale accounts.
    address internal EZETH_WHALE =
        address(0x0684FC172a0B8e6A65cF4684eDb2082272fe9050);
    address[] internal vaultSharesTokenWhaleAccounts = [EZETH_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
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
                shouldAccrueInterest: true,
                // NOTE: Base  withdrawals are disabled, so the tolerances are zero.
                //
                // The base test tolerances.
                closeLongWithBaseTolerance: 20,
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
                roundTripShortMaturityWithSharesTolerance: 1e3,
                // The verification tolerances.
                verifyDepositTolerance: 2,
                verifyWithdrawalTolerance: 2
            })
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
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
    /// @param baseAmount The base amount.
    /// @return The converted share amount.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        return
            EzETHLineaConversions.convertToShares(X_RENZO_DEPOSIT, baseAmount);
    }

    /// @dev Converts share amount to the equivalent amount in base.
    /// @param shareAmount The share amount.
    /// @return The converted base amount.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        return
            EzETHLineaConversions.convertToBase(X_RENZO_DEPOSIT, shareAmount);
    }

    /// @dev Deploys the ezETH Linea deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    /// @return The coordinator address.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new EzETHLineaHyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
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
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply() internal view override returns (uint256, uint256) {
        return (0, EZETH.totalSupply());
    }

    /// @dev Fetches the token balance information of an account.
    /// @param account The account to query.
    /// @return The balance of base.
    /// @return The balance of vault shares.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (account.balance, EZETH.balanceOf(account));
    }

    /// Getters ///

    /// @dev Test for the additional getters.
    function test_getters() external view {
        assertEq(
            address(IEzETHLineaHyperdrive(address(hyperdrive)).xRenzoDeposit()),
            address(X_RENZO_DEPOSIT)
        );
        (, uint256 totalShares) = getTokenBalances(address(hyperdrive));
        assertEq(hyperdrive.totalShares(), totalShares);
    }

    /// Helpers ///

    /// @dev Advance time and accrue interest.
    /// @param timeDelta The time to advance.
    /// @param variableRate The variable rate.
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
