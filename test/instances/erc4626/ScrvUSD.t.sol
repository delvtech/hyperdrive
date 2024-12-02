// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../../contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { Lib } from "../../utils/Lib.sol";
import { ERC4626HyperdriveInstanceTest } from "./ERC4626HyperdriveInstanceTest.t.sol";

interface ISCRVUSD {
    function lastProfitUpdate() external view returns (uint256);
    function fullProfitUnlockDate() external view returns (uint256);
}

contract scrvUSDHyperdriveTest is ERC4626HyperdriveInstanceTest {
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The crvUSD contract.
    IERC20 internal constant CRVUSD =
        IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);

    /// @dev The scrvUSD contract.
    IERC4626 internal constant SCRVUSD =
        IERC4626(0x0655977FEb2f289A4aB78af67BAB0d17aAb84367);

    /// @dev Whale accounts.
    address internal CRVUSD_TOKEN_WHALE =
        address(0x0a7b9483030994016567b3B1B4bbB865578901Cb);
    address[] internal baseTokenWhaleAccounts = [CRVUSD_TOKEN_WHALE];
    address internal SCRVUSD_TOKEN_WHALE =
        address(0x3Da232a0c0A5C59918D7B5fF77bf1c8Fc93aeE1B);
    address[] internal vaultSharesTokenWhaleAccounts = [SCRVUSD_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "ERC4626Hyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: CRVUSD,
                vaultSharesToken: SCRVUSD,
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
    function setUp() public override __mainnet_fork(21_188_049) {
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
        uint256 totalAssets = SCRVUSD.totalAssets();

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in the scrvUSD market. This amounts to manually
        // updating the total supply assets by updating the crvUSD balance of
        // scrvUSD.
        (totalAssets, ) = totalAssets.calculateInterest(
            variableRate,
            timeDelta
        );

        // scrvUSD profits can be unlocked over a period of time, which affects
        // the totalSupply and pricePerShare according to the unlocking rate.
        // We exclude this factor by updating the unlock date and lastProfitUpdate
        // according to the timeDelta.

        uint256 fullProfitUnlockDate = ISCRVUSD(address(SCRVUSD))
            .fullProfitUnlockDate();
        uint256 lastProfitUpdate = ISCRVUSD(address(SCRVUSD))
            .lastProfitUpdate();

        bytes32 fullProfitLocation = bytes32(uint256(38));
        bytes32 lastProfitLocation = bytes32(uint256(40));

        vm.store(
            address(SCRVUSD),
            fullProfitLocation,
            bytes32(fullProfitUnlockDate + timeDelta)
        );
        vm.store(
            address(SCRVUSD),
            lastProfitLocation,
            bytes32(lastProfitUpdate + timeDelta)
        );

        bytes32 idleLocation = bytes32(uint256(22));
        vm.store(address(SCRVUSD), idleLocation, bytes32(totalAssets));
    }
}
