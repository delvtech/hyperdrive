// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { ERC4626HyperdriveCoreDeployer } from "../../../contracts/src/deployers/erc4626/ERC4626HyperdriveCoreDeployer.sol";
import { ERC4626HyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/erc4626/ERC4626HyperdriveDeployerCoordinator.sol";
import { ERC4626Target0Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target0Deployer.sol";
import { ERC4626Target1Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target1Deployer.sol";
import { ERC4626Target2Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target2Deployer.sol";
import { ERC4626Target3Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target3Deployer.sol";
import { ERC4626Target4Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target4Deployer.sol";
import { ERC4626Conversions } from "../../../contracts/src/instances/erc4626/ERC4626Conversions.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../../contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { Lib } from "../../utils/Lib.sol";
import { ERC4626HyperdriveInstanceTest } from "./ERC4626HyperdriveInstanceTest.t.sol";

contract SUSDeHyperdriveTest is ERC4626HyperdriveInstanceTest {
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The cooldown error thrown by SUSDe on withdraw.
    error OperationNotAllowed();

    /// @dev The staked USDe contract.
    IERC4626 internal constant SUSDE =
        IERC4626(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);

    /// @dev The USDe contract.
    IERC20 internal constant USDE =
        IERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);

    /// @dev Whale accounts.
    address internal USDE_TOKEN_WHALE =
        address(0x42862F48eAdE25661558AFE0A630b132038553D0);
    address[] internal baseTokenWhaleAccounts = [USDE_TOKEN_WHALE];
    address internal SUSDE_TOKEN_WHALE =
        address(0x4139cDC6345aFFbaC0692b43bed4D059Df3e6d65);
    address[] internal vaultSharesTokenWhaleAccounts = [SUSDE_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "ERC4626Hyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: USDE,
                vaultSharesToken: IERC20(address(SUSDE)),
                shareTolerance: 1e3,
                minimumShareReserves: 1e18,
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
                // NOTE: SUSDe currently has a cooldown on withdrawals which
                // prevents users from withdrawing as base instantaneously. We still
                // support withdrawing with base since the cooldown can be disabled
                // in the future.
                baseWithdrawError: abi.encodeWithSelector(
                    OperationNotAllowed.selector
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
                roundTripLpInstantaneousWithSharesTolerance: 1e8,
                roundTripLpWithdrawalSharesWithSharesTolerance: 1e8,
                roundTripLongInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithSharesTolerance: 1e5,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 100,
                roundTripLongMaturityWithSharesTolerance: 1e5,
                roundTripShortInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithSharesTolerance: 1e5,
                roundTripShortMaturityWithSharesTolerance: 1e5,
                // The verification tolerances.
                verifyDepositTolerance: 2,
                verifyWithdrawalTolerance: 2
            })
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(20_335_384) {
        // Invoke the Instance testing suite setup.
        super.setUp();
    }

    /// Helpers ///

    /// @dev Advance time and accrue interest. Ethena accrues interest with the
    ///      `transferInRewards` function. Interest accrues every 8 hours and
    ///      vests over the course of the next 8 hours.
    /// @param timeDelta The time to advance.
    /// @param variableRate The variable rate.
    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Get the total base before advancing the time. This is important
        // because it ensures that we are accruing interest on the current
        // amount of total assets rather than the amount of total assets after
        // the current rewards have fully vested.
        (uint256 totalBase, ) = getSupply();

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in the SUSDe market. Since SUSDe's share price is
        // calculated as assets divided shares, we can accrue interest by
        // updating the USDe balance. We modify this in place to allow negative
        // interest accrual.
        (totalBase, ) = totalBase.calculateInterest(variableRate, timeDelta);
        bytes32 balanceLocation = keccak256(abi.encode(address(SUSDE), 2));
        vm.store(address(USDE), bytes32(balanceLocation), bytes32(totalBase));
    }
}
