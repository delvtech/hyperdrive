// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ElementError } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
import { IERC1155Mintable } from "contracts/interfaces/IERC1155Mintable.sol";

contract Hyperdrive is ERC20 {
    /// Tokens ///

    IERC20 public immutable baseToken;
    IERC1155Mintable public immutable longToken;
    IERC1155Mintable public immutable shortToken;

    /// Time ///

    uint256 public immutable termLength;
    uint256 public immutable timeStretch;

    /// Market state ///

    // TODO: These should both be uint128 and share a slot.
    uint256 public shareReserves;
    uint256 public bondReserves;

    uint256 public baseBuffer;
    uint256 public bondBuffer;

    uint256 public sharePrice;
    uint256 public immutable initialSharePrice;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _baseToken The base token contract.
    /// @param _longToken The long token contract.
    /// @param _shortToken The short token contract.
    /// @param _termLength The length of the terms supported by this Hyperdrive in seconds.
    /// @param _timeStretch The time stretch of the pool.
    constructor(
        IERC20 _baseToken,
        IERC1155Mintable _longToken,
        IERC1155Mintable _shortToken,
        uint256 _termLength,
        uint256 _timeStretch
    ) ERC20("Hyperdrive LP", "hLP") {
        // Initialize the token addresses.
        baseToken = _baseToken;
        longToken = _longToken;
        shortToken = _shortToken;

        // Initialize the time configurations.
        termLength = _termLength;
        timeStretch = _timeStretch;

        // TODO: This isn't correct. This will need to be updated when asset
        // delegation is implemented.
        initialSharePrice = FixedPointMath.ONE_18;
        sharePrice = FixedPointMath.ONE_18;
    }

    /// @notice Allows the first LP to initialize the market with a target APR.
    /// @param _contribution The amount of base asset to contribute.
    /// @param _apr The target APR.
    function initialize(uint256 _contribution, uint256 _apr) external {
        // Ensure that the pool hasn't been initialized yet.
        if (shareReserves > 0) {
            revert ElementError.PoolAlreadyInitialized();
        }

        // Pull the contribution into the contract.
        bool success = baseToken.transferFrom(
            msg.sender,
            address(this),
            _contribution
        );
        if (!success) {
            revert ElementError.TransferFailed();
        }

        // Update the reserves.
        shareReserves = _contribution;
        bondReserves = HyperdriveMath.calculateBondReserves(
            _contribution,
            initialSharePrice,
            sharePrice,
            _apr,
            termLength,
            timeStretch
        );

        // Mint LP tokens for the initializer.
        _mint(msg.sender, _contribution);
    }

    /// @notice Opens a long position that whose with a term length starting in
    ///         the current block.
    /// @param _amount The amount of base to use when trading.
    function openLong(uint256 _amount) external {
        if (_amount == 0) {
            revert ElementError.ZeroAmount();
        }

        // Take custody of the base that is being traded into the contract.
        bool success = baseToken.transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        if (!success) {
            revert ElementError.TransferFailed();
        }

        // Calculate the pool and user deltas using the trading function.
        (
            uint256 poolBaseDelta,
            uint256 poolBondDelta,
            uint256 bondsPurchased
        ) = HyperdriveMath.calculateOutGivenIn(
                shareReserves,
                bondReserves,
                totalSupply(),
                _amount,
                FixedPointMath.ONE_18,
                timeStretch,
                sharePrice,
                initialSharePrice,
                true
            );

        // Apply the trading deltas to the reserves.
        shareReserves += poolBaseDelta;
        bondReserves -= poolBondDelta;

        // Increase the base buffer by the number of bonds purchased to ensure
        // that the pool can fully redeem the newly purchased bonds.
        baseBuffer += bondsPurchased;

        // TODO: We should fuzz test this and other trading functions to ensure
        // that the APR never goes below zero. If it does, we may need to
        // enforce additional invariants.
        //
        // Ensure that the base reserves are greater than the base buffer and
        // that the bond reserves are greater than the bond buffer.
        if (sharePrice * shareReserves >= baseBuffer) {
            revert ElementError.BaseBufferExceedsShareReserves();
        }
        if (bondReserves >= bondBuffer) {
            revert ElementError.BondBufferExceedsBondReserves();
        }

        // Mint the bonds to the trader.
        longToken.mint(
            msg.sender,
            block.timestamp,
            bondsPurchased,
            new bytes(0)
        );
    }
}
