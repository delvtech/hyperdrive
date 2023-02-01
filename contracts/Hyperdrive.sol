// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ElementError } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
import { IERC1155Mintable } from "contracts/interfaces/IERC1155Mintable.sol";

contract Hyperdrive is ERC20 {
    using FixedPointMath for uint256;

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

    /// Long ///

    /// @notice Opens a long position.
    /// @param _baseAmount The amount of base to use when trading.
    function openLong(uint256 _baseAmount) external {
        if (_baseAmount == 0) {
            revert ElementError.ZeroAmount();
        }

        // Take custody of the base that is being traded into the contract.
        bool success = baseToken.transferFrom(
            msg.sender,
            address(this),
            _baseAmount
        );
        if (!success) {
            revert ElementError.TransferFailed();
        }

        // Calculate the pool and user deltas using the trading function.
        uint256 shareAmount = _baseAmount.divDown(sharePrice);
        (, uint256 poolBondDelta, uint256 bondProceeds) = HyperdriveMath
            .calculateOutGivenIn(
                shareReserves,
                bondReserves,
                totalSupply(),
                shareAmount,
                FixedPointMath.ONE_18,
                timeStretch,
                sharePrice,
                initialSharePrice,
                true
            );

        // Apply the trading deltas to the reserves and increase the base buffer
        // by the number of bonds purchased to ensure that the pool can fully
        // redeem the newly purchased bonds.
        shareReserves += shareAmount;
        bondReserves -= poolBondDelta;
        baseBuffer += bondProceeds;

        // TODO: We should fuzz test this and other trading functions to ensure
        // that the APR never goes below zero. If it does, we may need to
        // enforce additional invariants.
        //
        // Since the base buffer may have increased relative to the base
        // reserves and the bond reserves decreased, we must ensure that the
        // base reserves are greater than the base buffer and that the bond
        // reserves are greater than the bond buffer.
        if (sharePrice * shareReserves >= baseBuffer) {
            revert ElementError.BaseBufferExceedsShareReserves();
        }
        if (bondReserves >= bondBuffer) {
            revert ElementError.BondBufferExceedsBondReserves();
        }

        // Mint the bonds to the trader with an ID of the maturity time.
        longToken.mint(
            msg.sender,
            block.timestamp + termLength,
            bondProceeds,
            new bytes(0)
        );
    }

    /// @notice Closes a long position with a specified maturity time.
    /// @param _maturityTime The maturity time of the longs to close.
    /// @param _bondAmount The amount of longs to close.
    function closeLong(uint256 _maturityTime, uint256 _bondAmount) external {
        if (_bondAmount == 0) {
            revert ElementError.ZeroAmount();
        }

        // Burn the longs that are being closed.
        longToken.burn(msg.sender, _maturityTime, _bondAmount);

        // Calculate the pool and user deltas using the trading function.
        uint256 timeRemaining = block.timestamp < _maturityTime
            ? (_maturityTime - block.timestamp) * FixedPointMath.ONE_18
            : 0;
        (
            uint256 poolShareDelta,
            uint256 poolBondDelta,
            uint256 shareProceeds
        ) = HyperdriveMath.calculateOutGivenIn(
                shareReserves,
                bondReserves,
                totalSupply(),
                _bondAmount,
                timeRemaining,
                timeStretch,
                sharePrice,
                initialSharePrice,
                false
            );

        // Apply the trading deltas to the reserves and decrease the base buffer
        // by the amount of bonds sold. Since the difference between the base
        // reserves and the base buffer stays the same or gets larger and the
        // difference between the bond reserves and the bond buffer increases,
        // we don't need to check that the reserves are larger than the buffers.
        shareReserves -= poolShareDelta;
        bondReserves += poolBondDelta;
        baseBuffer -= _bondAmount;

        // Transfer the base returned to the trader.
        bool success = baseToken.transfer(
            msg.sender,
            shareProceeds.mulDown(sharePrice)
        );
        if (!success) {
            revert ElementError.TransferFailed();
        }
    }

    /// Short ///

    /// @notice Opens a short position.
    /// @param _bondAmount The amount of bonds to short.
    function openShort(uint256 _bondAmount) external {
        if (_bondAmount == 0) {
            revert ElementError.ZeroAmount();
        }

        // Calculate the pool and user deltas using the trading function.
        (uint256 poolShareDelta, , uint256 shareProceeds) = HyperdriveMath
            .calculateOutGivenIn(
                shareReserves,
                bondReserves,
                totalSupply(),
                _bondAmount,
                FixedPointMath.ONE_18,
                timeStretch,
                sharePrice,
                initialSharePrice,
                false
            );

        // Take custody of the maximum amount the trader can lose on the short.
        uint256 baseProceeds = shareProceeds.mulDown(sharePrice);
        bool success = baseToken.transferFrom(
            msg.sender,
            address(this),
            _bondAmount - baseProceeds
        );
        if (!success) {
            revert ElementError.TransferFailed();
        }

        // Apply the trading deltas to the reserves and increase the bond buffer
        // by the amount of bonds that were shorted.
        shareReserves -= poolShareDelta;
        bondReserves += _bondAmount;
        bondBuffer += _bondAmount;

        // The bond buffer is increased by the same amount as the bond buffer,
        // so there is no need to check that the bond reserves is greater than
        // or equal to the bond buffer. Since the share reserves are reduced,
        // we need to verify that the base reserves are greater than or equal
        // to the base buffer.
        if (sharePrice * shareReserves >= baseBuffer) {
            revert ElementError.BaseBufferExceedsShareReserves();
        }

        // Mint the short tokens to the trader.
        shortToken.mint(
            msg.sender,
            block.timestamp + termLength,
            _bondAmount,
            new bytes(0)
        );
    }

    // TODO: Make sure that the correct amount of variable interest is given to
    // the shorter.
    //
    /// @notice Closes a short position with a specified maturity time.
    /// @param _maturityTime The maturity time of the shorts to close.
    /// @param _bondAmount The amount of shorts to close.
    function closeShort(uint256 _maturityTime, uint256 _bondAmount) external {
        if (_bondAmount == 0) {
            revert ElementError.ZeroAmount();
        }

        // Burn the shorts that are being closed.
        shortToken.burn(msg.sender, _maturityTime, _bondAmount);

        // Calculate the pool and user deltas using the trading function.
        uint256 timeRemaining = block.timestamp < _maturityTime
            ? (_maturityTime - block.timestamp) * FixedPointMath.ONE_18
            : 0;
        (uint256 poolShareDelta, uint256 poolBondDelta, uint256 shareObligation) = HyperdriveMath
            .calculateInGivenOut(
                shareReserves,
                bondReserves,
                totalSupply(),
                _bondAmount,
                timeRemaining,
                timeStretch,
                sharePrice,
                initialSharePrice,
                false
            );

        // FIXME: Finish the shorting function.
    }
}
