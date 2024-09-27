// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../../contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { Lib } from "../../utils/Lib.sol";
import { ERC4626HyperdriveInstanceTest } from "./ERC4626HyperdriveInstanceTest.t.sol";

// NOTE: This is an abstract contract rather than an interface since IERC4626 is
//       an abstract contract.
abstract contract ISTUSD is IERC4626 {
    function lastUpdate() external view virtual returns (uint40);

    function rate() external view virtual returns (uint208);
}

contract stUSDHyperdriveTest is ERC4626HyperdriveInstanceTest {
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The USDA contract.
    IERC20 internal constant USDA =
        IERC20(0x0000206329b97DB379d5E1Bf586BbDB969C63274);

    /// @dev The stUSD contract.
    ISTUSD internal constant STUSD =
        ISTUSD(0x0022228a2cc5E7eF0274A7Baa600d44da5aB5776);

    /// @dev Whale accounts.
    address internal USDA_TOKEN_WHALE =
        address(0xEc0B13b2271E212E1a74D55D51932BD52A002961);
    address[] internal baseTokenWhaleAccounts = [USDA_TOKEN_WHALE];
    address internal STUSD_TOKEN_WHALE =
        address(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    address[] internal vaultSharesTokenWhaleAccounts = [STUSD_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "ERC4626Hyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: USDA,
                vaultSharesToken: STUSD,
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
    function setUp() public override __mainnet_fork(20_643_578) {
        // Invoke the Instance testing suite setup.
        super.setUp();
    }

    /// Helpers ///

    /// @dev Advance time and accrue interest.
    /// @param timeDelta The time to advance.
    /// @param variableRate The variable rate.
    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Get the total assets before advancing time.
        uint256 totalAssets = STUSD.totalAssets();

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in the stUSD market. This amounts to manually
        // updating the total supply assets by updating the USDA balance of
        // stUSD. Since stUSD's `totalAssets` function computes unaccrued
        // interest, we also overwrite stUSD's `lastUpdate` value to the current
        // block time.
        bytes32 lastUpdateLocation = bytes32(uint256(201));
        vm.store(
            address(STUSD),
            lastUpdateLocation,
            bytes32((block.timestamp << 208) | uint256(STUSD.rate()))
        );
        (totalAssets, ) = totalAssets.calculateInterest(
            variableRate,
            timeDelta
        );
        bytes32 balanceLocation = keccak256(abi.encode(address(STUSD), 51));
        vm.store(address(USDA), balanceLocation, bytes32(totalAssets));
    }
}
