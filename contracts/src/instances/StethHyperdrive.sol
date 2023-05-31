// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Hyperdrive } from "../Hyperdrive.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { ILido } from "../interfaces/ILido.sol";
import { IWETH } from "../interfaces/IWETH.sol";
import { Errors } from "../libraries/Errors.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";

// FIXME:
//
// - [x] Add NatSpec comments.
// - [x] Add a `_deposit` function. This should use Lido's `submit` function.
//       We will use WETH as the base token for the initial version. In the PR
//       write-up, I should discuss the pros and cons of this decision.
// - [x] Add a `_withdraw` function. This shouldn't have the option of
//       withdrawing WETH and should just return stETH.
// - [x] Add a `_pricePerShare` function. Lido has this functionality natively,
//       so we'll just need to make use of their machinery.
// - [x] This integration won't support the referral address. We should make a
//       note of this and double check during reviews that we don't want to
//       support this.
// - [ ] Should our users call deposit and/or buffered deposit? This would be
//       go from stETH's perspective.
//
/// @author DELV
/// @title StethHyperdrive
/// @notice An instance of Hyperdrive that utilizes Lido's staked ether (stETH)
///         as a yield source.
/// @dev Lido has it's own notion of shares to account for the accrual of
///      interest on the ether pooled in the Lido protocol. Instead of
///      maintaining a balance of shares, this integration can simply use Lido
///      shares directly.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StethHyperdrive is Hyperdrive {
    using FixedPointMath for uint256;

    // FIXME: I don't think there is a need to separate `lido` and `stETH`
    //        since they live at the same address.
    //
    /// @dev The Lido contract.
    ILido internal immutable lido;

    /// @dev The WETH token.
    IWETH internal immutable weth;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _dataProvider The address of the data provider.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The factory which is used to deploy the ERC20
    ///        linker contracts.
    /// @param _lido The Lido contract. This is the stETH token.
    /// @param _weth The WETH token.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        ILido _lido,
        IWETH _weth
    ) Hyperdrive(_config, _dataProvider, _linkerCodeHash, _linkerFactory) {
        lido = _lido;
        weth = _weth;
    }

    /// @dev Accepts a transfer from the user in base or the yield source token.
    /// @param _amount The amount to deposit.
    /// @param _asUnderlying A flag indicating that the deposit is paid in stETH
    ///        if true and in WETH if false.
    /// @return shares The amount of shares that represents the amount deposited.
    /// @return sharePrice The current share price.
    function _deposit(
        uint256 _amount,
        bool _asUnderlying
    ) internal override returns (uint256 shares, uint256 sharePrice) {
        if (_asUnderlying) {
            // Transfer stETH into the contract.
            bool success = lido.transferFrom(
                msg.sender,
                address(this),
                _amount
            );
            if (!success) {
                revert Errors.TransferFailed();
            }

            // Calculate the share price and the amount of shares deposited.
            sharePrice = _pricePerShare();
            shares = _amount.divDown(sharePrice);
        } else {
            // Transfer WETH into the contract and unwrap it.
            bool success = weth.transferFrom(
                msg.sender,
                address(this),
                _amount
            );
            if (!success) {
                revert Errors.TransferFailed();
            }
            weth.withdraw(_amount);

            // Submit the provided ether to Lido to be deposited. The governance
            // address is passed as the referral address; however, users can
            // specify whatever referrer they'd like by depositing stETH instead
            // of WETH.
            shares = lido.submit{ value: _amount }(_governance);

            // Calculate the share price.
            sharePrice = shares.divDown(_amount);
        }

        return (shares, sharePrice);
    }

    /// @dev Withdraws stETH to the destination address.
    /// @param _shares The amount of shares to withdraw.
    /// @param _destination The recipient of the withdrawal.
    /// @param _asUnderlying This must be false since stETH withdrawals aren't
    ///        processed instantaneously. Users that want to withdraw can manage
    ///        their withdrawal separately.
    /// @return amountWithdrawn The amount of stETH withdrawn.
    /// @return sharePrice The current share price.
    function _withdraw(
        uint256 _shares,
        address _destination,
        bool _asUnderlying
    ) internal override returns (uint256 amountWithdrawn, uint256 sharePrice) {
        if (_asUnderlying) {
            revert Errors.UnsupportedToken();
        }

        // Transfer stETH to the destination.
        amountWithdrawn = lido.transferShares(_destination, _shares);

        // Calculate the share price.
        sharePrice = amountWithdrawn.divDown(_shares);

        return (amountWithdrawn, sharePrice);
    }

    /// @dev Returns the current share price. We simply use Lido's share price.
    /// @return price The current share price.
    function _pricePerShare() internal view override returns (uint256 price) {
        return lido.getTotalPooledEther().divDown(lido.getTotalShares());
    }
}
