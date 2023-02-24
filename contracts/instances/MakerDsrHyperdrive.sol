// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Hyperdrive } from "../Hyperdrive.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { Errors } from "../libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface Pot {
    function chi() external view returns (uint256);

    function rho() external view returns (uint256);

    function dsr() external view returns (uint256);
}

interface DsrManager {
    function dai() external view returns (address);

    function pot() external view returns (address);

    function pieOf(address) external view returns (uint256);

    function daiBalance(address) external returns (uint256);

    function join(address, uint256) external;

    function exit(address, uint256) external;

    function exitAll(address) external;
}

contract MakerDsrHyperdrive is Hyperdrive {
    using FixedPointMath for uint256;

    // @notice The shares created by this pool, starts at 1 to one with
    //         deposits and increases
    uint256 public totalShares;

    // @notice The pool management contract
    DsrManager public dsrManager;
    // @notice The core Maker accounting module for the Dai Savings Rate
    Pot public pot;
    // @notice Maker constant
    uint256 public constant RAY = 1e27;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The factory which is used to deploy the ERC20
    ///        linker contracts.
    /// @param _checkpointsPerTerm The number of checkpoints that elapses before
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
            IERC20(address(_dsrManager.dai())), // baseToken will always be DAI
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
        baseToken.approve(address(dsrManager), type(uint256).max);
    }

    /// @notice Transfers base or shares from the user and commits it to the yield source.
    /// @param amount The amount of base tokens to deposit.
    /// @param asUnderlying If true the yield source will transfer underlying tokens
    ///                     if false it will transfer the yielding asset directly
    /// @return sharesMinted The shares this deposit creates.
    /// @return sharePrice The share price at time of deposit.
    function _deposit(
        uint256 amount,
        bool asUnderlying
    ) internal override returns (uint256 sharesMinted, uint256 sharePrice) {
        if (!asUnderlying) {
            revert Errors.Unsupported();
        }

        // Transfer the base token from the user to this contract
        bool success = baseToken.transferFrom(
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
            uint256 newShares = totalShares.mulDown(amount.divDown(totalBase));
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
            revert Errors.Unsupported();
        }
        // Load the balance of this contract - this calls drip internally so
        // this is real deposits + interest accrued at point in time
        uint256 totalBase = dsrManager.daiBalance(address(this));

        // The withdraw is the percent of shares the user has times the total assets
        amountWithdrawn = totalBase.mulDown(shares.divDown(totalShares));

        // Remove shares from the total supply
        totalShares -= shares;

        // If all shares are removed from the pool we exit all underlying,
        // otherwise the users portion worth of dai is exited.
        if (totalShares == 0) {
            // Use differential amounts for rounding - TODO Is this needed?
            uint256 preExitBalance = baseToken.balanceOf(address(destination));
            dsrManager.exitAll(destination);
            amountWithdrawn =
                baseToken.balanceOf(address(destination)) -
                preExitBalance;
        } else {
            dsrManager.exit(destination, amountWithdrawn);
        }
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
        // The normalized DAI amount owned by this contract
        uint256 pie = dsrManager.pieOf(address(this));
        // Load the balance of this contract
        uint256 totalBase = pie.mulDivDown(chi(), RAY);
        // The share price is assets divided by shares
        return (totalBase.divDown(totalShares));
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
    function chi() public view returns (uint256) {
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
        assembly {
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
