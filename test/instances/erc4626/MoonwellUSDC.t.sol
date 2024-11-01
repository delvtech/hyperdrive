// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";
import { MetaMorphoHyperdriveInstanceTest } from "./MetaMorphoHyperdriveInstanceTest.t.sol";

contract MoonwellUSDCHyperdriveTest is MetaMorphoHyperdriveInstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    /// @dev The USDC contract.
    IERC20 internal constant USDC =
        IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    /// @dev The Moonwell USDC contract.
    IERC20 internal constant MWUSDC =
        IERC20(0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca);

    /// @dev Whale accounts.
    address internal USDC_TOKEN_WHALE =
        address(0x711799fcb318010c3eBebD094B3eefB7d1e2Cf08);
    address[] internal baseTokenWhaleAccounts = [USDC_TOKEN_WHALE];
    address internal MWUSDC_TOKEN_WHALE =
        address(0x49E96E255bA418d08E66c35b588E2f2F3766E1d0);
    address[] internal vaultSharesTokenWhaleAccounts = [MWUSDC_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "ERC4626Hyperdrive",
                decimals: 6,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: USDC,
                vaultSharesToken: MWUSDC,
                shareTolerance: 1e3,
                minimumShareReserves: 1e3,
                minimumTransactionAmount: 1e3,
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
                baseWithdrawError: new bytes(0),
                isRebasing: false,
                shouldAccrueInterest: true,
                // The base test tolerances.
                closeLongWithBaseTolerance: 20,
                closeShortWithBaseUpperBoundTolerance: 10,
                closeShortWithBaseTolerance: 100,
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
                // NOTE: This is high, but the vault share proceeds are always
                // less than the expected amount. This seems to be caused by the
                // lack of precision of our vault share price. For reasonable
                // numbers (above 1e18), the result is consistently within 6
                // decimals of precision.
                roundTripLpInstantaneousWithSharesTolerance: 1e18,
                roundTripLpWithdrawalSharesWithSharesTolerance: 1e7,
                roundTripLongInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithSharesTolerance: 1e5,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithSharesTolerance: 1e5,
                roundTripShortInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithSharesTolerance: 1e5,
                roundTripShortMaturityWithSharesTolerance: 1e5,
                // The verification tolerances.
                verifyDepositTolerance: 1e12,
                verifyWithdrawalTolerance: 1e13
            })
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __base_fork(21_117_198) {
        // Invoke the Instance testing suite setup.
        super.setUp();
    }

    /// Price Per Share ///

    /// @dev Fuzz test that verifies that the vault share price is the price
    ///      that dictates the conversion between base and shares.
    ///
    ///      NOTE: We use a custom tolerance for this test to avoid reducing the
    ///      utility of `shareTolerance`.
    /// @param basePaid the fuzz parameter for the base paid.
    function test__pricePerVaultShare(uint256 basePaid) external override {
        // Ensure that the share price is the expected value.
        (uint256 totalBase, uint256 totalSupply) = getSupply();
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, totalBase.divDown(totalSupply));

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of shares. This will
        // be an approximation.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxLong()
        );
        (, uint256 hyperdriveSharesBefore) = getTokenBalances(
            address(hyperdrive)
        );
        openLong(bob, basePaid);
        (, uint256 hyperdriveSharesAfter) = getTokenBalances(
            address(hyperdrive)
        );
        assertApproxEqAbs(
            hyperdriveSharesAfter,
            hyperdriveSharesBefore + basePaid.divDown(vaultSharePrice),
            1e15
        );
    }
}
