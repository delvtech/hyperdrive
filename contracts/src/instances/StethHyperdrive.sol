// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { Hyperdrive } from "../Hyperdrive.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { Errors } from "../libraries/Errors.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";

// FIXME: Add to interfaces.
interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 _amount) external;
}

// FIXME: Add to interfaces.
interface ILido {
    function submit(address _referral) external payable returns (uint256);

    function getTotalPooledEther() external view returns (uint256);

    function getTotalShares() external view returns (uint256);
}

// FIXME:
//
// - [ ] Add NatSpec comments.
// - [ ] Add a `_deposit` function. This should use Lido's `submit` function.
//       We will use WETH as the base token for the initial version. In the PR
//       write-up, I should discuss the pros and cons of this decision.
// - [ ] Add a `_withdraw` function. This shouldn't have the option of
//       withdrawing WETH and should just return stETH.
// - [ ] Add a `_pricePerShare` function. Lido has this functionality natively,
//       so we'll just need to make use of their machinery.
// - [ ] Should our users call deposit and/or buffered deposit? This would be
//       go from stETH's perspective.
// - [ ] Gas golf price per share. It might be cheaper to use `sharesOf` since
//       every function call will need to get the amount of shares to use for
//       the contract, so that state will be hot. Having said this, if we need
//       to get the total shares and pooled ether to calculate the amount of
//       ETH controlled by this account, then we shouldn't bother.
contract StethHyperdrive is Hyperdrive {
    using FixedPointMath for uint256;

    /// @dev The Lido contract.
    ILido internal immutable lido;

    /// @dev The stETH token.
    IERC20 internal immutable stETH;

    /// @dev The WETH token.
    IWETH internal immutable weth;

    // FIXME: NatSpec.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        ILido _lido,
        IERC20 _stETH,
        IWETH _weth
    ) Hyperdrive(_config, _dataProvider, _linkerCodeHash, _linkerFactory) {
        lido = _lido;
        stETH = _stETH;
        weth = _weth;
    }

    // FIXME: NatSpec.
    function _deposit(
        uint256 _amount,
        bool _asUnderlying
    ) internal override returns (uint256 shares, uint256 sharePrice) {
        if (_asUnderlying) {
            // Transfer stETH into the contract.
            bool success = stETH.transferFrom(
                msg.sender,
                address(this),
                _amount
            );
            if (!success) {
                revert Errors.TransferFailed();
            }

            // FIXME: Comment this.
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

            // FIXME: Should the referrer be the destination? Something else?
            //
            // Submit the provided ether to Lido to be deposited.
            shares = lido.submit{ value: _amount }(address(0));

            // FIXME: Will this deviate from the result from Lido? We should
            //        test it.
            //
            // Calculate the share price.
            sharePrice = shares.divDown(_amount);
        }

        return (shares, sharePrice);
    }

    // FIXME: NatSpec.
    function _withdraw(
        uint256 _shares,
        address _destination,
        bool _asUnderlying
    ) internal override returns (uint256 amountWithdrawn, uint256 shares) {
        if (_asUnderlying) {
            // FIXME: This should definitely be accepted. Transfer the stETH
            // shares. We need to get the amount of stETH that this relates to.
        } else {
            // FIXME: This may or may not need to be accepted. Is it possible
            // to instantly withdraw stETH or is this not even a part of their
            // interface?
        }
    }

    // FIXME: NatSpec.
    function _pricePerShare() internal view override returns (uint256 price) {
        // FIXME: It may be good to explain this.
        return lido.getTotalPooledEther().divDown(lido.getTotalShares());
    }
}
