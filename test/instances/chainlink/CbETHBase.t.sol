// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/src/interfaces/IChainlinkAggregatorV3.sol";
import { ChainlinkHyperdriveInstanceTest } from "./ChainlinkHyperdriveInstanceTest.t.sol";

contract CbETHBaseTest is ChainlinkHyperdriveInstanceTest {
    /// @dev Chainlink's aggregator for the cbETH-ETH reference rate on Base.
    IChainlinkAggregatorV3 internal constant CHAINLINK_AGGREGATOR =
        IChainlinkAggregatorV3(0x868a501e68F3D1E89CfC0D22F6b22E8dabce5F04);

    /// @dev The address of the cbETH token on Base.
    IERC20 internal constant CBETH =
        IERC20(0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22);

    /// @dev The cbETH Whale accounts.
    address internal constant CBETH_WHALE =
        address(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    address[] internal vaultSharesTokenWhaleAccounts = [CBETH_WHALE];

    /// @notice Instantiates the ChainlinkHyperdriveInstance testing suite with
    ///         the configuration.
    constructor()
        ChainlinkHyperdriveInstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "ChainlinkHyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: new address[](0),
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: IERC20(address(0)),
                vaultSharesToken: CBETH,
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
                // NOTE: Base deposits and withdrawals are disabled, so the
                // tolerances are zero.
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
                roundTripLpInstantaneousWithSharesTolerance: 1e3,
                roundTripLpWithdrawalSharesWithSharesTolerance: 1e3,
                roundTripLongInstantaneousWithSharesUpperBoundTolerance: 1e4,
                roundTripLongInstantaneousWithSharesTolerance: 1e3,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithSharesTolerance: 1e4,
                roundTripShortInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithSharesTolerance: 1e3,
                roundTripShortMaturityWithSharesTolerance: 1e3,
                // The verification tolerances.
                verifyDepositTolerance: 2,
                verifyWithdrawalTolerance: 2
            }),
            CHAINLINK_AGGREGATOR
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __base_fork(19_600_508) {
        // Invoke the Instance testing suite setup.
        super.setUp();
    }
}
