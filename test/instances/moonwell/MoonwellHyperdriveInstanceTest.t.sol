// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

// FIXME
import { console2 as console } from "forge-std/console2.sol";

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { MoonwellHyperdriveCoreDeployer } from "../../../contracts/src/deployers/moonwell/MoonwellHyperdriveCoreDeployer.sol";
import { MoonwellHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/moonwell/MoonwellHyperdriveDeployerCoordinator.sol";
import { MoonwellTarget0Deployer } from "../../../contracts/src/deployers/moonwell/MoonwellTarget0Deployer.sol";
import { MoonwellTarget1Deployer } from "../../../contracts/src/deployers/moonwell/MoonwellTarget1Deployer.sol";
import { MoonwellTarget2Deployer } from "../../../contracts/src/deployers/moonwell/MoonwellTarget2Deployer.sol";
import { MoonwellTarget3Deployer } from "../../../contracts/src/deployers/moonwell/MoonwellTarget3Deployer.sol";
import { MoonwellTarget4Deployer } from "../../../contracts/src/deployers/moonwell/MoonwellTarget4Deployer.sol";
import { MoonwellConversions } from "../../../contracts/src/instances/moonwell/MoonwellConversions.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IMoonwellHyperdrive } from "../../../contracts/src/interfaces/IMoonwellHyperdrive.sol";
import { IMToken } from "../../../contracts/src/interfaces/IMoonwell.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

abstract contract MoonwellHyperdriveInstanceTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// Overrides ///

    /// @dev Gets the extra data used to deploy the Moonwell instance. This is empty.
    /// @return The empty extra data.
    function getExtraData() internal pure override returns (bytes memory) {
        return new bytes(0);
    }

    /// @notice Instantiates the instance testing suite with the configuration.
    /// @param _config The instance test configuration.
    constructor(InstanceTestConfig memory _config) InstanceTest(_config) {}

    /// @dev Converts base amount to the equivalent amount in shares.
    /// @param baseAmount The base amount.
    /// @return The converted share amount.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        return
            MoonwellConversions.convertToShares(
                IMToken(address(config.vaultSharesToken)),
                baseAmount
            );
    }

    /// @dev Converts share amount to the equivalent amount in base.
    /// @param shareAmount The share amount.
    /// @return The converted base amount.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        return
            MoonwellConversions.convertToBase(
                IMToken(address(config.vaultSharesToken)),
                shareAmount
            );
    }

    /// @dev Deploys the Moonwell Hyperdrive deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    /// @return The coordinator address.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new MoonwellHyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new MoonwellHyperdriveCoreDeployer()),
                    address(new MoonwellTarget0Deployer()),
                    address(new MoonwellTarget1Deployer()),
                    address(new MoonwellTarget2Deployer()),
                    address(new MoonwellTarget3Deployer()),
                    address(new MoonwellTarget4Deployer())
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply() internal view override returns (uint256, uint256) {
        return (
            IMToken(address(config.vaultSharesToken)).totalReserves(),
            IMToken(address(config.vaultSharesToken)).totalSupply()
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
            IMToken(address(config.vaultSharesToken)).balanceOf(account)
        );
    }

    /// Getters ///

    /// @dev Test the instances getters.
    function test_getters() external view {
        (, uint256 totalShares) = getTokenBalances(address(hyperdrive));
        IMToken(address(config.vaultSharesToken)).balanceOf(address(this));
        assertEq(hyperdrive.totalShares(), totalShares);
    }

    /// Price Per Share ///

    /// @dev Fuzz test that verifies that the vault share price is the price
    ///      that dictates the conversion between base and shares.
    /// @param basePaid The fuzz parameter for the base paid.
    function test__pricePerVaultShare(uint256 basePaid) external {
        // Ensure that the share price is the expected value.
        (uint256 totalBase, uint256 totalShares) = getSupply();
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(
            vaultSharePrice,
            MoonwellConversions.exchangeRateCurrent(
                IMToken(address(config.vaultSharesToken))
            )
        );

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
        console.log("sharesPaid: ", basePaid.divDown(vaultSharePrice));
        assertApproxEqAbs(
            hyperdriveSharesAfter,
            hyperdriveSharesBefore + basePaid.divDown(vaultSharePrice),
            config.shareTolerance
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
        // Accrue interest to ensure that `exchangeRateCurrent` equals
        // `exchangeRateStored`.
        IMToken mToken = IMToken(address(config.vaultSharesToken));
        mToken.accrueInterest();

        // Gets some data before advancing the time.
        uint256 cash = mToken.getCash();
        uint256 totalAssets = cash +
            mToken.totalBorrows() -
            mToken.totalReserves();

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accruing interest amounts to updating the exchange rate. We do this
        // in two ways:
        //
        // 1. We override the `accrualBlockTimestamp` to be the current block
        //    timestamp to avoid accruing interest because of the `vm.warp`.
        // 2. We update the base balance of the Moonwell pool. This will change
        //    the return value of the `getCash()` getter, which gives us a
        //    degree of freedom to modify the exchange rate.
        vm.store(
            address(mToken),
            bytes32(uint256(9)),
            bytes32(block.timestamp)
        );
        (, int256 interest) = totalAssets.calculateInterest(
            variableRate,
            timeDelta
        );
        setBaseBalance(address(mToken), uint256(int256(cash) + interest));
    }

    /// @dev Sets the base balance of an account.
    /// @param _owner The owner of the tokens.
    /// @param _balance The balance to set.
    function setBaseBalance(address _owner, uint256 _balance) internal virtual;
}
