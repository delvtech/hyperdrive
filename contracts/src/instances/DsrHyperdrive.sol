// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { Hyperdrive } from "../Hyperdrive.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { Errors } from "../libraries/Errors.sol";
import { Pot, DsrManager } from "../interfaces/IMaker.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

contract DsrHyperdrive is Hyperdrive {
    using FixedPointMath for uint256;

    // @notice The shares created by this pool, starts at 1 to one with
    //         deposits and increases
    uint256 internal totalShares;

    // @notice The pool management contract
    DsrManager internal immutable dsrManager;

    // @notice The core Maker accounting module for the Dai Savings Rate
    Pot internal immutable pot;

    // @notice Maker constant
    uint256 internal constant RAY = 1e27;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _dataProvider The address of the data provider.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The factory which is used to deploy the ERC20
    ///        linker contracts.
    /// @param _dsrManager The "dai savings rate" manager contract
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        DsrManager _dsrManager
    ) Hyperdrive(_config, _dataProvider, _linkerCodeHash, _linkerFactory) {
        // Ensure that the Hyperdrive pool was configured properly.
        if (address(_config.baseToken) != address(_dsrManager.dai())) {
            revert Errors.InvalidBaseToken();
        }
        if (_config.initialSharePrice != FixedPointMath.ONE_18) {
            revert Errors.InvalidInitialSharePrice();
        }

        dsrManager = _dsrManager;
        pot = Pot(dsrManager.pot());
        _baseToken.approve(address(dsrManager), type(uint256).max);
    }

    /// @notice Transfers base or shares from the user and commits it to the yield source.
    /// @param amount The amount of base tokens to deposit.
    /// @param asUnderlying The DSR yield source only supports depositing the
    ///        underlying token. If this is false, the transaction will revert.
    /// @return sharesMinted The shares this deposit creates.
    /// @return sharePrice The share price at time of deposit.
    function _deposit(
        uint256 amount,
        bool asUnderlying
    ) internal override returns (uint256 sharesMinted, uint256 sharePrice) {
        if (!asUnderlying) {
            revert Errors.UnsupportedToken();
        }

        // Transfer the base token from the user to this contract
        bool success = _baseToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) {
            revert Errors.TransferFailed();
        }

        // Get total invested balance of pool, deposits + interest
        uint256 totalBase = dsrManager.daiBalance(address(this));

        // Deposit the base tokens into the dsr
        dsrManager.join(address(this), amount);

        // Do share calculations
        if (totalShares == 0) {
            totalShares = amount;
            // Initial deposits are always 1:1
            return (amount, FixedPointMath.ONE_18);
        } else {
            uint256 newShares = totalShares.mulDivDown(amount, totalBase);
            totalShares += newShares;
            return (newShares, amount.divDown(newShares));
        }
    }

    /// @notice Withdraws shares from the yield source and sends the resulting tokens to the destination
    /// @param shares The shares to withdraw from the yield source
    /// @param destination The address which is where to send the resulting tokens
    /// @return amountWithdrawn the amount of 'token' produced by this withdraw
    /// @return sharePrice The share price on withdraw.
    function _withdraw(
        uint256 shares,
        address destination,
        bool asUnderlying
    ) internal override returns (uint256 amountWithdrawn, uint256 sharePrice) {
        if (!asUnderlying) {
            revert Errors.UnsupportedToken();
        }
        // Load the balance of this contract - this calls drip internally so
        // this is real deposits + interest accrued at point in time
        uint256 totalBase = dsrManager.daiBalance(address(this));

        // The withdraw is the percent of shares the user has times the total assets
        amountWithdrawn = totalBase.mulDivDown(shares, totalShares);

        // Remove shares from the total supply
        totalShares -= shares;

        // Withdraw pro-rata share of underlying to user
        dsrManager.exit(destination, amountWithdrawn);

        return (amountWithdrawn, amountWithdrawn.divDown(shares));
    }

    /// @notice Loads the share price from the yield source.
    /// @return sharePrice The current share price.
    function _pricePerShare()
        internal
        view
        override
        returns (uint256 sharePrice)
    {
        uint256 pie = dsrManager.pieOf(address(this));
        uint256 totalBase = pie.mulDivDown(chi(), RAY);
        if (totalShares != 0) {
            return totalBase.divDown(totalShares);
        }
        return 0;
    }

    /// @notice Gets the current up to date value of the rate accumulator
    /// @dev The Maker protocol uses a tick based accounting mechanic to
    ///      accumulate interest in a single variable called the rate
    ///      accumulator or more commonly "chi".
    ///      This is re-calibrated on any interaction with the maker protocol by
    ///      a function pot.drip(). The rationale for not using this is that it
    ///      is not a view function and so the purpose of this function is to
    ///      get the real chi value without interacting with the core maker
    ///      system and expensively mutating state.
    /// return chi The rate accumulator
    function chi() internal view returns (uint256) {
        // timestamp when drip was last called
        uint256 rho = pot.rho();
        // Rate accumulator as of last drip
        uint256 _chi = pot.chi();
        // Annualized interest rate
        uint256 dsr = pot.dsr();
        // Calibrates the rate accumulator to current time
        return
            (block.timestamp > rho)
                ? _rpow(dsr, block.timestamp - rho, RAY).mulDivDown(_chi, RAY)
                : _chi;
    }

    /// @notice Taken from https://github.com/makerdao/dss/blob/master/src/pot.sol#L85
    /// @return z
    function _rpow(uint x, uint n, uint base) internal pure returns (uint z) {
        assembly ("memory-safe") {
            switch x
            case 0 {
                switch n
                case 0 {
                    z := base
                }
                default {
                    z := 0
                }
            }
            default {
                switch mod(n, 2)
                case 0 {
                    z := base
                }
                default {
                    z := x
                }
                let half := div(base, 2) // for rounding.
                for {
                    n := div(n, 2)
                } n {
                    n := div(n, 2)
                } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) {
                        revert(0, 0)
                    }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) {
                        revert(0, 0)
                    }
                    x := div(xxRound, base)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) {
                            revert(0, 0)
                        }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) {
                            revert(0, 0)
                        }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }
}
