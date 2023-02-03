// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { HyperdriveError } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
import { IERC1155Mintable } from "contracts/interfaces/IERC1155Mintable.sol";

/// @author Delve
/// @title Hyperdrive
/// @notice A fixed-rate AMM that mints bonds on demand for longs and shorts.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract Hyperdrive is ERC20 {
    using FixedPointMath for uint256;

    /// Tokens ///

    // @dev The base asset.
    IERC20 public immutable baseToken;

    // @dev A mintable ERC1155 token that is used to record long balances.
    //      Hyperdrive must be able to mint short tokens for trading to occur.
    IERC1155Mintable public immutable longToken;

    // @dev A mintable ERC1155 token that is used to record short balances.
    //      Hyperdrive must be able to mint short tokens for trading to occur.
    IERC1155Mintable public immutable shortToken;

    /// Time ///

    // @dev The amount of seconds that elapse before a bond can be redeemed.
    uint256 public immutable positionDuration;

    // @dev A parameter that decreases slippage around a target rate.
    uint256 public immutable timeStretch;

    /// Market state ///

    // @dev The share price at the time the pool was created.
    uint256 public immutable initialSharePrice;

    // @dev The current share price.
    uint256 public sharePrice;

    // @dev The share reserves. The share reserves multiplied by the share price
    //      give the base reserves, so shares are a mechanism of ensuring that
    //      interest is properly awarded over time.
    uint256 public shareReserves;

    // @dev The bond reserves. In Hyperdrive, the bond reserves aren't backed by
    //      pre-minted bonds and are instead used as a virtual value that
    //      ensures that the spot rate changes according to the laws of supply
    //      and demand.
    uint256 public bondReserves;

    // @dev The base buffer stores the amount of outstanding obligations to bond
    //      holders. This is required to maintain solvency since the bond
    //      reserves are virtual and bonds are minted on demand.
    uint256 public baseBuffer;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _baseToken The base token contract.
    /// @param _longToken The long token contract.
    /// @param _shortToken The short token contract.
    /// @param _positionDuration The time in seconds that elaspes before bonds
    ///        can be redeemed one-to-one for base.
    /// @param _timeStretch The time stretch of the pool.
    constructor(
        IERC20 _baseToken,
        IERC1155Mintable _longToken,
        IERC1155Mintable _shortToken,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) ERC20("Hyperdrive LP", "hLP") {
        // Initialize the token addresses.
        baseToken = _baseToken;
        longToken = _longToken;
        shortToken = _shortToken;

        // Initialize the time configurations.
        positionDuration = _positionDuration;
        timeStretch = _timeStretch;

        // TODO: This isn't correct. This will need to be updated when asset
        // delgation is implemented.
        initialSharePrice = FixedPointMath.ONE_18;
        sharePrice = FixedPointMath.ONE_18;
    }

    /// LP ///

    /// @notice Allows the first LP to initialize the market with a target APR.
    /// @param _contribution The amount of base asset to contribute.
    /// @param _apr The target APR.
    function initialize(uint256 _contribution, uint256 _apr) external {
        // Ensure that the pool hasn't been initialized yet.
        if (shareReserves > 0 || bond_reserves > 0) {
            revert HyperdriveError.PoolAlreadyInitialized();
        }

        // Pull the contribution into the contract.
        bool success = baseToken.transferFrom(
            msg.sender,
            address(this),
            _contribution
        );
        if (!success) {
            revert HyperdriveError.TransferFailed();
        }

        // Update the reserves.
        shareReserves = _contribution; // TODO: Update when using non-trivial share price.
        bondReserves = HyperdriveMath.calculateBondReserves(
            _contribution, // TODO: Update when using non-trivial share price.
            initialSharePrice,
            sharePrice,
            _apr,
            positionDuration,
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
            revert HyperdriveError.ZeroAmount();
        }

        // Take custody of the base that is being traded into the contract.
        bool success = baseToken.transferFrom(
            msg.sender,
            address(this),
            _baseAmount
        );
        if (!success) {
            revert HyperdriveError.TransferFailed();
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
            revert HyperdriveError.BaseBufferExceedsShareReserves();
        }

        // Mint the bonds to the trader with an ID of the maturity time.
        longToken.mint(
            msg.sender,
            block.timestamp + positionDuration,
            bondProceeds,
            new bytes(0)
        );
    }

    /// @notice Closes a long position with a specified maturity time.
    /// @param _maturityTime The maturity time of the longs to close.
    /// @param _bondAmount The amount of longs to close.
    function closeLong(uint256 _maturityTime, uint256 _bondAmount) external {
        if (_bondAmount == 0) {
            revert HyperdriveError.ZeroAmount();
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
            revert HyperdriveError.TransferFailed();
        }
    }

    /// Short ///

    /// @notice Opens a short position.
    /// @param _bondAmount The amount of bonds to short.
    function openShort(uint256 _bondAmount) external {
        if (_bondAmount == 0) {
            revert HyperdriveError.ZeroAmount();
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
            revert HyperdriveError.TransferFailed();
        }

        // Apply the trading deltas to the reserves and increase the bond buffer
        // by the amount of bonds that were shorted.
        shareReserves -= poolShareDelta;
        bondReserves += _bondAmount;

        // Since the share reserves are reduced, we need to verify that the base
        // reserves are greater than or equal to the base buffer.
        if (sharePrice * shareReserves >= baseBuffer) {
            revert HyperdriveError.BaseBufferExceedsShareReserves();
        }

        // Mint the short tokens to the trader. The ID is a concatenation of the
        // current share price and the maturity time of the shorts.
        shortToken.mint(
            msg.sender,
            encodeShortKey(sharePrice, block.timestamp + positionDuration),
            _bondAmount,
            new bytes(0)
        );
    }

    /// @notice Closes a short position with a specified maturity time.
    /// @param _key The key of the shorts to close. The short key is a
    ///        concatenation of the share price when the short was opened and
    ///        the maturity time of the short.
    /// @param _bondAmount The amount of shorts to close.
    function closeShort(uint256 _key, uint256 _bondAmount) external {
        if (_bondAmount == 0) {
            revert HyperdriveError.ZeroAmount();
        }

        // Burn the shorts that are being closed.
        shortToken.burn(msg.sender, _key, _bondAmount);

        // Get the open share price and maturity time from the short key.
        (uint256 openSharePrice, uint256 maturityTime) = decodeShortKey(_key);

        // Calculate the pool and user deltas using the trading function.
        uint256 timeRemaining = block.timestamp < maturityTime
            ? (maturityTime - block.timestamp) * FixedPointMath.ONE_18
            : 0;
        (
            uint256 poolShareDelta,
            uint256 poolBondDelta,
            uint256 sharePayment
        ) = HyperdriveMath.calculateInGivenOut(
                shareReserves,
                bondReserves,
                totalSupply(),
                _bondAmount,
                timeRemaining,
                timeStretch,
                sharePrice,
                initialSharePrice
            );

        // Apply the trading deltas to the reserves. Since the share reserves
        // increase or stay the same, there is no need to check that the share
        // reserves are greater than or equal to the base buffer.
        shareReserves += poolShareDelta;
        bondReserves -= poolBondDelta;

        // Transfer the profit to the shorter. This includes the proceeds from
        // the short sale as well as the variable interest that was collected
        // on the face value of the bonds.
        uint256 tradingProceeds = _bondAmount.sub(
            sharePrice.mulDown(sharePayment)
        );
        uint256 interestProceeds = sharePrice
            .divDown(openSharePrice)
            .sub(FixedPointMath.ONE_18)
            .mulDown(_bondAmount);
        bool success = baseToken.transfer(
            msg.sender,
            tradingProceeds.add(interestProceeds)
        );
        if (!success) {
            revert HyperdriveError.TransferFailed();
        }
    }

    /// Utilities ///

    /// @notice Serializes a share price and a maturity time into a short key.
    /// @param _openSharePrice The share price when the short was opened.
    /// @param _maturityTime The maturity time of the bond that was shorted.
    /// @return key The serialized short key.
    function encodeShortKey(
        uint256 _openSharePrice,
        uint256 _maturityTime
    ) public pure returns (uint256 key) {
        return (_openSharePrice << 32) | _maturityTime;
    }

    /// @notice Deserializes a short key into the opening share price and
    ///         maturity time.
    /// @param _key The serialized short key.
    /// @return openSharePrice The share price when the short was opened.
    /// @return maturityTime The maturity time of the bond that was shorted.
    function decodeShortKey(
        uint256 _key
    ) public pure returns (uint256 openSharePrice, uint256 maturityTime) {
        openSharePrice = _key >> 32; // most significant 224 bits
        maturityTime = _key & 0xffffffff; // least significant 32 bits
        return (openSharePrice, maturityTime);
    }
}
