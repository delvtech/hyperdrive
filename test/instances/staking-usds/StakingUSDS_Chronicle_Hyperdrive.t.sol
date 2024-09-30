// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IStakingUSDS } from "../../../contracts/src/interfaces/IStakingUSDS.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { StakingUSDSHyperdriveInstanceTest } from "./StakingUSDSHyperdriveInstanceTest.t.sol";

contract StakingUSDS_Chronicle_Hyperdrive is StakingUSDSHyperdriveInstanceTest {
    using stdStorage for StdStorage;

    /// @dev The mainnet StakingRewards vault for Chronicle rewards.
    IStakingUSDS internal constant STAKING_USDS =
        IStakingUSDS(0x10ab606B067C9C461d8893c47C7512472E19e2Ce);

    /// @dev The mainnet USDS token.
    IERC20 internal constant USDS =
        IERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);

    /// @dev Whale accounts.
    address internal BASE_TOKEN_WHALE =
        0x2621CC0B3F3c079c1Db0E80794AA24976F0b9e3c;
    address[] internal baseTokenWhaleAccounts = [BASE_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        StakingUSDSHyperdriveInstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "StakingUSDSHyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: new address[](0),
                baseToken: USDS,
                vaultSharesToken: IERC20(address(0)),
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
                roundTripLpWithdrawalSharesWithBaseTolerance: 1e7,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 1e3,
                // NOTE: Since the curve fee isn't zero, this check is ignored.
                roundTripLongInstantaneousWithBaseTolerance: 1e4,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 100,
                roundTripLongMaturityWithBaseTolerance: 1e3,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 1e3,
                // NOTE: Since the curve fee isn't zero, this check is ignored.
                roundTripShortInstantaneousWithBaseTolerance: 1e3,
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
            STAKING_USDS
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(20_865_206) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }
}
