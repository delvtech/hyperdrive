// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../../contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { Lib } from "../../utils/Lib.sol";
import { ERC4626HyperdriveInstanceTest } from "./ERC4626HyperdriveInstanceTest.t.sol";

contract sGYD_gnosis_HyperdriveTest is ERC4626HyperdriveInstanceTest {
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The storage location of ERC20 data in L2 GYD and sGYD.
    bytes32 ERC20_STORAGE_LOCATION =
        0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;

    /// @dev The GYD contract.
    IERC20 internal constant GYD =
        IERC20(0xCA5d8F8a8d49439357d3CF46Ca2e720702F132b8);

    /// @dev The sGYD contract.
    IERC4626 internal constant SGYD =
        IERC4626(0xeA50f402653c41cAdbaFD1f788341dB7B7F37816);

    /// @dev Whale accounts.
    address internal GYD_TOKEN_WHALE =
        address(0xa1886c8d748DeB3774225593a70c79454B1DA8a6);
    address[] internal baseTokenWhaleAccounts = [GYD_TOKEN_WHALE];
    address internal SGYD_TOKEN_WHALE =
        address(0x7a12F90D69E3D779049632634ADE17ad082447e5);
    address[] internal vaultSharesTokenWhaleAccounts = [SGYD_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "ERC4626Hyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: GYD,
                vaultSharesToken: IERC20(SGYD),
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
                closeShortWithBaseUpperBoundTolerance: 1e4,
                closeShortWithBaseTolerance: 1e4,
                burnWithBaseTolerance: 20,
                roundTripLpInstantaneousWithBaseTolerance: 1e5,
                roundTripLpWithdrawalSharesWithBaseTolerance: 1e5,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithBaseTolerance: 1e5,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithBaseTolerance: 1e5,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithBaseTolerance: 1e5,
                roundTripShortMaturityWithBaseTolerance: 1e5,
                roundTripPairInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripPairInstantaneousWithBaseTolerance: 1e5,
                roundTripPairMaturityWithBaseTolerance: 1e5,
                // The share test tolerances.
                closeLongWithSharesTolerance: 20,
                closeShortWithSharesTolerance: 100,
                burnWithSharesTolerance: 20,
                roundTripLpInstantaneousWithSharesTolerance: 1e7,
                roundTripLpWithdrawalSharesWithSharesTolerance: 1e7,
                roundTripLongInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithSharesTolerance: 1e5,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithSharesTolerance: 1e5,
                roundTripShortInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithSharesTolerance: 1e5,
                roundTripShortMaturityWithSharesTolerance: 1e5,
                roundTripPairInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripPairInstantaneousWithSharesTolerance: 1e5,
                roundTripPairMaturityWithSharesTolerance: 1e5,
                // The verification tolerances.
                verifyDepositTolerance: 2,
                verifyWithdrawalTolerance: 2
            })
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __gnosis_chain_fork(36_808_076) {
        // NOTE: We need to mint GYD since the current supply is very low.
        //
        // Mint GYD to the GYD whale.
        setBalanceGYD(GYD_TOKEN_WHALE, 1_000_000e18);

        // NOTE: We need to mint sGYD since the current supply is zero.
        //
        // Mint GYD to the sGYD whale and mint sGYD.
        setBalanceGYD(SGYD_TOKEN_WHALE, 1_000_000e18);
        vm.stopPrank();
        vm.startPrank(SGYD_TOKEN_WHALE);
        GYD.approve(address(SGYD), 1_000_000e18);
        SGYD.deposit(1_000_000e18, SGYD_TOKEN_WHALE);

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

        // Accrue interest in the sGYD market. This amounts to manually
        // updating the total supply assets by minting more GYD to the contract.
        uint256 totalAssets = SGYD.totalAssets();
        (totalAssets, ) = totalAssets.calculateInterest(
            variableRate,
            timeDelta
        );
        setBalanceGYD(address(SGYD), totalAssets);
    }

    /// @dev Sets the GYD balance of an account.
    /// @param _account The account to be updated.
    /// @param _amount The amount of tokens to set.
    function setBalanceGYD(address _account, uint256 _amount) internal {
        bytes32 balanceLocation = keccak256(
            abi.encode(address(_account), ERC20_STORAGE_LOCATION)
        );
        vm.store(address(GYD), balanceLocation, bytes32(_amount));
    }

    /// @dev Sets the sGYD balance of an account.
    /// @param _account The account to be updated.
    /// @param _amount The amount of tokens to set.
    function setBalanceSGYD(address _account, uint256 _amount) internal {
        bytes32 balanceLocation = keccak256(
            abi.encode(address(_account), ERC20_STORAGE_LOCATION)
        );
        vm.store(address(SGYD), balanceLocation, bytes32(_amount));
    }
}
