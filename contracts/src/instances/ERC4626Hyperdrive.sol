// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC4626 } from "../interfaces/IERC4626.sol";
import { Hyperdrive } from "../Hyperdrive.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @author DELV
/// @title ERC4626Hyperdrive
/// @notice An instance of Hyperdrive that utilizes ERC4626 vaults as a yield source.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Hyperdrive is Hyperdrive {
    using FixedPointMath for uint256;
    using SafeERC20 for IERC20;

    // The yield source contract for this hyperdrive
    IERC4626 internal immutable pool;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _dataProvider The address of the data provider.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The factory which is used to deploy the ERC20
    ///        linker contracts.
    /// @param _pool The ERC4626 compatible yield source
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC4626 _pool
    ) Hyperdrive(_config, _dataProvider, _linkerCodeHash, _linkerFactory) {
        // Initialize the pool immutable.
        pool = _pool;

        // Ensure that the Hyperdrive pool was configured properly.
        // WARN - 4626 implementations should be checked that if they use an asset
        //        with decimals less than 18 that the preview deposit is scale
        //        invariant. EG - because this line uses a very large query to load
        //        price for USDC if the price per share changes based on size of deposit
        //        then this line will read an incorrect and possibly dangerous price.
        if (_config.initialSharePrice != _pricePerShare()) {
            revert IHyperdrive.InvalidInitialSharePrice();
        }
        if (address(_config.baseToken) != _pool.asset()) {
            revert IHyperdrive.InvalidBaseToken();
        }

        // Set immutables and prepare for deposits by setting immutables
        if (!_config.baseToken.approve(address(pool), type(uint256).max)) {
            revert IHyperdrive.ApprovalFailed();
        }
    }

    /// Yield Source ///

    /// @notice Transfers amount of 'token' from the user and commits it to the yield source.
    /// @param amount The amount of token to transfer
    /// @param asUnderlying If true the yield source will transfer underlying tokens
    ///                     if false it will transfer the yielding asset directly
    /// @return sharesMinted The shares this deposit creates
    /// @return sharePrice The share price at time of deposit
    function _deposit(
        uint256 amount,
        bool asUnderlying
    ) internal override returns (uint256 sharesMinted, uint256 sharePrice) {
        if (asUnderlying) {
            // Transfer from user
            _baseToken.safeTransferFrom(msg.sender, address(this), amount);
            // Supply for the user
            sharesMinted = pool.deposit(amount, address(this));
            sharePrice = _pricePerShare();
        } else {
            // Calculate the current exchange rate for these
            // WARN - IF an ERC4626 has significant differences between a
            //        price perShare in aggregate vs one for individual users
            //        then this can create bugs.
            uint256 converted = pool.convertToShares(amount);
            // Transfer erc4626 shares from the user
            IERC20(address(pool)).safeTransferFrom(
                msg.sender,
                address(this),
                converted
            );
            sharesMinted = converted;
            sharePrice = _pricePerShare();
        }
    }

    /// @notice Withdraws shares from the yield source and sends the resulting tokens to the destination
    /// @param shares The shares to withdraw from the yield source
    /// @param asUnderlying If true the yield source will transfer underlying tokens
    ///                     if false it will transfer the yielding asset directly
    /// @param destination The address which is where to send the resulting tokens
    /// @return amountWithdrawn the amount of 'token' produced by this withdraw
    function _withdraw(
        uint256 shares,
        address destination,
        bool asUnderlying
    ) internal override returns (uint256 amountWithdrawn) {
        if (asUnderlying) {
            // In this case we simply withdraw
            amountWithdrawn = pool.redeem(shares, destination, address(this));
        } else {
            // Transfer erc4626 shares to the user
            IERC20(address(pool)).safeTransfer(destination, shares);
            // Now we calculate the price per share
            uint256 estimated = pool.convertToAssets(shares);
            amountWithdrawn = estimated;
        }
    }

    /// @notice Loads the share price from the yield source.
    /// @return The current share price.
    /// @dev must remain consistent with the impl inside of the DataProvider
    function _pricePerShare() internal view override returns (uint256) {
        return pool.convertToAssets(FixedPointMath.ONE_18);
    }

    /// @notice Some yield sources [eg Morpho] pay rewards directly to this contract
    ///         but we can't handle distributing them internally so we sweep to the
    ///         fee collector address to then redistribute to users
    /// @param token The ERC20 we want to call
    /// @dev WARNING - This sweep only checks that the token is not equal to the base or yield source
    ///                if another token is expected to have a balance on this contract it is unsafe.
    ///                ANY TOKENS IN THIS CONTRACT BESIDES YIELD SOURCE SHARES OR BASE TOKEN CAN BE STOLEN.
    /// @dev WARNING - It is unlikely but possible that there is a selector overlap with 'transferFrom'. Any
    ///                integrating contracts should be checked for that, as it may result in an unexpected call
    ///                from this address.
    function sweep(IERC20 token) external {
        // Only governance address can call
        if (msg.sender != _feeCollector && !_pausers[msg.sender])
            revert IHyperdrive.Unauthorized();
        // Cannot rug the yield source or base token
        if (
            address(token) == address(pool) ||
            address(token) == address(_baseToken)
        ) revert IHyperdrive.UnsupportedToken();
        // Transfer to the fee collector
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(_feeCollector, balance);
    }
}
