// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IMToken, IMoonwellComptroller } from "../../../contracts/src/interfaces/IMoonwell.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { MoonwellHyperdriveInstanceTest } from "./MoonwellHyperdriveInstanceTest.t.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";

contract Moonwell_AERO_Hyperdrive is MoonwellHyperdriveInstanceTest {
    using stdStorage for StdStorage;

    /// @dev The Base Moonwell Comptroller.
    IMoonwellComptroller COMPTROLLER =
        IMoonwellComptroller(0xfBb21d0380beE3312B33c4353c8936a0F13EF26C);

    /// @dev The Base Moonwell AERO token (vaultSharesToken).
    IMToken internal constant MAERO =
        IMToken(0x73902f619CEB9B31FD8EFecf435CbDf89E369Ba6);

    /// @dev The Base AERO token (baseToken).
    address internal constant AERO =
        address(0x940181a94A35A4569E4529A3CDfB74e38FD98631);

    /// @dev Whale accounts.
    address internal AERO_TOKEN_WHALE =
        address(0x807877258B55BfEfaBDD469dA1C72731C5070839);
    address[] internal baseTokenWhaleAccounts = [AERO_TOKEN_WHALE];
    address internal MAERO_TOKEN_WHALE =
        address(0x3B11267dfC4B9EBe8427E8F557056b4B6cE98112);
    address[] internal vaultSharesTokenWhaleAccounts = [MAERO_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        MoonwellHyperdriveInstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "MoonwellHyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: IERC20(AERO),
                vaultSharesToken: IERC20(MAERO),
                shareTolerance: 0,
                minimumShareReserves: 1e5,
                minimumTransactionAmount: 1e15,
                positionDuration: POSITION_DURATION,
                fees: IHyperdrive.Fees({
                    curve: 0.001e18,
                    flat: 0.0001e18,
                    governanceLP: 0,
                    governanceZombie: 0
                }),
                enableBaseDeposits: true,
                enableShareDeposits: true,
                enableBaseWithdraws: true,
                enableShareWithdraws: true,
                baseWithdrawError: abi.encodeWithSelector(
                    IHyperdrive.UnsupportedToken.selector
                ),
                isRebasing: false,
                shouldAccrueInterest: true,
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
            })
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __base_fork(21712351) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }

    /// @dev Sets the base balance of an account.
    /// @param _owner The owner of the tokens.
    /// @param _balance The balance to set.
    function setBaseBalance(
        address _owner,
        uint256 _balance
    ) internal override {
        bytes32 balanceLocation = keccak256(abi.encode(_owner, 0));
        vm.store(address(config.baseToken), balanceLocation, bytes32(_balance));
    }
}
