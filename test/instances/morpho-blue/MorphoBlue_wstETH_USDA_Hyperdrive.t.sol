// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IMorphoBlueHyperdrive } from "../../../contracts/src/interfaces/IMorphoBlueHyperdrive.sol";
import { Lib } from "../../utils/Lib.sol";
import { MorphoBlueHyperdriveInstanceTest } from "./MorphoBlueHyperdriveInstanceTest.t.sol";

contract MorphoBlue_wstETH_USDA_HyperdriveTest is
    MorphoBlueHyperdriveInstanceTest
{
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The address of the loan token. This is just the USDA token.
    address internal constant LOAN_TOKEN =
        address(0x0000206329b97DB379d5E1Bf586BbDB969C63274);

    /// @dev Whale accounts.
    address internal LOAN_TOKEN_WHALE =
        address(0xEc0B13b2271E212E1a74D55D51932BD52A002961);
    address[] internal baseTokenWhaleAccounts = [LOAN_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        MorphoBlueHyperdriveInstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "MorphoBlueHyperdrive",
                decimals: 18,
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
                shareTolerance: 1e15,
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
                shouldAccrueInterest: true,
                // The base test tolerances.
                closeLongWithBaseTolerance: 2,
                roundTripLpInstantaneousWithBaseTolerance: 1e13,
                roundTripLpWithdrawalSharesWithBaseTolerance: 1e13,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithBaseTolerance: 1e9,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithBaseTolerance: 1e5,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithBaseTolerance: 1e5,
                roundTripShortMaturityWithBaseTolerance: 1e10,
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
                verifyWithdrawalTolerance: 2
            }),
            IMorphoBlueHyperdrive.MorphoBlueParams({
                // The mainnet Morpho Blue pool
                morpho: IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb),
                // The address of the collateral token. This is just the wstETH
                // token.
                collateralToken: address(
                    0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
                ),
                // The address of the oracle.
                oracle: address(0xBC693693fDBB177Ad05ff38633110016BC043AC5),
                // The address of the interest rate model.
                irm: address(0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC),
                // The liquidation loan to value ratio.
                lltv: 860000000000000000
            })
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(20_481_157) {
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
        bytes32 balanceLocation = keccak256(
            abi.encode(address(_recipient), 51)
        );
        vm.store(address(LOAN_TOKEN), balanceLocation, bytes32(_amount));
    }
}
