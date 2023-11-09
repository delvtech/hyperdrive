// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Hyperdrive } from "../Hyperdrive.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";

// TODO: Polish the comments as part of #621.
//
/// @author DELV
/// @title ERC4626Hyperdrive
/// @notice An instance of Hyperdrive that utilizes ERC4626 vaults as a yield source.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Hyperdrive is Hyperdrive {
    using FixedPointMath for uint256;
    using SafeERC20 for IERC20;

    /// @dev The yield source contract for this hyperdrive
    IERC4626 internal immutable pool;

    /// @dev A mapping from addresses to their status as a sweep target. This
    ///      mapping does not change after construction.
    mapping(address target => bool canSweep) internal isSweepable;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _dataProvider The address of the data provider.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The factory which is used to deploy the ERC20
    ///        linker contracts.
    /// @param _pool The ERC4626 compatible yield source.
    /// @param _targets The addresses that can be swept by governance. This
    ///        allows governance to collect rewards derived from incentive
    ///        programs while also preventing edge cases where `sweep` is used
    ///        to access the pool or base tokens.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        address _pool,
        address[] memory _targets
    ) Hyperdrive(_config, _dataProvider, _linkerCodeHash, _linkerFactory) {
        // Initialize the pool immutable.
        pool = IERC4626(_pool);

        // Ensure that the Hyperdrive pool was configured properly.
        // WARN: 4626 implementations should be checked that if they use an
        // asset with decimals less than 18 that the preview deposit is scale
        // invariant. EG - because this line uses a very large query to load
        // price for USDC if the price per share changes based on size of
        // deposit then this line will read an incorrect and possibly dangerous
        // price.
        if (_config.initialSharePrice != _pricePerShare()) {
            revert IHyperdrive.InvalidInitialSharePrice();
        }
        if (address(_config.baseToken) != IERC4626(_pool).asset()) {
            revert IHyperdrive.InvalidBaseToken();
        }

        // Set immutables and prepare for deposits by setting immutables
        if (!_config.baseToken.approve(address(pool), type(uint256).max)) {
            revert IHyperdrive.ApprovalFailed();
        }

        // Set the sweep targets. The base and pool tokens can't be set as sweep
        // targets to prevent governance from rugging the pool.
        for (uint256 i = 0; i < _targets.length; i++) {
            address target = _targets[i];
            if (
                address(target) == address(pool) ||
                address(target) == address(_baseToken)
            ) {
                revert IHyperdrive.UnsupportedToken();
            }
            isSweepable[target] = true;
        }
    }

    /// Yield Source ///

    /// @notice Accepts a trader's deposit in either base or vault shares. If
    ///         the deposit is settled in base, the base is deposited into the
    ///         yield source immediately.
    /// @param _amount The amount of token to transfer
    /// @param _options The options that configure the deposit. The only option
    ///        used in this implementation is "asBase" which determines if
    ///        the deposit is settled in base or vault shares.
    /// @return sharesMinted The shares this deposit creates
    /// @return sharePrice The share price at time of deposit.
    function _deposit(
        uint256 _amount,
        IHyperdrive.Options calldata _options
    ) internal override returns (uint256 sharesMinted, uint256 sharePrice) {
        if (_options.asBase) {
            // Take custody of the deposit in base.
            _baseToken.safeTransferFrom(msg.sender, address(this), _amount);

            // Deposit the base into the yield source.
            sharesMinted = pool.deposit(_amount, address(this));
            sharePrice = _pricePerShare();
        } else {
            // WARN: This logic doesn't account for slippage in the conversion
            // from base to shares. If deposits to the yield source incur
            // slippage, this logic will be incorrect.
            sharesMinted = _amount;

            // Take custody of the deposit in vault shares.
            IERC20(address(pool)).safeTransferFrom(
                msg.sender,
                address(this),
                sharesMinted
            );
            sharePrice = _pricePerShare();
        }
    }

    /// @notice Processes a trader's withdrawal in either base or vault shares.
    ///         If the withdrawal is settled in base, the base will need to be
    ///         withdrawn from the yield source.
    /// @param _shares The amount of shares to withdraw from Hyperdrive.
    /// @param _options The options that configure the withdrawal. The options
    ///        used in this implementation are "destination" which specifies the
    ///        recipient of the withdrawal and "asBase" which determines
    ///        if the withdrawal is settled in base or vault shares.
    /// @return amountWithdrawn The amount withdrawn from the yield source.
    function _withdraw(
        uint256 _shares,
        IHyperdrive.Options calldata _options
    ) internal override returns (uint256 amountWithdrawn) {
        if (_options.asBase) {
            // Redeem from the yield source and transfer the
            // resulting base to the destination address.
            amountWithdrawn = pool.redeem(
                _shares,
                _options.destination,
                address(this)
            );
        } else {
            // Transfer vault shares to the destination.
            IERC20(address(pool)).safeTransfer(_options.destination, _shares);
            amountWithdrawn = _shares;
        }
    }

    /// @notice Loads the share price from the yield source.
    /// @return The current share price.
    /// @dev must remain consistent with the impl inside of the DataProvider
    function _pricePerShare() internal view override returns (uint256) {
        return pool.convertToAssets(FixedPointMath.ONE_18);
    }

    /// @notice Some yield sources [eg Morpho] pay rewards directly to this
    ///         contract but we can't handle distributing them internally so we
    ///         sweep to the fee collector address to then redistribute to users.
    /// @dev WARN: The entire balance of any of the sweep targets can be swept
    ///      by governance. If these sweep targets provide access to the base or
    ///      pool token, then governance has the ability to rug the pool.
    /// @dev WARN: It is unlikely but possible that there is a selector overlap
    ///      with 'transferFrom'. Any integrating contracts should be checked
    ///      for that, as it may result in an unexpected call from this address.
    /// @param _target The token to sweep.
    function sweep(IERC20 _target) external {
        // Ensure that the sender is the fee collector or a pauser.
        if (msg.sender != _feeCollector && !_pausers[msg.sender])
            revert IHyperdrive.Unauthorized();

        // Ensure that thet target can be swept by governance.
        if (!isSweepable[address(_target)]) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Transfer the entire balance of the sweep target to the fee collector.
        uint256 balance = _target.balanceOf(address(this));
        _target.safeTransfer(_feeCollector, balance);
    }
}
