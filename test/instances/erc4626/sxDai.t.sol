// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { ERC4626HyperdriveCoreDeployer } from "../../../contracts/src/deployers/erc4626/ERC4626HyperdriveCoreDeployer.sol";
import { ERC4626HyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/erc4626/ERC4626HyperdriveDeployerCoordinator.sol";
import { ERC4626Target0Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target0Deployer.sol";
import { ERC4626Target1Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target1Deployer.sol";
import { ERC4626Target2Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target2Deployer.sol";
import { ERC4626Target3Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target3Deployer.sol";
import { ERC4626Target4Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target4Deployer.sol";
import { ERC4626Conversions } from "../../../contracts/src/instances/erc4626/ERC4626Conversions.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../../contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { Lib } from "../../utils/Lib.sol";
import { ERC4626HyperdriveInstanceTest } from "./ERC4626HyperdriveInstanceTest.t.sol";

contract sxDaiHyperdriveTest is ERC4626HyperdriveInstanceTest {
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The wxDai contract.
    IERC20 internal constant WXDAI =
        IERC20(0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d);

    /// @dev The sxDai contract.
    IERC4626 internal constant SXDAI =
        IERC4626(0xaf204776c7245bF4147c2612BF6e5972Ee483701);

    /// @dev Whale accounts.
    address internal WXDAI_TOKEN_WHALE =
        address(0xd0Dd6cEF72143E22cCED4867eb0d5F2328715533);
    address[] internal baseTokenWhaleAccounts = [WXDAI_TOKEN_WHALE];
    address internal SXDAI_TOKEN_WHALE =
        address(0x7a5c3860a77a8DC1b225BD46d0fb2ac1C6D191BC);
    address[] internal vaultSharesTokenWhaleAccounts = [SXDAI_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "ERC4626Hyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: WXDAI,
                vaultSharesToken: SXDAI,
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
                roundTripLpWithdrawalSharesWithBaseTolerance: 1e5,
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
    function setUp() public override __gnosis_chain_fork(35_681_086) {
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
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in the sxDAI market. This amounts to manually
        // updating the total supply assets.
        uint256 totalAssets = SXDAI.totalAssets();
        (totalAssets, ) = totalAssets.calculateInterest(
            variableRate,
            timeDelta
        );
        bytes32 balanceLocation = keccak256(abi.encode(address(SXDAI), 3));
        vm.store(address(WXDAI), balanceLocation, bytes32(totalAssets));
    }
}
