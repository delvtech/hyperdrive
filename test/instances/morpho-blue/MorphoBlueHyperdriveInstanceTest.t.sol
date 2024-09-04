// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Id, IMorpho, Market, MarketParams } from "morpho-blue/src/interfaces/IMorpho.sol";
import { MarketParamsLib } from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { MorphoBalancesLib } from "morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import { MorphoBlueHyperdriveCoreDeployer } from "../../../contracts/src/deployers/morpho-blue/MorphoBlueHyperdriveCoreDeployer.sol";
import { MorphoBlueHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/morpho-blue/MorphoBlueHyperdriveDeployerCoordinator.sol";
import { MorphoBlueTarget0Deployer } from "../../../contracts/src/deployers/morpho-blue/MorphoBlueTarget0Deployer.sol";
import { MorphoBlueTarget1Deployer } from "../../../contracts/src/deployers/morpho-blue/MorphoBlueTarget1Deployer.sol";
import { MorphoBlueTarget2Deployer } from "../../../contracts/src/deployers/morpho-blue/MorphoBlueTarget2Deployer.sol";
import { MorphoBlueTarget3Deployer } from "../../../contracts/src/deployers/morpho-blue/MorphoBlueTarget3Deployer.sol";
import { MorphoBlueTarget4Deployer } from "../../../contracts/src/deployers/morpho-blue/MorphoBlueTarget4Deployer.sol";
import { MorphoBlueConversions } from "../../../contracts/src/instances/morpho-blue/MorphoBlueConversions.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IMorphoBlueHyperdrive } from "../../../contracts/src/interfaces/IMorphoBlueHyperdrive.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

abstract contract MorphoBlueHyperdriveInstanceTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The Morpho Blue parameters for this test.
    IMorphoBlueHyperdrive.MorphoBlueParams internal morphoBlueParams;

    /// @notice Instantiates the MorphoBlueHyperdriveInstanceTest.
    /// @param _config The instance test configuration.
    /// @param _morphoBlueParams The Morpho Blue parameters.
    constructor(
        InstanceTestConfig memory _config,
        IMorphoBlueHyperdrive.MorphoBlueParams memory _morphoBlueParams
    ) InstanceTest(_config) {
        morphoBlueParams = _morphoBlueParams;
    }

    /// Overrides ///

    /// @dev Gets the extra data used to the Morpho Blue Hyperdrive instance.
    ///      This extra data contains information about the Morpho market like
    ///      the Morpho Blue pool address, the collateral token, the oracle
    ///      address, the interest rate model address, and the liquidation loan
    ///      to value ratio.
    /// @return The extra data containing information about the Morpho Blue
    ///         market.
    function getExtraData() internal view override returns (bytes memory) {
        return abi.encode(morphoBlueParams);
    }

    /// @dev Converts base amount to the equivalent about in shares.
    /// @param baseAmount The base amount.
    /// @return The converted share amount.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        return
            MorphoBlueConversions.convertToShares(
                morphoBlueParams.morpho,
                config.baseToken,
                morphoBlueParams.collateralToken,
                morphoBlueParams.oracle,
                morphoBlueParams.irm,
                morphoBlueParams.lltv,
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
            MorphoBlueConversions.convertToBase(
                morphoBlueParams.morpho,
                config.baseToken,
                morphoBlueParams.collateralToken,
                morphoBlueParams.oracle,
                morphoBlueParams.irm,
                morphoBlueParams.lltv,
                shareAmount
            );
    }

    /// @dev Deploys the rsETH Linea deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    /// @return The coordinator address.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new MorphoBlueHyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new MorphoBlueHyperdriveCoreDeployer()),
                    address(new MorphoBlueTarget0Deployer()),
                    address(new MorphoBlueTarget1Deployer()),
                    address(new MorphoBlueTarget2Deployer()),
                    address(new MorphoBlueTarget3Deployer()),
                    address(new MorphoBlueTarget4Deployer())
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply() internal view override returns (uint256, uint256) {
        (
            uint256 totalSupplyAssets,
            uint256 totalSupplyShares,
            ,

        ) = morphoBlueParams.morpho.expectedMarketBalances(
                MarketParams({
                    loanToken: address(config.baseToken),
                    collateralToken: morphoBlueParams.collateralToken,
                    oracle: morphoBlueParams.oracle,
                    irm: morphoBlueParams.irm,
                    lltv: morphoBlueParams.lltv
                })
            );
        return (totalSupplyAssets, totalSupplyShares);
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
            morphoBlueParams
                .morpho
                .position(
                    MarketParams({
                        loanToken: address(config.baseToken),
                        collateralToken: morphoBlueParams.collateralToken,
                        oracle: morphoBlueParams.oracle,
                        irm: morphoBlueParams.irm,
                        lltv: morphoBlueParams.lltv
                    }).id(),
                    account
                )
                .supplyShares
        );
    }

    /// Getters ///

    /// @dev Test the instances getters. In the case of Morpho Blue, we need to
    ///      ensure that we can get all of the identifying information about the
    ///      Morpho Blue market.
    function test_getters() external view {
        assertEq(
            IMorphoBlueHyperdrive(address(hyperdrive)).vault(),
            address(morphoBlueParams.morpho)
        );
        assertEq(
            IMorphoBlueHyperdrive(address(hyperdrive)).collateralToken(),
            morphoBlueParams.collateralToken
        );
        assertEq(
            IMorphoBlueHyperdrive(address(hyperdrive)).oracle(),
            morphoBlueParams.oracle
        );
        assertEq(
            IMorphoBlueHyperdrive(address(hyperdrive)).irm(),
            morphoBlueParams.irm
        );
        assertEq(
            IMorphoBlueHyperdrive(address(hyperdrive)).lltv(),
            morphoBlueParams.lltv
        );
        assertEq(
            Id.unwrap(IMorphoBlueHyperdrive(address(hyperdrive)).id()),
            Id.unwrap(
                MarketParams({
                    loanToken: address(config.baseToken),
                    collateralToken: morphoBlueParams.collateralToken,
                    oracle: morphoBlueParams.oracle,
                    irm: morphoBlueParams.irm,
                    lltv: morphoBlueParams.lltv
                }).id()
            )
        );
        (, uint256 totalShares) = getTokenBalances(address(hyperdrive));
        assertEq(hyperdrive.totalShares(), totalShares);
    }

    /// Price Per Share ///

    /// @dev Fuzz test that verifies that the vault share price is the price
    ///      that dictates the conversion between base and shares.
    /// @param basePaid The fuzz parameter for the base paid.
    function test__pricePerVaultShare(uint256 basePaid) external {
        // Ensure that the share price is the expected value.
        (
            uint256 totalSupplyAssets,
            uint256 totalSupplyShares,
            ,

        ) = morphoBlueParams.morpho.expectedMarketBalances(
                MarketParams({
                    loanToken: address(config.baseToken),
                    collateralToken: morphoBlueParams.collateralToken,
                    oracle: morphoBlueParams.oracle,
                    irm: morphoBlueParams.irm,
                    lltv: morphoBlueParams.lltv
                })
            );
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, totalSupplyAssets.divDown(totalSupplyShares));

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
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in the Morpho market. This amounts to manually
        // updating the total supply assets and the last update time.
        Id marketId = MarketParams({
            loanToken: address(config.baseToken),
            collateralToken: morphoBlueParams.collateralToken,
            oracle: morphoBlueParams.oracle,
            irm: morphoBlueParams.irm,
            lltv: morphoBlueParams.lltv
        }).id();
        Market memory market = morphoBlueParams.morpho.market(marketId);
        (uint256 totalSupplyAssets, ) = uint256(market.totalSupplyAssets)
            .calculateInterest(variableRate, timeDelta);
        bytes32 marketLocation = keccak256(abi.encode(marketId, 3));
        vm.store(
            address(morphoBlueParams.morpho),
            marketLocation,
            bytes32(
                (uint256(market.totalSupplyShares) << 128) | totalSupplyAssets
            )
        );
        vm.store(
            address(morphoBlueParams.morpho),
            bytes32(uint256(marketLocation) + 2),
            bytes32((uint256(market.fee) << 128) | uint256(block.timestamp))
        );

        // In order to prevent transfers from failing, we also need to increase
        // the DAI balance of the Morpho vault to match the total assets.
        mintBaseTokens(address(morphoBlueParams.morpho), totalSupplyAssets);
    }

    /// @dev Mints base tokens to a specified account.
    /// @param _recipient The recipient of the minted tokens.
    /// @param _amount The amount of tokens to mint.
    function mintBaseTokens(
        address _recipient,
        uint256 _amount
    ) internal virtual;
}
