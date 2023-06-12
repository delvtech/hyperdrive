// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "../interfaces/IERC20.sol";
import { HyperdriveDataProvider } from "../HyperdriveDataProvider.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { Errors } from "../libraries/Errors.sol";
import { Pot, DsrManager } from "../interfaces/IMaker.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { MultiTokenDataProvider } from "../token/MultiTokenDataProvider.sol";

contract DsrHyperdriveDataProvider is
    MultiTokenDataProvider,
    HyperdriveDataProvider
{
    using FixedPointMath for uint256;

    // @notice The shares created by this pool, starts at 1 to one with
    //         deposits and increases
    uint256 internal _totalShares;

    // @notice The pool management contract
    DsrManager internal immutable _dsrManager;

    // @notice The core Maker accounting module for the Dai Savings Rate
    Pot internal immutable _pot;

    // @notice Maker constant
    uint256 internal constant RAY = 1e27;

    /// @notice Initializes the data provider.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _linkerCodeHash_ The hash of the erc20 linker contract deploy code
    /// @param _factory_ The factory which is used to deploy the linking contracts
    /// @param _dsrManager_ The "dai savings rate" manager contract
    constructor(
        IHyperdrive.PoolConfig memory _config,
        bytes32 _linkerCodeHash_,
        address _factory_,
        DsrManager _dsrManager_
    )
        HyperdriveDataProvider(_config)
        MultiTokenDataProvider(_linkerCodeHash_, _factory_)
    {
        _dsrManager = _dsrManager_;
        _pot = Pot(_dsrManager_.pot());
    }

    /// Getters ///

    /// @notice Gets the DSRManager.
    /// @return The DSRManager.
    function dsrManager() external view returns (DsrManager) {
        _revert(abi.encode(_dsrManager));
    }

    /// @notice The accounting module for the Dai Savings Rate.
    /// @return Maker's Pot contract.
    function pot() external view returns (Pot) {
        _revert(abi.encode(_pot));
    }

    /// @notice Gets the total number of shares in existence.
    /// @return The total number of shares.
    function totalShares() external view returns (uint256) {
        _revert(abi.encode(_totalShares));
    }

    /// Yield Source ///

    /// @notice Loads the share price from the yield source.
    /// @return sharePrice The current share price.
    function _pricePerShare()
        internal
        view
        override
        returns (uint256 sharePrice)
    {
        // The normalized DAI amount owned by this contract
        uint256 pie = _dsrManager.pieOf(address(this));
        // Load the balance of this contract
        uint256 totalBase = pie.mulDivDown(chi(), RAY);
        // The share price is assets divided by shares
        return (totalBase.divDown(_totalShares));
    }

    /// TODO Is this actually worthwhile versus using drip?
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
        uint256 rho = _pot.rho();
        // Rate accumulator as of last drip
        uint256 _chi = _pot.chi();
        // Annualized interest rate
        uint256 dsr = _pot.dsr();
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
