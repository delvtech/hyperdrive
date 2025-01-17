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

interface ISUSDS {
    function chi() external view returns (uint256);

    function rho() external view returns (uint256);

    function ssr() external view returns (uint256);

    function drip() external returns (uint256);
}

contract sUSDSHyperdriveTest is ERC4626HyperdriveInstanceTest {
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The RAY constant from sUSDS.
    uint256 internal constant RAY = 1e27;

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
                closeLongWithBaseTolerance: 1e3,
                closeShortWithBaseUpperBoundTolerance: 10,
                closeShortWithBaseTolerance: 100,
                burnWithBaseTolerance: 1e3,
                roundTripLpInstantaneousWithBaseTolerance: 1e8,
                roundTripLpWithdrawalSharesWithBaseTolerance: 1e8,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithBaseTolerance: 1e8,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithBaseTolerance: 1e5,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithBaseTolerance: 1e5,
                roundTripShortMaturityWithBaseTolerance: 1e5,
                roundTripPairInstantaneousWithBaseUpperBoundTolerance: 1e3,
                // FIXME: Why is this higher than the other tolerances?
                roundTripPairInstantaneousWithBaseTolerance: 1e8,
                roundTripPairMaturityWithBaseUpperBoundTolerance: 1e3,
                roundTripPairMaturityWithBaseTolerance: 1e5,
                // The share test tolerances.
                closeLongWithSharesTolerance: 1e3,
                closeShortWithSharesTolerance: 100,
                burnWithSharesTolerance: 1e3,
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
                // FIXME: Why is this higher than the other tolerances?
                roundTripPairInstantaneousWithSharesTolerance: 1e6,
                roundTripPairMaturityWithSharesUpperBoundTolerance: 1e3,
                roundTripPairMaturityWithSharesTolerance: 1e5,
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
        uint256 baseBalance = USDS.balanceOf(address(SUSDS));
        uint256 chi = ISUSDS(address(SUSDS)).chi();
        uint256 rho = ISUSDS(address(SUSDS)).rho();
        uint256 ssr = ISUSDS(address(SUSDS)).ssr();
        chi = (_rpow(ssr, block.timestamp - rho) * chi) / RAY;

        // Accrue interest in the sUSDS market. This amounts to manually
        // updating the total supply assets and increasing the contract's
        // USDS balance.
        (chi, ) = chi.calculateInterest(variableRate, timeDelta);
        (baseBalance, ) = baseBalance.calculateInterest(
            variableRate,
            timeDelta
        );

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Update the sUSDS market state.
        bytes32 balanceLocation = keccak256(abi.encode(address(SUSDS), 2));
        vm.store(address(USDS), balanceLocation, bytes32(baseBalance));

        // Update the sUSDS contract's base balance.
        vm.store(
            address(SUSDS),
            bytes32(uint256(5)),
            bytes32((uint256(block.timestamp) << 192) | chi)
        );
    }

    /// @dev The ray pow method from sUSDS.
    /// @param x The base of the exponentiation.
    /// @param n The exponent of the exponentiation.
    /// @param z The result of the exponentiation.
    function _rpow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        assembly {
            switch x
            case 0 {
                switch n
                case 0 {
                    z := RAY
                }
                default {
                    z := 0
                }
            }
            default {
                switch mod(n, 2)
                case 0 {
                    z := RAY
                }
                default {
                    z := x
                }
                let half := div(RAY, 2) // for rounding.
                for {
                    n := div(n, 2)
                } n {
                    n := div(n, 2)
                } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) {
                        revert(0, 0)
                    }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) {
                        revert(0, 0)
                    }
                    x := div(xxRound, RAY)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) {
                            revert(0, 0)
                        }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) {
                            revert(0, 0)
                        }
                        z := div(zxRound, RAY)
                    }
                }
            }
        }
    }
}
