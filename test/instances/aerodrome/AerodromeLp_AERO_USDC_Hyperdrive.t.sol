// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AerodromeLpHyperdriveInstanceTest } from "./AerodromeLpHyperdriveInstanceTest.t.sol";
import { IGauge } from "aerodrome/interfaces/IGauge.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract AerodromeLp_AERO_USDC_Hyperdrive is AerodromeLpHyperdriveInstanceTest {
    using stdStorage for StdStorage;
    using Strings for uint256;

    /// @dev The Base Aerodrome Lp Token for the AERO-USDC pool.
    IERC20 internal constant AERO_USDC_LP =
        IERC20(0x6cDcb1C4A4D1C3C6d054b27AC5B77e89eAFb971d);

    /// @dev The Aerodrome Gauge contract for the AERO-USDC pool.
    IGauge internal constant AERO_USDC_GAUGE =
        IGauge(0x4F09bAb2f0E15e2A078A227FE1537665F55b8360);

    /// @dev Whale accounts.
    address internal BASE_TOKEN_WHALE =
        0xa000AD1221c525037504452819116941338e70b2;
    address[] internal baseTokenWhaleAccounts = [BASE_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        AerodromeLpHyperdriveInstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "AerodromeLpHyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: new address[](0),
                baseToken: AERO_USDC_LP,
                vaultSharesToken: IERC20(address(0)),
                shareTolerance: 0,
                minimumShareReserves: 1e8,
                minimumTransactionAmount: 1e8,
                positionDuration: POSITION_DURATION,
                fees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                }),
                enableBaseDeposits: true,
                enableShareDeposits: false,
                enableBaseWithdraws: true,
                enableShareWithdraws: false,
                baseWithdrawError: abi.encodeWithSelector(
                    IHyperdrive.UnsupportedToken.selector
                ),
                isRebasing: false,
                shouldAccrueInterest: false,
                // The base test tolerances.
                closeLongWithBaseTolerance: 0,
                closeShortWithBaseUpperBoundTolerance: 10,
                closeShortWithBaseTolerance: 100,
                roundTripLpInstantaneousWithBaseTolerance: 0,
                roundTripLpWithdrawalSharesWithBaseTolerance: 10,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 100,
                roundTripLongInstantaneousWithBaseTolerance: 10,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 0,
                roundTripLongMaturityWithBaseTolerance: 0,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 100,
                roundTripShortInstantaneousWithBaseTolerance: 10,
                roundTripShortMaturityWithBaseTolerance: 0,
                // NOTE: Share deposits and withdrawals are disabled, so these are
                // 0.
                //
                // The share test tolerances.
                closeLongWithSharesTolerance: 0,
                closeShortWithSharesTolerance: 0,
                roundTripLpInstantaneousWithSharesTolerance: 0,
                roundTripLpWithdrawalSharesWithSharesTolerance: 0,
                roundTripLongInstantaneousWithSharesUpperBoundTolerance: 0,
                roundTripLongInstantaneousWithSharesTolerance: 0,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 0,
                roundTripLongMaturityWithSharesTolerance: 0,
                roundTripShortInstantaneousWithSharesUpperBoundTolerance: 0,
                roundTripShortInstantaneousWithSharesTolerance: 0,
                roundTripShortMaturityWithSharesTolerance: 0,
                // The verification tolerances.
                verifyDepositTolerance: 2,
                verifyWithdrawalTolerance: 3
            }),
            AERO_USDC_GAUGE
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __base_fork(21_237_898) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }
}
