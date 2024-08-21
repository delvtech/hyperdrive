// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { MorphoBlueConversions } from "../../instances/morpho-blue/MorphoBlueConversions.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IMorphoBlueHyperdrive } from "../../interfaces/IMorphoBlueHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../../interfaces/IHyperdriveDeployerCoordinator.sol";
import { MORPHO_BLUE_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND } from "../../libraries/Constants.sol";
import { ONE } from "../../libraries/FixedPointMath.sol";
import { HyperdriveDeployerCoordinator } from "../HyperdriveDeployerCoordinator.sol";

/// @author DELV
/// @title MorphoBlueHyperdriveDeployerCoordinator
/// @notice The deployer coordinator for the MorphoBlueHyperdrive
///         implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MorphoBlueHyperdriveDeployerCoordinator is
    HyperdriveDeployerCoordinator
{
    using SafeERC20 for ERC20;

    /// @notice The deployer coordinator's kind.
    string public constant override kind =
        MORPHO_BLUE_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND;

    /// @notice Instantiates the deployer coordinator.
    /// @param _name The deployer coordinator's name.
    /// @param _factory The factory that this deployer will be registered with.
    /// @param _coreDeployer The core deployer.
    /// @param _target0Deployer The target0 deployer.
    /// @param _target1Deployer The target1 deployer.
    /// @param _target2Deployer The target2 deployer.
    /// @param _target3Deployer The target3 deployer.
    /// @param _target4Deployer The target4 deployer.
    constructor(
        string memory _name,
        address _factory,
        address _coreDeployer,
        address _target0Deployer,
        address _target1Deployer,
        address _target2Deployer,
        address _target3Deployer,
        address _target4Deployer
    )
        HyperdriveDeployerCoordinator(
            _name,
            _factory,
            _coreDeployer,
            _target0Deployer,
            _target1Deployer,
            _target2Deployer,
            _target3Deployer,
            _target4Deployer
        )
    {}

    /// @dev Prepares the coordinator for initialization by drawing funds from
    ///      the LP, if necessary.
    /// @param _hyperdrive The Hyperdrive instance that is being initialized.
    /// @param _lp The LP that is initializing the pool.
    /// @param _contribution The amount of capital to supply. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _options The options that configure how the initialization is
    ///        settled.
    /// @return value The value that should be sent in the initialize transaction.
    function _prepareInitialize(
        IHyperdrive _hyperdrive,
        address _lp,
        uint256 _contribution,
        IHyperdrive.Options memory _options
    ) internal override returns (uint256 value) {
        // Depositing with shares is not supported.
        if (!_options.asBase) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Transfer base from the LP and approve the Hyperdrive pool.
        ERC20 baseToken = ERC20(_hyperdrive.baseToken());
        baseToken.safeTransferFrom(_lp, address(this), _contribution);
        baseToken.forceApprove(address(_hyperdrive), _contribution);

        // This yield source isn't payable, so we should always send 0 value.
        return 0;
    }

    /// @notice Convert an amount of vault shares to an amount of base.
    /// @param _baseToken The base token underlying the Aave vault.
    /// @param _vault The Morpho Blue contract.
    /// @param _baseToken The collateral token for this Morpho Blue market.
    /// @param _oracle The oracle for this Morpho Blue market.
    /// @param _irm The IRM for this Morpho Blue market.
    /// @param _lltv The LLTV for this Morpho Blue market.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IMorpho _vault,
        IERC20 _baseToken,
        address _collateralToken,
        address _oracle,
        address _irm,
        uint256 _lltv,
        uint256 _shareAmount
    ) public view returns (uint256) {
        return
            MorphoBlueConversions.convertToBase(
                _vault,
                _baseToken,
                _collateralToken,
                _oracle,
                _irm,
                _lltv,
                _shareAmount
            );
    }

    /// @notice Convert an amount of base to an amount of vault shares.
    /// @param _baseToken The base token underlying the Aave vault.
    /// @param _vault The Morpho Blue contract.
    /// @param _baseToken The collateral token for this Morpho Blue market.
    /// @param _oracle The oracle for this Morpho Blue market.
    /// @param _irm The IRM for this Morpho Blue market.
    /// @param _lltv The LLTV for this Morpho Blue market.
    /// @param _baseAmount The base amount.
    /// @return The base amount.
    function convertToShares(
        IMorpho _vault,
        IERC20 _baseToken,
        address _collateralToken,
        address _oracle,
        address _irm,
        uint256 _lltv,
        uint256 _baseAmount
    ) public view returns (uint256) {
        return
            MorphoBlueConversions.convertToShares(
                _vault,
                _baseToken,
                _collateralToken,
                _oracle,
                _irm,
                _lltv,
                _baseAmount
            );
    }

    /// @dev We override the message value check since this integration is
    ///      not payable.
    function _checkMessageValue() internal view override {
        if (msg.value != 0) {
            revert IHyperdriveDeployerCoordinator.NotPayable();
        }
    }

    /// @notice Checks the pool configuration to ensure that it is valid.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    /// @param _extraData The empty extra data.
    function _checkPoolConfig(
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory _extraData
    ) internal view override {
        // Perform the default checks.
        super._checkPoolConfig(_deployConfig, _extraData);

        // Ensure that the vault shares token address is zero. This makes it
        // clear that there isn't a vault shares token backing the Morpho Blue
        // integration.
        if (address(_deployConfig.vaultSharesToken) != address(0)) {
            revert IHyperdriveDeployerCoordinator.InvalidVaultSharesToken();
        }

        // Ensure that the base token address is properly configured.
        if (address(_deployConfig.baseToken) == address(0)) {
            revert IHyperdriveDeployerCoordinator.InvalidBaseToken();
        }

        // Ensure that the minimum share reserves are large enough to meet the
        // minimum requirements for safety.
        //
        // NOTE: Some pools may require larger minimum share reserves to be
        // considered safe. This is just a sanity check.
        if (
            _deployConfig.minimumShareReserves <
            10 ** (_deployConfig.baseToken.decimals() - 3)
        ) {
            revert IHyperdriveDeployerCoordinator.InvalidMinimumShareReserves();
        }

        // Ensure that the minimum transaction amount is large enough to meet
        // the minimum requirements for safety.
        //
        // NOTE: Some pools may require larger minimum transaction amounts to be
        // considered safe. This is just a sanity check.
        if (
            _deployConfig.minimumTransactionAmount <
            10 ** (_deployConfig.baseToken.decimals() - 3)
        ) {
            revert IHyperdriveDeployerCoordinator
                .InvalidMinimumTransactionAmount();
        }
    }

    /// @dev Gets the initial vault share price of the Hyperdrive pool.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    /// @param _extraData The extra data for the Morpho instance. This contains
    ///        the market parameters that weren't specified in the config.
    /// @return The initial vault share price of the Hyperdrive pool.
    function _getInitialVaultSharePrice(
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory _extraData
    ) internal view override returns (uint256) {
        IMorphoBlueHyperdrive.MorphoBlueParams memory params = abi.decode(
            _extraData,
            (IMorphoBlueHyperdrive.MorphoBlueParams)
        );
        return
            convertToBase(
                params.morpho,
                _deployConfig.baseToken,
                params.collateralToken,
                params.oracle,
                params.irm,
                params.lltv,
                ONE
            );
    }
}
