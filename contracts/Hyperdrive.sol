// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AssetId } from "contracts/libraries/AssetId.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
import { MultiToken } from "contracts/MultiToken.sol";

/// @author Delve
/// @title Hyperdrive
/// @notice A fixed-rate AMM that mints bonds on demand for longs and shorts.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract Hyperdrive is MultiToken {
    using FixedPointMath for uint256;

    /// Tokens ///

    // @dev The base asset.
    IERC20 public immutable baseToken;

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

    // @notice The amount of longs that are still open.
    uint256 public longsOutstanding;

    // @notice The amount of shorts that are still open.
    uint256 public shortsOutstanding;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The factory which is used to deploy the ERC20
    ///        linker contracts.
    /// @param _baseToken The base token contract.
    /// @param _positionDuration The time in seconds that elaspes before bonds
    ///        can be redeemed one-to-one for base.
    /// @param _timeStretch The time stretch of the pool.
    constructor(
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20 _baseToken,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) MultiToken(_linkerCodeHash, _linkerFactory) {
        // Initialize the base token address.
        baseToken = _baseToken;

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
    /// @param _contribution The amount of base to supply.
    /// @param _apr The target APR.
    function initialize(uint256 _contribution, uint256 _apr) external {
        // Ensure that the pool hasn't been initialized yet.
        if (shareReserves > 0 || bondReserves > 0) {
            revert Errors.PoolAlreadyInitialized();
        }

        // Take custody of the base being supplied.
        bool success = baseToken.transferFrom(
            msg.sender,
            address(this),
            _contribution
        );
        if (!success) {
            revert Errors.TransferFailed();
        }

        // Calculate the amount of LP shares the initializer receives.
        uint256 lpShares = shareReserves;

        // Update the reserves.
        shareReserves = _contribution.divDown(sharePrice);
        bondReserves = HyperdriveMath.calculateBondReserves(
            shareReserves,
            lpShares,
            initialSharePrice,
            _apr,
            positionDuration,
            timeStretch
        );

        // Mint LP shares to the initializer.
        _mint(0, msg.sender, lpShares);
    }

    // TODO: Add slippage protection.
    //
    /// @notice Allows LPs to supply liquidity for LP shares.
    /// @param _contribution The amount of base to supply.
    function addLiquidty(uint256 _contribution) external {
        if (_contribution == 0) {
            revert Errors.ZeroAmount();
        }

        // Take custody of the base being supplied.
        bool success = baseToken.transferFrom(
            msg.sender,
            address(this),
            _contribution
        );
        if (!success) {
            revert Errors.TransferFailed();
        }

        // Calculate the pool's APR prior to updating the share reserves so that
        // we can compute the bond reserves update.
        uint256 apr = HyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            positionDuration,
            timeStretch
        );

        // Calculate the amount of LP shares that the supplier should receive.
        uint256 shares = _contribution.divDown(sharePrice);
        uint256 lpShares = HyperdriveMath.calculateLpSharesOutForSharesIn(
            shares,
            shareReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            longsOutstanding,
            shortsOutstanding,
            sharePrice
        );

        // Update the reserves.
        shareReserves += shares;
        bondReserves = HyperdriveMath.calculateBondReserves(
            shareReserves,
            totalSupply[AssetId._LP_ASSET_ID] + lpShares,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );

        // Mint LP shares to the supplier.
        _mint(AssetId._LP_ASSET_ID, msg.sender, lpShares);
    }

    // TODO: Consider if some MEV protection is necessary for the LP.
    //
    /// @notice Allows an LP to burn shares and withdraw from the pool.
    /// @param _shares The LP shares to burn.
    function removeLiquidity(uint256 _shares) external {
        if (_shares == 0) {
            revert Errors.ZeroAmount();
        }

        // Calculate the pool's APR prior to updating the share reserves and LP
        // total supply so that we can compute the bond reserves update.
        uint256 apr = HyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            positionDuration,
            timeStretch
        );

        // Calculate the amount of base that should be withdrawn.
        uint256 shareProceeds = HyperdriveMath.calculateSharesOutForLpSharesIn(
            _shares,
            shareReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            longsOutstanding,
            sharePrice
        );

        // Burn the LP shares.
        _burn(AssetId._LP_ASSET_ID, msg.sender, _shares);

        // Update the reserves.
        shareReserves -= shareProceeds;
        bondReserves = HyperdriveMath.calculateBondReserves(
            shareReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );

        // Transfer the base proceeds to the LP.
        bool success = baseToken.transfer(
            msg.sender,
            shareProceeds.mulDown(sharePrice)
        );
        if (!success) {
            revert Errors.TransferFailed();
        }
    }

    /// Long ///

    /// @notice Opens a long position.
    /// @param _baseAmount The amount of base to use when trading.
    function openLong(uint256 _baseAmount) external {
        if (_baseAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Take custody of the base that is being traded into the contract.
        bool success = baseToken.transferFrom(
            msg.sender,
            address(this),
            _baseAmount
        );
        if (!success) {
            revert Errors.TransferFailed();
        }

        // Calculate the pool and user deltas using the trading function.
        uint256 shareAmount = _baseAmount.divDown(sharePrice);
        (, uint256 poolBondDelta, uint256 bondProceeds) = HyperdriveMath
            .calculateOutGivenIn(
                shareReserves,
                bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                shareAmount,
                FixedPointMath.ONE_18,
                timeStretch,
                sharePrice,
                initialSharePrice,
                true
            );

        // Apply the trading deltas to the reserves and update the amount of
        // longs outstanding.
        shareReserves += shareAmount;
        bondReserves -= poolBondDelta;
        longsOutstanding += bondProceeds;

        // TODO: We should fuzz test this and other trading functions to ensure
        // that the APR never goes below zero. If it does, we may need to
        // enforce additional invariants.
        //
        // Since the base buffer may have increased relative to the base
        // reserves and the bond reserves decreased, we must ensure that the
        // base reserves are greater than the longsOutstanding.
        if (sharePrice * shareReserves >= longsOutstanding) {
            revert Errors.BaseBufferExceedsShareReserves();
        }

        // Mint the bonds to the trader with an ID of the maturity time.
        _mint(block.timestamp + positionDuration, msg.sender, bondProceeds);
    }

    /// @notice Closes a long position with a specified maturity time.
    /// @param _maturityTime The maturity time of the longs to close.
    /// @param _bondAmount The amount of longs to close.
    function closeLong(uint32 _maturityTime, uint256 _bondAmount) external {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Burn the longs that are being closed.
        uint256 maturityTime = uint32(_maturityTime);
        _burn(maturityTime, msg.sender, _bondAmount);
        longsOutstanding -= _bondAmount;

        // Calculate the pool and user deltas using the trading function.
        uint256 timeRemaining = block.timestamp < maturityTime
            ? (maturityTime - block.timestamp) * FixedPointMath.ONE_18
            : 0;
        (
            uint256 poolShareDelta,
            uint256 poolBondDelta,
            uint256 shareProceeds
        ) = HyperdriveMath.calculateOutGivenIn(
                shareReserves,
                bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                _bondAmount,
                timeRemaining,
                timeStretch,
                sharePrice,
                initialSharePrice,
                false
            );

        // Apply the trading deltas to the reserves and decrease the base buffer
        // by the amount of bonds sold. Since the difference between the base
        // reserves and the longs outstanding stays the same or gets larger and
        // the difference between the bond reserves and the bond buffer increases,
        // we don't need to check that the reserves are larger than the buffers.
        shareReserves -= poolShareDelta;
        bondReserves += poolBondDelta;

        // Transfer the base returned to the trader.
        bool success = baseToken.transfer(
            msg.sender,
            shareProceeds.mulDown(sharePrice)
        );
        if (!success) {
            revert Errors.TransferFailed();
        }
    }

    /// Short ///

    /// @notice Opens a short position.
    /// @param _bondAmount The amount of bonds to short.
    function openShort(uint256 _bondAmount) external {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Calculate the pool and user deltas using the trading function.
        (uint256 poolShareDelta, , uint256 shareProceeds) = HyperdriveMath
            .calculateOutGivenIn(
                shareReserves,
                bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
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
            revert Errors.TransferFailed();
        }

        // Apply the trading deltas to the reserves and increase the bond buffer
        // by the amount of bonds that were shorted.
        shareReserves -= poolShareDelta;
        bondReserves += _bondAmount;
        shortsOutstanding += _bondAmount;

        // Since the share reserves are reduced, we need to verify that the base
        // reserves are greater than or equal to the amount of longs outstanding.
        if (sharePrice * shareReserves >= longsOutstanding) {
            revert Errors.BaseBufferExceedsShareReserves();
        }

        // Mint the short tokens to the trader. The ID is a concatenation of the
        // current share price and the maturity time of the shorts.
        _mint(
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Short,
                sharePrice,
                block.timestamp + positionDuration
            ),
            msg.sender,
            _bondAmount
        );
    }

    /// @notice Closes a short position with a specified maturity time.
    /// @param _assetId The asset ID of the short.
    /// @param _bondAmount The amount of shorts to close.
    function closeShort(uint256 _assetId, uint256 _bondAmount) external {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Ensure that the asset ID refers to a short and get the open share
        // price and maturity time from the short key.
        (
            AssetId.AssetIdPrefix prefix,
            uint256 openSharePrice,
            uint256 maturityTime
        ) = AssetId.decodeAssetId(_assetId);
        if (prefix != AssetId.AssetIdPrefix.Short) {
            revert Errors.UnexpectedAssetId();
        }

        // Burn the shorts that are being closed.
        _burn(_assetId, msg.sender, _bondAmount);
        shortsOutstanding -= _bondAmount;

        // Calculate the pool and user deltas using the trading function.
        uint256 timeRemaining = block.timestamp < maturityTime
            ? (maturityTime - block.timestamp) * FixedPointMath.ONE_18
            : 0;
        (
            uint256 poolShareDelta,
            uint256 poolBondDelta,
            uint256 sharePayment
        ) = HyperdriveMath.calculateBaseInGivenBondsOut(
                shareReserves,
                bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
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
            revert Errors.TransferFailed();
        }
    }
}
