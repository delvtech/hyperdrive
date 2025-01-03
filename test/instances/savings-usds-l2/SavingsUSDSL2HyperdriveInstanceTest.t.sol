// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { SavingsUSDSL2HyperdriveCoreDeployer } from "../../../contracts/src/deployers/savings-usds-l2/SavingsUSDSL2HyperdriveCoreDeployer.sol";
import { SavingsUSDSL2HyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/savings-usds-l2/SavingsUSDSL2HyperdriveDeployerCoordinator.sol";
import { SavingsUSDSL2Target0Deployer } from "../../../contracts/src/deployers/savings-usds-l2/SavingsUSDSL2Target0Deployer.sol";
import { SavingsUSDSL2Target1Deployer } from "../../../contracts/src/deployers/savings-usds-l2/SavingsUSDSL2Target1Deployer.sol";
import { SavingsUSDSL2Target2Deployer } from "../../../contracts/src/deployers/savings-usds-l2/SavingsUSDSL2Target2Deployer.sol";
import { SavingsUSDSL2Target3Deployer } from "../../../contracts/src/deployers/savings-usds-l2/SavingsUSDSL2Target3Deployer.sol";
import { SavingsUSDSL2Target4Deployer } from "../../../contracts/src/deployers/savings-usds-l2/SavingsUSDSL2Target4Deployer.sol";
import { SavingsUSDSL2Conversions } from "../../../contracts/src/instances/savings-usds-l2/SavingsUSDSL2Conversions.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IPSM } from "../../../contracts/src/interfaces/IPSM.sol";
import { IRateProvider } from "../../../contracts/src/interfaces/IRateProvider.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract SavingsUSDSL2HyperdriveInstanceTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The RAY constant from sUSDS.
    uint256 internal constant RAY = 1e27;

    /// @dev The PSM contract.
    IPSM internal PSM;

    /// @notice Instantiates the instance testing suite with the configuration.
    /// @param _config The instance test configuration.
    constructor(
        InstanceTestConfig memory _config,
        IPSM _PSM
    ) InstanceTest(_config) {
        PSM = _PSM;
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy the Aerodrome LP instance. This
    ///      is empty.
    /// @return The empty extra data.
    function getExtraData() internal view override returns (bytes memory) {
        return abi.encode(PSM);
    }

    /// @dev Converts base amount to the equivalent about in shares.
    /// @param baseAmount The base amount.
    /// @return The converted share amount.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        return SavingsUSDSL2Conversions.convertToShares(PSM, baseAmount);
    }

    /// @dev Converts share amount to the equivalent amount in base.
    /// @param shareAmount The share amount.
    /// @return The converted base amount.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        return SavingsUSDSL2Conversions.convertToBase(PSM, shareAmount);
    }

    /// @dev Deploys the AerodromeLp Hyperdrive deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    /// @return The coordinator address.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new SavingsUSDSL2HyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new SavingsUSDSL2HyperdriveCoreDeployer()),
                    address(new SavingsUSDSL2Target0Deployer()),
                    address(new SavingsUSDSL2Target1Deployer()),
                    address(new SavingsUSDSL2Target2Deployer()),
                    address(new SavingsUSDSL2Target3Deployer()),
                    address(new SavingsUSDSL2Target4Deployer())
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply()
        internal
        view
        virtual
        override
        returns (uint256, uint256)
    {
        return (
            PSM.usds().balanceOf(address(PSM)),
            convertToShares(PSM.usds().balanceOf(address(PSM)))
        );
    }

    /// @dev Fetches the token balance information of an account.
    /// @param account The account to query.
    /// @return The balance of base.
    /// @return The balance of vault shares.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (
            config.baseToken.balanceOf(account),
            config.vaultSharesToken.balanceOf(account)
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
        IRateProvider rateProvider = IRateProvider(PSM.rateProvider());
        uint256 chi = rateProvider.getChi();
        uint256 rho = rateProvider.getRho();
        uint256 ssr = rateProvider.getSSR();
        chi = (_rpow(ssr, block.timestamp - rho) * chi) / RAY;

        // Accrue interest in the SUSDS market. This amounts to manually
        // updating the chi value, which is the exchange rate.
        (chi, ) = chi.calculateInterest(variableRate, timeDelta);

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Update the SUSDS market state.
        vm.store(
            address(rateProvider),
            bytes32(uint256(1)),
            bytes32((uint256(block.timestamp) << 216) | (chi << 96) | ssr)
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
