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

import "forge-std/console2.sol";

interface ISUSDS {
    function chi() external view returns (uint256);
    function rho() external view returns (uint256);
    function drip() external returns (uint256);
}

contract sUSDSHyperdriveTest is ERC4626HyperdriveInstanceTest {
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The USDS contract.
    IERC20 internal constant USDS =
        IERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);

    /// @dev The sUSDS contract.
    IERC4626 internal constant SUSDS =
        IERC4626(0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD);

    /// @dev Whale accounts.
    address internal USDS_TOKEN_WHALE =
        address(0x0650CAF159C5A49f711e8169D4336ECB9b950275);
    address[] internal baseTokenWhaleAccounts = [USDS_TOKEN_WHALE];
    address internal SUSDS_TOKEN_WHALE =
        address(0x2674341D40b445c21287b81c4Bc95EC8E358f7E8);
    address[] internal vaultSharesTokenWhaleAccounts = [SUSDS_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "ERC4626Hyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: USDS,
                vaultSharesToken: SUSDS,
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
                roundTripLpInstantaneousWithBaseTolerance: 1e8,
                roundTripLpWithdrawalSharesWithBaseTolerance: 1e8,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithBaseTolerance: 1e8,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithBaseTolerance: 1e5,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithBaseTolerance: 1e5,
                roundTripShortMaturityWithBaseTolerance: 1e5,
                // The share test tolerances.
                closeLongWithSharesTolerance: 1e3,
                closeLongWithBaseTolerance: 1e3,
                closeShortWithSharesTolerance: 100,
                roundTripLpInstantaneousWithSharesTolerance: 1e7,
                roundTripLpWithdrawalSharesWithSharesTolerance: 1e7,
                roundTripLongInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithSharesTolerance: 1e5,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithSharesTolerance: 1e17,
                roundTripShortInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithSharesTolerance: 1e5,
                roundTripShortMaturityWithSharesTolerance: 1e17,
                // The verification tolerances.
                verifyDepositTolerance: 5,
                verifyWithdrawalTolerance: 2
            })
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(20_836_852) {
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
        uint256 chi = ISUSDS(address(SUSDS)).chi();
        // Accrue interest in the sUSDS market. This amounts to manually
        // updating the total supply assets.
        (chi, ) = chi.calculateInterest(
            variableRate,
            timeDelta
        );
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);
        console2.log("rho", ISUSDS(address(SUSDS)).rho().toString(18));
        console2.log("chi", ISUSDS(address(SUSDS)).chi().toString(18));
        vm.store(address(SUSDS), bytes32(uint256(5)), bytes32((uint256(block.timestamp)<<192)|chi));
        console2.log("rho", ISUSDS(address(SUSDS)).rho().toString(18));
        console2.log("chi", ISUSDS(address(SUSDS)).chi().toString(18));

        console2.log("rho", ISUSDS(address(SUSDS)).rho().toString(18));
        console2.log("chi", ISUSDS(address(SUSDS)).chi().toString(18));

        // vm.warp(block.timestamp + timeDelta);

        // Interest accumulates in the dsr based on time passed.
        // This may caused insolvency if too much interest accrues as no real dai is being
        // accrued.
        // console2.log("rho", ISUSDS(address(SUSDS)).rho().toString(18));
        // console2.log("chi", ISUSDS(address(SUSDS)).chi().toString(18));
        // ISUSDS(address(SUSDS)).drip();
        // console2.log("rho", ISUSDS(address(SUSDS)).rho().toString(18));
        // console2.log("chi", ISUSDS(address(SUSDS)).chi().toString(18));
    }
}