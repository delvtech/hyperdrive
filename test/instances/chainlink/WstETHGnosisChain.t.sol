// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/src/interfaces/IChainlinkAggregatorV3.sol";
import { ChainlinkHyperdriveInstanceTest } from "./ChainlinkHyperdriveInstanceTest.t.sol";

contract WstETHGnosisChainTest is ChainlinkHyperdriveInstanceTest {
    /// @dev Chainlink's aggregator for the wstETH-ETH reference rate on Gnosis
    ///      Chain.
    IChainlinkAggregatorV3 internal constant CHAINLINK_AGGREGATOR =
        IChainlinkAggregatorV3(0x0064AC007fF665CF8D0D3Af5E0AD1c26a3f853eA);

    /// @dev The address of the wstETH token on Gnosis Chain.
    IERC20 internal constant WSTETH =
        IERC20(0x6C76971f98945AE98dD7d4DFcA8711ebea946eA6);

    /// @dev The wstETH Whale accounts.
    address internal constant WSTETH_WHALE =
        address(0x458cD345B4C05e8DF39d0A07220feb4Ec19F5e6f);
    address[] internal vaultSharesTokenWhaleAccounts = [WSTETH_WHALE];

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
                vaultSharesToken: WSTETH,
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
                closeLongWithBaseTolerance: 0,
                closeShortWithBaseUpperBoundTolerance: 0,
                closeShortWithBaseTolerance: 0,
                burnWithBaseTolerance: 0,
                roundTripLpInstantaneousWithBaseTolerance: 0,
                roundTripLpWithdrawalSharesWithBaseTolerance: 0,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 0,
                roundTripLongInstantaneousWithBaseTolerance: 0,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 0,
                roundTripLongMaturityWithBaseTolerance: 0,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 0,
                roundTripShortInstantaneousWithBaseTolerance: 0,
                roundTripShortMaturityWithBaseTolerance: 0,
                roundTripPairInstantaneousWithBaseUpperBoundTolerance: 0,
                roundTripPairInstantaneousWithBaseTolerance: 0,
                roundTripPairMaturityWithBaseUpperBoundTolerance: 0,
                roundTripPairMaturityWithBaseTolerance: 0,
                // The share test tolerances.
                closeLongWithSharesTolerance: 20,
                closeShortWithSharesTolerance: 100,
                burnWithSharesTolerance: 20,
                roundTripLpInstantaneousWithSharesTolerance: 1e3,
                roundTripLpWithdrawalSharesWithSharesTolerance: 1e3,
                roundTripLongInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithSharesTolerance: 1e4,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithSharesTolerance: 1e4,
                roundTripShortInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithSharesTolerance: 1e3,
                roundTripShortMaturityWithSharesTolerance: 1e3,
                roundTripPairInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripPairInstantaneousWithSharesTolerance: 1e3,
                roundTripPairMaturityWithSharesUpperBoundTolerance: 1e3,
                roundTripPairMaturityWithSharesTolerance: 1e3,
                // The verification tolerances.
                verifyDepositTolerance: 2,
                verifyWithdrawalTolerance: 2
            }),
            CHAINLINK_AGGREGATOR
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __gnosis_chain_fork(35_336_446) {
        // Invoke the Instance testing suite setup.
        super.setUp();
    }
}
