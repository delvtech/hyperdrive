// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "./interfaces/IHyperdrive.sol";
import "./interfaces/IERC20.sol";
import "./libraries/ERC20Permit.sol";
import "./libraries/Errors.sol";
import "contracts/libraries/AssetId.sol";

contract StableWrapper is ERC20Permit {
    // The multitoken of the bond
    IHyperdrive public immutable bond;
    // The underlying token from the bond
    IERC20 public immutable token;
    // The basis points [ie out of 10000] which will be minted for a bond deposit
    // TODO - Should we make this mutable and updatable?
    uint256 public immutable mintPercent;

    // Store the user deposits and withdraws
    mapping(address => mapping(uint256 => uint256)) userAccounts;

    /// @notice Constructs the contract and initializes the variables.
    /// @param _bond The hyperdrive contract.
    /// @param _token The underlying token of the bonds.
    /// @param _mintPercent How many tokens will be minted per bond.
    /// @param name_ The ERC20 name.
    /// @param symbol_ The ERC20 symbol.
    constructor(
        IHyperdrive _bond,
        IERC20 _token,
        uint256 _mintPercent,
        string memory name_,
        string memory symbol_
    ) ERC20Permit(name_, symbol_) {
        // Set the immutables
        bond = _bond;
        token = _token;
        mintPercent = _mintPercent;
    }

    /// @notice Transfers bonds from the user and then mints erc20 for the mintable percent.
    /// @param openSharePrice The bond's initial share price
    /// @param expiryTime The bond's expiry time
    /// @param amount The amount of bonds to mint
    function mint(
        uint256 openSharePrice,
        uint256 expiryTime,
        uint256 amount
    ) external {
        // Encode the asset ID
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            openSharePrice,
            expiryTime
        );

        // Must not be expired
        if (expiryTime <= block.timestamp) revert Errors.BondExpired();
        // Transfer from the user
        bond.transferFrom(assetId, msg.sender, address(this), amount);

        // Mint them the tokens for their deposit
        uint256 mintAmount = (amount * mintPercent) / 10000;
        _mint(msg.sender, mintAmount);

        // Add this to the deposited amount
        userAccounts[msg.sender][assetId] += amount;
    }

    /// @notice Closes a user account by selling the bond and then transferring the delta value of that
    ///         sale vs the erc20 tokens minted by its deposit. Optionally also burns the ERC20 wrapper
    ///         from the user, if enabled it will transfer both the delta of sale value and the value of
    ///         the burned token.
    /// @param openSharePrice The bond which was used as collateral 's opening share price.
    /// @param expiryTime The bond's expiry time
    /// @param amount The amount of bonds to redeem
    /// @param andBurn If true it will burn the number of erc20 minted by this deposited bond
    function close(
        uint256 openSharePrice,
        uint256 expiryTime,
        uint256 amount,
        bool andBurn
    ) external {
        // Encode the asset ID
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            openSharePrice,
            expiryTime
        );

        // We unload the variables from storage on the user account
        uint256 userAccount = userAccounts[msg.sender][assetId];
        // Forces overflow and deletion of bits in top 128 bits
        uint256 deposited = (userAccount << 128) >> 128;
        uint256 forceClosed = (userAccount >> 128);

        // Close the user position
        uint256 receivedAmount;
        if (forceClosed == 0) {
            // Close the bond [selling if earlier than the expiration]
            receivedAmount = bond.closeLong(
                openSharePrice,
                uint32(expiryTime),
                amount
            );
            // Update the user account data, note this sub is safe because the top bits are zero.
            userAccounts[msg.sender][assetId] -= amount;
        } else {
            // If the user account was already closed we use the recorded closing price
            receivedAmount = (forceClosed * amount) / deposited;
            // Update the user account
            deposited -= amount;
            forceClosed -= receivedAmount;
            userAccounts[msg.sender][assetId] = (forceClosed << 128) + deposited;
        }

        // We require that this won't make the position unbacked
        uint256 mintedFromBonds = (amount * mintPercent) / 10000;
        if (receivedAmount < mintedFromBonds) revert Errors.InsufficientPrice();

        // The user gets at least the interest implied from
        uint256 userFunds = receivedAmount - mintedFromBonds;

        // If the user would also like to burn the erc20 from their wallet
        if (andBurn) {
            _burn(msg.sender, mintedFromBonds);
            userFunds += mintedFromBonds;
        }

        // Transfer the released funds to the user
        bool success = token.transfer(msg.sender, userFunds);
        if (!success) revert Errors.TransferFailed();
    }

    /// @notice Allows a user to liquidate the contents of an account they do not own if
    ///         the bond has already expired. This cannot harm the user in question as the
    ///         bond price will not increase above one. Funds freed remain in the contract.
    /// @param user The user who's account will be liquidated
    /// @param openSharePrice The user's bond's open share price
    /// @param expiryTime The user's bond's expiry time.
    function forceClose(
        address user,
        uint256 openSharePrice,
        uint256 expiryTime
    ) public {
        // Encode the asset ID
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            openSharePrice,
            expiryTime
        );
        // We unload the variables from storage on the user account
        uint256 userAccount = userAccounts[user][assetId];
        // Forces overflow and deletion of bits in top 128 bits
        uint256 deposited = (userAccount << 128) >> 128;
        uint256 forceClosed = (userAccount >> 128);

        // Cannot close again
        if (forceClosed != 0) revert Errors.AlreadyClosed();
        // Cannot close if not expired
        if (expiryTime > block.timestamp) revert Errors.BondNotExpired();

        // Close the long
        uint256 receivedAmount = bond.closeLong(
            openSharePrice,
            uint32(expiryTime),
            deposited
        );
        // Store the user account update
        userAccounts[user][assetId] = (receivedAmount << 128) + deposited;
    }

    /// @notice Burns a caller's erc20 and transfers the result from the contract's token balance.
    /// @param amount The amount of erc20 wrapper to burn.
    function redeem(uint256 amount) public {
        // Simply burn from the user and send funds from the contract balance
        _burn(msg.sender, amount);

        // Transfer the released funds to the user
        bool success = token.transfer(msg.sender, amount);
        if (!success) revert Errors.TransferFailed();
    }

    /// @notice Calls both force close and redeem to enable easy liquidation of a user account
    /// @param user The user who's account will be liquidated
    /// @param openSharePrice The user's bond's open share price
    /// @param expiryTime The user's bond's expiry time.
    /// @param amount The amount of erc20 wrapper to burn.
    function forceCloseAndRedeem(
        address user,
        uint256 openSharePrice,
        uint256 expiryTime,
        uint256 amount
    ) external {
        forceClose(user, openSharePrice, expiryTime);
        redeem(amount);
    }
}
