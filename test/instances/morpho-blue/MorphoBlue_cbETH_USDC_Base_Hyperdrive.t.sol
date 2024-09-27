// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IFiatTokenProxy } from "../../../contracts/src/interfaces/IFiatTokenProxy.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IMorphoBlueHyperdrive } from "../../../contracts/src/interfaces/IMorphoBlueHyperdrive.sol";
import { Lib } from "../../utils/Lib.sol";
import { MorphoBlueHyperdriveInstanceTest } from "./MorphoBlueHyperdriveInstanceTest.t.sol";

contract MorphoBlue_cbETH_USDC_Base_HyperdriveTest is
    MorphoBlueHyperdriveInstanceTest
{
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The address of the loan token. This is just the USDC token.
    address internal constant LOAN_TOKEN =
        address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    /// @dev Whale accounts.
    address internal LOAN_TOKEN_WHALE =
        address(0x3304E22DDaa22bCdC5fCa2269b418046aE7b566A);
    address[] internal baseTokenWhaleAccounts = [LOAN_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        MorphoBlueHyperdriveInstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "MorphoBlueHyperdrive",
                decimals: 6,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: new address[](0),
                baseToken: IERC20(LOAN_TOKEN),
                vaultSharesToken: IERC20(address(0)),
                // NOTE: The share tolerance is quite high for this integration
                // because the vault share price is ~1e12, which means that just
                // multiplying or dividing by the vault is an imprecise way of
                // converting between base and vault shares. We included more
                // assertions than normal to the round trip tests to verify that
                // the calculations satisfy our expectations of accuracy.
                shareTolerance: 1e3,
                minimumShareReserves: 1e6,
                minimumTransactionAmount: 1e6,
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
            }),
            IMorphoBlueHyperdrive.MorphoBlueParams({
                // The mainnet Morpho Blue pool
                morpho: IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb),
                // The address of the collateral token. This is just the wstETH
                // token.
                collateralToken: address(
                    0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22
                ),
                // The address of the oracle.
                oracle: address(0xb40d93F44411D8C09aD17d7F88195eF9b05cCD96),
                // The address of the interest rate model.
                irm: address(0x46415998764C29aB2a25CbeA6254146D50D22687),
                // The liquidation loan to value ratio.
                lltv: 860000000000000000
            })
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __base_fork(19_604_571) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }

    /// Helpers ///

    /// @dev Mints base tokens to a specified account.
    /// @param _recipient The recipient of the minted tokens.
    /// @param _amount The amount of tokens to mint.
    function mintBaseTokens(
        address _recipient,
        uint256 _amount
    ) internal override {
        bytes32 balanceLocation = keccak256(abi.encode(address(_recipient), 9));
        vm.store(
            IFiatTokenProxy(LOAN_TOKEN).implementation(),
            balanceLocation,
            bytes32(_amount)
        );
    }
}
