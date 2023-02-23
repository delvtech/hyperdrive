// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Hyperdrive } from "../Hyperdrive.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { Errors } from "../libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface Pot {
    function chi() external view returns (uint256);
}

interface DsrManager {
    function pot() external view returns (address);

    function pieOf(address) external view returns (uint256);

    function daiBalance(address) external returns (uint256);

    function join(address, uint256) external;

    function exit(address, uint256) external;
}

contract MakerDsrHyperdrive is Hyperdrive {
    using FixedPointMath for uint256;

    // The shares created by this pool, starts at 1 to one with deposits and increases
    uint256 public totalShares;
    // The pool management contract
    DsrManager public dsrManager;
    // The core Maker accounting module for the Dai Savings Rate
    Pot public pot;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The factory which is used to deploy the ERC20
    ///        linker contracts.
    /// @param _baseToken The base token contract.
    /// @param _checkpointsPerTerm The number of checkpoints that elaspes before
    ///        bonds can be redeemed one-to-one for base.
    /// @param _checkpointDuration The time in seconds between share price
    ///        checkpoints. Position duration must be a multiple of checkpoint
    ///        duration.
    /// @param _timeStretch The time stretch of the pool.
    /// @param _curveFee The fee parameter for the curve portion of the hyperdrive trade equation.
    /// @param _flatFee The fee parameter for the flat portion of the hyperdrive trade equation.
    /// @param _dsrManager The "dai savings rate" manager contract
    constructor(
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20 _baseToken,
        uint256 _checkpointsPerTerm,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        uint256 _curveFee,
        uint256 _flatFee,
        DsrManager _dsrManager
    )
        Hyperdrive(
            _linkerCodeHash,
            _linkerFactory,
            _baseToken,
            FixedPointMath.ONE_18,
            _checkpointsPerTerm,
            _checkpointDuration,
            _timeStretch,
            _curveFee,
            _flatFee
        )
    {
        dsrManager = _dsrManager;
        pot = Pot(dsrManager.pot());
    }

    ///@notice Transfers amount of 'token' from the user and commits it to the yield source.
    ///@param amount The amount of token to transfer
    ///@return sharesMinted The shares this deposit creates
    ///@return sharePrice The share price at time of deposit
    function _deposit(
        uint256 amount,
        bool
    ) internal override returns (uint256 sharesMinted, uint256 sharePrice) {
        // Transfer from user
        bool success = baseToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) {
            revert Errors.TransferFailed();
        }

        // Get total base, deposits + interest
        uint256 totalBase = dsrManager.daiBalance(address(this));
        // Deposit base into the dsr
        dsrManager.join(address(this), amount);

        // Do share calculations
        if (totalShares == 0) {
            totalShares = amount;
            return (amount, totalBase.divDown(amount));
        } else {
            uint256 newShares = totalShares.mulDown(amount.divDown(totalBase));
            totalShares += newShares;
            return (newShares, amount.divDown(newShares));
        }
    }

    ///@notice Withdraws shares from the yield source and sends the resulting tokens to the destination
    ///@param shares The shares to withdraw from the yield source
    ///@param destination The address which is where to send the resulting tokens
    ///@return amountWithdrawn the amount of 'token' produced by this withdraw
    ///@return sharePrice The share price on withdraw.
    function _withdraw(
        uint256 shares,
        address destination,
        bool
    ) internal override returns (uint256 amountWithdrawn, uint256 sharePrice) {
        // Load the balance of this contract
        uint256 totalBase = dsrManager.daiBalance(address(this));
        // The withdraw is the percent of shares the user has times the total assets
        uint256 withdrawValue = totalBase.mulDown(shares.divDown(totalShares));
        // Now we call aave to fulfill this for the user
        dsrManager.exit(destination, withdrawValue);
        // Return the amount and implied share price
        return (withdrawValue, shares.divDown(withdrawValue));
    }

    ///@notice Loads the share price from the yield source.
    ///@return sharePrice The current share price.
    function _pricePerShare()
        internal
        view
        override
        returns (uint256 sharePrice)
    {
        // The interest rate accumulator
        uint256 chi = pot.chi();
        // The normalized DAI amount owned by this contract
        uint256 pie = dsrManager.pieOf(address(this));
        // Load the balance of this contract
        uint256 totalBase = pie.mulDown(chi);
        // The share price is assets divided by shares
        return (totalBase.divDown(totalShares));
    }
}
