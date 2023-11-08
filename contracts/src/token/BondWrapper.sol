// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { AssetId } from "../libraries/AssetId.sol";

/// @author DELV
/// @title BondWrapper
/// @notice A token that wraps Hyperdrive long positions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract BondWrapper is ERC20 {
    // The multitoken of the bond
    IHyperdrive public immutable hyperdrive;
    // The underlying token from the bond
    IERC20 public immutable token;
    // The basis points [ie out of 10000] which will be minted for a bond deposit
    uint256 public immutable mintPercent;

    // Store the user deposits as a mapping from user address -> asset id -> amount
    mapping(address user => mapping(uint256 assetId => uint256 amount))
        public deposits;

    /// @notice Constructs the contract and initializes the variables.
    /// @param _hyperdrive The hyperdrive contract.
    /// @param _token The underlying token of the bonds.
    /// @param _mintPercent How many tokens will be minted per bond.
    /// @param name_ The ERC20 name.
    /// @param symbol_ The ERC20 symbol.
    constructor(
        IHyperdrive _hyperdrive,
        IERC20 _token,
        uint256 _mintPercent,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_, 18) {
        if (_mintPercent >= 10_000) {
            revert IHyperdrive.MintPercentTooHigh();
        }

        // By setting these addresses to the max uint256, attempting to execute
        // a transfer to either of them will revert. This is a gas efficient way
        // to prevent a common user mistake where they transfer to the token
        // address. These values are not considered 'real' tokens and so are not
        // included in 'total supply' which only contains minted tokens.
        // WARN - Never allow allowances to be set for these addresses.
        balanceOf[address(0)] = type(uint256).max;
        balanceOf[address(this)] = type(uint256).max;

        // Set the immutables
        hyperdrive = _hyperdrive;
        token = _token;
        mintPercent = _mintPercent;
    }

    /// @notice Transfers bonds from the user and then mints erc20 for the mintable percent.
    /// @param  maturityTime The bond's expiry time
    /// @param amount The amount of bonds to mint
    /// @param destination The address which gets credited with these funds
    function mint(
        uint256 maturityTime,
        uint256 amount,
        address destination
    ) external {
        // Must not be matured
        if (maturityTime <= block.timestamp) revert IHyperdrive.BondMatured();

        // Encode the asset ID
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );

        // Transfer from the user
        hyperdrive.transferFrom(assetId, msg.sender, address(this), amount);

        // Mint them the tokens for their deposit
        uint256 mintAmount = (amount * mintPercent) / 10_000;
        _mint(destination, mintAmount);

        // Add this to the deposited amount
        deposits[destination][assetId] += amount;
    }

    /// @notice Closes a user account by selling the bond and then transferring the delta value of that
    ///         sale vs the erc20 tokens minted by its deposit. Optionally also burns the ERC20 wrapper
    ///         from the user, if enabled it will transfer both the delta of sale value and the value of
    ///         the burned token.
    /// @param  maturityTime The bond's expiry time
    /// @param amount The amount of bonds to redeem
    /// @param andBurn If true it will burn the number of erc20 minted by this deposited bond
    /// @param destination The address which gets credited with this withdraw
    /// @param minOutput The min amount the user expects transferred to them.
    /// @param extraData Extra data to pass to the yield source.
    function close(
        uint256 maturityTime,
        uint256 amount,
        bool andBurn,
        address destination,
        uint256 minOutput,
        bytes memory extraData
    ) external {
        // Encode the asset ID
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );

        uint256 receivedAmount;
        if (maturityTime > block.timestamp) {
            // Close the bond [selling if earlier than the expiration]
            receivedAmount = hyperdrive.closeLong(
                maturityTime,
                amount,
                0,
                IHyperdrive.Options({
                    destination: address(this),
                    asBase: true,
                    extraData: extraData
                })
            );
        } else {
            // Sell all assets
            sweep(maturityTime, extraData);
            // Sweep guarantees 1 to 1 conversion so the user gets exactly the amount they are closing
            receivedAmount = amount;
        }
        // Update the user balances
        deposits[msg.sender][assetId] -= amount;

        // Close the user position
        // We require that this won't make the position unbacked
        uint256 mintedFromBonds = (amount * mintPercent) / 10_000;

        if (receivedAmount < mintedFromBonds)
            revert IHyperdrive.InsufficientPrice();

        // The user gets at least the interest implied from
        uint256 userFunds = receivedAmount - mintedFromBonds;

        // If the user would also like to burn the erc20 from their wallet
        if (andBurn) {
            _burn(msg.sender, mintedFromBonds);
            userFunds += mintedFromBonds;
        }

        // The user has to get at least what they expect.
        if (userFunds < minOutput) revert IHyperdrive.OutputLimit();

        // Transfer the released funds to the user
        SafeTransferLib.safeTransfer(
            ERC20(address(token)),
            destination,
            userFunds
        );
    }

    /// @notice Sells all assets from the contract if they are matured, has no affect if
    ///         the contract has no assets from a timestamp
    /// @param maturityTime The maturity time of the asset to sell
    /// @param extraData Extra data to pass to the yield source.
    function sweep(uint256 maturityTime, bytes memory extraData) public {
        // Require only sweeping after maturity
        if (maturityTime > block.timestamp) revert IHyperdrive.BondNotMatured();
        // Load the balance of this contract
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );
        uint256 balance = hyperdrive.balanceOf(assetId, address(this));
        // Only close if we have something to close
        if (balance != 0) {
            // Since we're closing the entire position, the output can be ignored.
            hyperdrive.closeLong(
                maturityTime,
                balance,
                balance,
                IHyperdrive.Options({
                    destination: address(this),
                    asBase: true,
                    extraData: extraData
                })
            );
        }
    }

    /// @notice Burns a caller's erc20 and transfers the result from the contract's token balance.
    /// @param amount The amount of erc20 wrapper to burn.
    function redeem(uint256 amount) public {
        // Simply burn from the user and send funds from the contract balance
        _burn(msg.sender, amount);

        // Transfer the released funds to the user
        SafeTransferLib.safeTransfer(ERC20(address(token)), msg.sender, amount);
    }

    /// @notice Calls both force close and redeem to enable easy liquidation of a user account
    /// @param  maturityTimes Maturity times which the caller would like to sweep before redeeming
    /// @param amount The amount of erc20 wrapper to burn.
    /// @param extraDatas Extra data to pass to the yield source.
    function sweepAndRedeem(
        uint256[] calldata maturityTimes,
        uint256 amount,
        bytes[] memory extraDatas
    ) external {
        if (maturityTimes.length != extraDatas.length) {
            revert IHyperdrive.InputLengthMismatch();
        }

        // Cycle through each maturity and sweep.
        for (uint256 i = 0; i < maturityTimes.length; ) {
            sweep(maturityTimes[i], extraDatas[i]);
            unchecked {
                ++i;
            }
        }
        redeem(amount);
    }
}
