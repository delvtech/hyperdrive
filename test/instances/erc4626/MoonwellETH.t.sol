// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { MetaMorphoHyperdriveInstanceTest } from "./MetaMorphoHyperdriveInstanceTest.t.sol";

contract MoonwellETHHyperdriveTest is MetaMorphoHyperdriveInstanceTest {
    /// @dev The WETH contract.
    IERC20 internal constant WETH =
        IERC20(0x4200000000000000000000000000000000000006);

    /// @dev The Moonwell ETH contract.
    IERC20 internal constant MWETH =
        IERC20(0xa0E430870c4604CcfC7B38Ca7845B1FF653D0ff1);

    /// @dev Whale accounts.
    address internal WETH_TOKEN_WHALE =
        address(0x6446021F4E396dA3df4235C62537431372195D38);
    address[] internal baseTokenWhaleAccounts = [WETH_TOKEN_WHALE];
    address internal MWETH_TOKEN_WHALE =
        address(0xF63F5FCC54f5fd11f3c098053F330E032E4D9259);
    address[] internal vaultSharesTokenWhaleAccounts = [MWETH_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "ERC4626Hyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: WETH,
                vaultSharesToken: MWETH,
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
                closeLongWithBaseTolerance: 20,
                roundTripLpInstantaneousWithBaseTolerance: 1e5,
                roundTripLpWithdrawalSharesWithBaseTolerance: 1e6,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithBaseTolerance: 1e5,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithBaseTolerance: 1e5,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithBaseTolerance: 1e5,
                roundTripShortMaturityWithBaseTolerance: 1e5,
                // The share test tolerances.
                closeLongWithSharesTolerance: 20,
                closeShortWithSharesTolerance: 100,
                roundTripLpInstantaneousWithSharesTolerance: 1e7,
                roundTripLpWithdrawalSharesWithSharesTolerance: 1e7,
                roundTripLongInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithSharesTolerance: 1e5,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 1e3,
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
    function setUp() public override __base_fork(20_773_209) {
        // Invoke the Instance testing suite setup.
        super.setUp();
    }
}
