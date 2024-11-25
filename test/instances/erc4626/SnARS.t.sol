// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../../contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { Lib } from "../../utils/Lib.sol";
import { ERC4626HyperdriveInstanceTest } from "./ERC4626HyperdriveInstanceTest.t.sol";

interface ISnARS is IERC20 {
    function numStakingContract() external view returns (IStaking);
}

interface IStaking {
    function setApy(uint256) external;
}

contract SnARSHyperdriveTest is ERC4626HyperdriveInstanceTest {
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The admin that can update the snARS APY.
    address internal constant SNARS_ADMIN =
        0x062F9f2e46cDEF536D0E10c6cb31f951921c4A68;

    /// @dev The nARS contract.
    IERC20 internal constant NARS =
        IERC20(0x5e40f26E89213660514c51Fb61b2d357DBf63C85);

    /// @dev The snARS contract.
    ISnARS internal constant SNARS =
        ISnARS(0xC1F4C75e8925A67BE4F35D6b1c044B5ea8849a58);

    /// @dev Whale accounts.
    address internal NARS_TOKEN_WHALE =
        address(0x1ebc5e10D58e1d78A28971B5776Ea6A64CB88329);
    address[] internal baseTokenWhaleAccounts = [NARS_TOKEN_WHALE];
    address internal SNARS_TOKEN_WHALE =
        address(0x54423d0A5c4e3a6Eb8Bd12FDD54c1e6b42D52Ebe);
    address[] internal vaultSharesTokenWhaleAccounts = [SNARS_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "ERC4626Hyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: NARS,
                vaultSharesToken: SNARS,
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
                enableBaseWithdraws: false,
                enableShareWithdraws: true,
                baseWithdrawError: abi.encodeWithSelector(
                    IHyperdrive.UnsupportedToken.selector
                ),
                isRebasing: false,
                shouldAccrueInterest: true,
                // NOTE: Base  withdrawals are disabled, so the tolerances are zero.
                //
                // The base test tolerances.
                closeLongWithBaseTolerance: 0,
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
                roundTripLpInstantaneousWithSharesTolerance: 1e7,
                roundTripLpWithdrawalSharesWithSharesTolerance: 1e8,
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
    function setUp() public override __base_fork(21_071_334) {
        // Invoke the Instance testing suite setup.
        super.setUp();
    }

    /// @dev HACK: The snARS vault returns a total assets of 0, so we have to
    ///      override this.
    /// @dev Fetches the total supply of the base and share tokens.
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply() internal view override returns (uint256, uint256) {
        uint256 totalShares = IERC4626(address(config.vaultSharesToken))
            .totalSupply();
        return (
            IERC4626(address(config.vaultSharesToken)).convertToAssets(
                totalShares
            ),
            totalShares
        );
    }

    /// Helpers ///

    /// @dev Advance time and accrue interest.
    /// @param timeDelta The time to advance.
    /// @param variableRate The variable rate.
    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Ensure the variable rate isn't negative.
        require(variableRate >= 0, "SnARSHyperdriveTest: negative rate");

        // Update the APY of the staking contract.
        vm.stopPrank();
        vm.startPrank(SNARS_ADMIN);
        IStaking staking = SNARS.numStakingContract();
        // NOTE: Since we aren't calling this contract repeatedly, this
        // functions as an APR.
        staking.setApy(uint256(variableRate));

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);
    }
}
