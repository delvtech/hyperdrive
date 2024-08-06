// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC20 } from "./IERC20.sol";

abstract contract IERC4626 is IERC20 {
    /// @notice Emitted when funds are deposited into the vault.
    event Deposit(
        address indexed sender,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );

    /// @notice Emitted when funds are withdrawn from the vault.
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );

    /// @notice The underlying asset of the vault.
    /// @return asset The underlying asset.
    function asset() external view virtual returns (address asset);

    /// @notice The total number of underlying assets held by the vault.
    /// @return totalAssets The total number of underlying assets.
    function totalAssets() external view virtual returns (uint256 totalAssets);

    /// @notice Deposits assets into the vault and mints shares.
    /// @param assets The amount of assets to deposit.
    /// @param receiver The address that will receive the shares.
    /// @return shares The amount of shares minted.
    function deposit(
        uint256 assets,
        address receiver
    ) external virtual returns (uint256 shares);

    /// @notice Mints a specified amount of shares for a receiver.
    /// @param shares The amount of shares to mint.
    /// @param receiver The address that will receive the shares.
    /// @return assets The amount of assets required to mint the shares.
    function mint(
        uint256 shares,
        address receiver
    ) external virtual returns (uint256 assets);

    /// @notice Withdraws assets from the vault and burns shares.
    /// @param assets The amount of assets to withdraw.
    /// @param receiver The address that will receive the assets.
    /// @param owner The address that owns the shares.
    /// @return shares The amount of shares burned.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external virtual returns (uint256 shares);

    /// @notice Burns a specified amount of shares for an owner.
    /// @param shares The amount of shares to burn.
    /// @param receiver The address that will receive the assets.
    /// @param owner The address that owns the shares.
    /// @return assets The amount of assets received for burning the shares.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external virtual returns (uint256 assets);

    /// @notice Converts an amount of assets to shares.
    /// @param assets The amount of assets to convert.
    /// @return shares The amount of shares that would be minted.
    function convertToShares(
        uint256 assets
    ) external view virtual returns (uint256 shares);

    /// @notice Converts an amount of shares to assets.
    /// @param shares The amount of shares to convert.
    /// @return assets The amount of assets that would be received.
    function convertToAssets(
        uint256 shares
    ) external view virtual returns (uint256 assets);

    /// @notice The maximum amount of assets that can be deposited into the
    ///         vault.
    /// @param owner The address of the account that would deposit the assets.
    /// @return maxAssets The maximum amount of assets that can be deposited.
    function maxDeposit(
        address owner
    ) external view virtual returns (uint256 maxAssets);

    /// @notice Previews the amount of shares that would be minted for a
    ///         given amount of assets.
    /// @param assets The amount of assets to deposit.
    /// @return shares The amount of shares that would be minted.
    function previewDeposit(
        uint256 assets
    ) external view virtual returns (uint256 shares);

    /// @notice The maximum number of shares that can be minted by `owner`.
    /// @param owner The address of the account that would mint the shares.
    /// @return maxShares The maximum number of shares that can be minted.
    function maxMint(
        address owner
    ) external view virtual returns (uint256 maxShares);

    /// @notice Previews the amount of assets that would be minted for a
    ///         given amount of shares.
    /// @param shares The amount of shares to mint.
    /// @return assets The amount of assets deposited.
    function previewMint(
        uint256 shares
    ) external view virtual returns (uint256 assets);

    /// @notice The maximum amount of assets that can be withdrawn from the
    ///         vault.
    /// @param owner The address of the account that would withdraw the assets.
    /// @return maxAssets The maximum amount of assets that can be withdrawn.
    function maxWithdraw(
        address owner
    ) external view virtual returns (uint256 maxAssets);

    /// @notice Previews the amount of shares that would be burned for a
    ///         given amount of assets.
    /// @param assets The amount of assets to withdraw.
    /// @return shares The amount of shares that would be burned.
    function previewWithdraw(
        uint256 assets
    ) external view virtual returns (uint256 shares);

    /// @notice The maximum number of shares that can be redeemed by `owner`.
    /// @param owner The address of the account that would redeem the shares.
    /// @return maxShares The maximum number of shares that can be redeemed.
    function maxRedeem(
        address owner
    ) external view virtual returns (uint256 maxShares);

    /// @notice Previews the amount of assets that would be received for a
    ///         given amount of shares.
    /// @param shares The amount of shares to redeem.
    /// @return assets The amount of assets received.
    function previewRedeem(
        uint256 shares
    ) external view virtual returns (uint256 assets);
}
