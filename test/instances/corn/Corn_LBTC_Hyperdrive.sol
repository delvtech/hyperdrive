// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { ICornSilo } from "../../../contracts/src/interfaces/ICornSilo.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { CornHyperdriveInstanceTest } from "./CornHyperdriveInstanceTest.t.sol";

contract Corn_LBTC_Hyperdrive is CornHyperdriveInstanceTest {
    using stdStorage for StdStorage;

    /// @dev The mainnet Corn Silo.
    ICornSilo internal constant CORN_SILO =
        ICornSilo(0x8bc93498b861fd98277c3b51d240e7E56E48F23c);

    /// @dev The mainnet LBTC token.
    IERC20 internal constant LBTC =
        IERC20(0x8236a87084f8B84306f72007F36F2618A5634494);

    /// @dev Whale accounts.
    address internal BASE_TOKEN_WHALE =
        0x208567a5FF415f1081fa0f47d3A1bD60b8B03199;
    address[] internal baseTokenWhaleAccounts = [BASE_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        CornHyperdriveInstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "CornHyperdrive",
                decimals: 8,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: new address[](0),
                baseToken: LBTC,
                vaultSharesToken: IERC20(address(0)),
                shareTolerance: 0,
                minimumShareReserves: 1e5,
                minimumTransactionAmount: 1e5,
                positionDuration: POSITION_DURATION,
                fees: IHyperdrive.Fees({
                    curve: 0.001e18,
                    flat: 0.0001e18,
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
                closeLongWithBaseTolerance: 2,
                roundTripLpInstantaneousWithBaseTolerance: 1e3,
                roundTripLpWithdrawalSharesWithBaseTolerance: 1e5,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 100,
                // NOTE: Since the curve fee isn't zero, this check is ignored.
                roundTripLongInstantaneousWithBaseTolerance: 0,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 100,
                roundTripLongMaturityWithBaseTolerance: 1e3,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 100,
                // NOTE: Since the curve fee isn't zero, this check is ignored.
                roundTripShortInstantaneousWithBaseTolerance: 0,
                roundTripShortMaturityWithBaseTolerance: 1e3,
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
            CORN_SILO
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(20_744_342) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }
}
