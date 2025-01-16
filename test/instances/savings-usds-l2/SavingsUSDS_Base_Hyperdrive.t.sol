// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IPSM } from "../../../contracts/src/interfaces/IPSM.sol";
import { SavingsUSDSL2HyperdriveInstanceTest } from "./SavingsUSDSL2HyperdriveInstanceTest.t.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract SavingsUSDS_L2_Base_Hyperdrive is SavingsUSDSL2HyperdriveInstanceTest {
    using stdStorage for StdStorage;
    using Strings for uint256;

    /// @dev The PSM contract on Base.
    IPSM internal immutable _PSM =
        IPSM(address(0x1601843c5E9bC251A3272907010AFa41Fa18347E));

    /// @dev The tokens on Base.
    IERC20 internal immutable USDS =
        IERC20(address(0x820C137fa70C8691f0e44Dc420a5e53c168921Dc));
    IERC20 internal immutable SUSDS =
        IERC20(address(0x5875eEE11Cf8398102FdAd704C9E96607675467a));

    /// @dev Whale accounts on Base.
    /// there are no whales, using the PSM module itself
    address internal USDS_TOKEN_WHALE =
        address(0x2f45724d7E384b38D5C97206e78470544304887F);
    address[] internal baseTokenWhaleAccounts = [USDS_TOKEN_WHALE];
    address internal SUSDS_TOKEN_WHALE =
        address(0xE971427F9a3C7a282D51E7FBE8A6DFfD257eBdDA);
    address[] internal vaultSharesTokenWhaleAccounts = [SUSDS_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        SavingsUSDSL2HyperdriveInstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "SavingsUSDSL2Hyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: USDS,
                vaultSharesToken: IERC20(SUSDS),
                shareTolerance: 1e3,
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
                enableBaseWithdraws: true,
                enableShareWithdraws: true,
                baseWithdrawError: new bytes(0),
                isRebasing: false,
                shouldAccrueInterest: true,
                // The base test tolerances.
                closeLongWithBaseTolerance: 1e3,
                closeShortWithBaseUpperBoundTolerance: 10,
                closeShortWithBaseTolerance: 100,
                burnWithBaseTolerance: 1e3,
                roundTripLpInstantaneousWithBaseTolerance: 1e8,
                roundTripLpWithdrawalSharesWithBaseTolerance: 1e8,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithBaseTolerance: 1e8,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithBaseTolerance: 1e5,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithBaseTolerance: 1e5,
                roundTripShortMaturityWithBaseTolerance: 1e5,
                roundTripPairInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripPairInstantaneousWithBaseTolerance: 1e5,
                roundTripPairMaturityWithBaseTolerance: 1e5,
                // The share test tolerances.
                closeLongWithSharesTolerance: 1e3,
                closeShortWithSharesTolerance: 100,
                burnWithSharesTolerance: 1e3,
                roundTripLpInstantaneousWithSharesTolerance: 1e7,
                roundTripLpWithdrawalSharesWithSharesTolerance: 1e7,
                roundTripLongInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithSharesTolerance: 1e5,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithSharesTolerance: 1e5,
                roundTripShortInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithSharesTolerance: 1e5,
                roundTripShortMaturityWithSharesTolerance: 1e5,
                roundTripPairInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripPairInstantaneousWithSharesTolerance: 1e5,
                roundTripPairMaturityWithSharesTolerance: 1e5,
                // The verification tolerances.
                verifyDepositTolerance: 5,
                verifyWithdrawalTolerance: 2
            }),
            _PSM
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __base_fork(23_839_241) {
        // Invoke the Instance testing suite setup.
        super.setUp();
    }
}
