// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "./Hyperdrive.sol";
import "./libraries/FixedPointMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface Pool {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(address asset, uint256 amount, address to) external;
}

contract AaveYieldSource is Hyperdrive {
    using FixedPointMath for uint256;

    // The aave deployment details, the a token for this asset and the aave pool
    IERC20 public immutable aToken;
    Pool public immutable pool;
    // The shares created by this pool, starts at 1 to one with deposits and increases
    uint256 public totalShares;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The factory which is used to deploy the ERC20
    ///        linker contracts.
    /// @param _baseToken The base token contract.
    /// @param _positionDuration The time in seconds that elapses before bonds
    ///        can be redeemed one-to-one for base.
    /// @param _timeStretch The time stretch of the pool.
    constructor(
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20 _baseToken,
        uint256 _positionDuration,
        uint256 _timeStretch,
        IERC20 _aToken,
        Pool _pool
    )
        Hyperdrive(
            _linkerCodeHash,
            _linkerFactory,
            _baseToken,
            _positionDuration,
            _timeStretch,
            FixedPointMath.ONE_18
        )
    {
        aToken = _aToken;
        pool = _pool;
    }

    ///@notice Transfers amount of 'token' from the user and commits it to the yield source.
    ///@param amount The amount of token to transfer
    ///@return sharesMinted The shares this deposit creates
    ///@return pricePerShare The price per share at time of deposit
    function deposit(
        uint256 amount
    ) internal override returns (uint256 sharesMinted, uint256 pricePerShare) {
        // Transfer from user
        bool success = baseToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) {
            revert Errors.TransferFailed();
        }

        // Load the balance of this pool
        uint256 assets = aToken.balanceOf(address(this));
        // Supply for the user
        pool.supply(address(baseToken), amount, address(this), 0);

        // Do share calculations
        if (totalShares == 0) {
            totalShares = amount;
            return (amount, assets.divDown(amount));
        } else {
            uint256 newShares = totalShares.mulDown(amount.divDown(assets));
            totalShares += newShares;
            return (newShares, amount.divDown(newShares));
        }
    }

    ///@notice Withdraws shares from the yield source and sends the resulting tokens to the destination
    ///@param shares The shares to withdraw from the yieldsource
    ///@param destination The address which is where to send the resulting tokens
    ///@return amountWithdrawn the amount of 'token' produced by this withdraw
    ///@return pricePerShare The price per share on withdraw.
    function withdraw(
        uint256 shares,
        address destination
    )
        internal
        override
        returns (uint256 amountWithdrawn, uint256 pricePerShare)
    {
        // Load the balance of this contract
        uint256 assets = aToken.balanceOf(address(this));
        // The withdraw is the percent of shares the user has times the total assets
        uint256 withdrawValue = assets.mulDown(shares.divDown(totalShares));
        // Now we call aave to fulfill this for the user
        pool.withdraw(address(baseToken), withdrawValue, destination);
        // Return the amount and implied share price
        return (withdrawValue, shares.divDown(withdrawValue));
    }

    ///@notice Loads the price per share from the yield source
    ///@return pricePerShare The current price per share
    function _pricePerShare()
        internal
        view
        override
        returns (uint256 pricePerShare)
    {
        // Load the balance of this contract
        uint256 assets = aToken.balanceOf(address(this));
        // Price per share is assets divided by shares
        return (assets.divDown(totalShares));
    }
}
