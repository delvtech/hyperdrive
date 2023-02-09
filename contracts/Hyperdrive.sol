// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

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

// TODO - Here we give default implementations of the virtual methods to not break tests
//        we should move to an abstract contract to prevent this from being deployed w/o
//        real implementations.
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

    // @notice The amount of long withdrawal shares that haven't been paid out.
    uint256 public longWithdrawalSharesOutstanding;

    // @notice The amount of short withdrawal shares that haven't been paid out.
    uint256 public shortWithdrawalSharesOutstanding;

    // @notice The proceeds that have accrued to the long withdrawal shares.
    uint256 public longWithdrawalShareProceeds;

    // @notice The proceeds that have accrued to the short withdrawal shares.
    uint256 public shortWithdrawalShareProceeds;

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
        uint256 _initialPricePerShare
    ) MultiToken(_linkerCodeHash, _linkerFactory) {
        // Initialize the base token address.
        baseToken = _baseToken;

        // Initialize the time configurations.
        positionDuration = _positionDuration;
        timeStretch = _timeStretch;

        initialSharePrice = _initialPricePerShare;
    }

    /// Yield Source ///
    // In order to deploy a yield source implement must be written which implements the following methods

    ///@notice Transfers amount of 'token' from the user and commits it to the yield source.
    ///@param amount The amount of token to transfer
    ///@return sharesMinted The shares this deposit creates
    ///@return pricePerShare The price per share at time of deposit
    function deposit(
        uint256 amount
    ) internal virtual returns (uint256 sharesMinted, uint256 pricePerShare) {}

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
        virtual
        returns (uint256 amountWithdrawn, uint256 pricePerShare)
    {}

    ///@notice Loads the price per share from the yield source
    ///@return pricePerShare The current price per share
    function _pricePerShare()
        internal
        virtual
        returns (uint256 pricePerShare)
    {}

    /// LP ///

    /// @notice Allows the first LP to initialize the market with a target APR.
    /// @param _contribution The amount of base to supply.
    /// @param _apr The target APR.
    function initialize(uint256 _contribution, uint256 _apr) external {
        // Ensure that the pool hasn't been initialized yet.
        if (shareReserves > 0 || bondReserves > 0) {
            revert Errors.PoolAlreadyInitialized();
        }

        // Deposit for the user, this transfers from them.
        (uint256 shares, uint256 pricePerShare) = deposit(_contribution);

        // Set the state variables.
        shareReserves = shares;
        // We calculate the implied bond reserve from the share price
        bondReserves = HyperdriveMath.calculateBondReserves(
            shares,
            shares,
            pricePerShare,
            _apr,
            positionDuration,
            timeStretch
        );

        // Mint LP shares to the initializer.
        // TODO - Should we index the lp share and virtual reserve to shares or to underlying?
        //        I think in the case where price per share < 1 there may be a problem.
        _mint(AssetId._LP_ASSET_ID, msg.sender, shares);
    }

    // TODO: Add slippage protection.
    //
    /// @notice Allows LPs to supply liquidity for LP shares.
    /// @param _contribution The amount of base to supply.
    function addLiquidty(uint256 _contribution) external {
        if (_contribution == 0) {
            revert Errors.ZeroAmount();
        }

        // Deposit for the user, this call also transfers from them
        (uint256 shares, uint256 pricePerShare) = deposit(_contribution);

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
        uint256 lpShares = HyperdriveMath.calculateLpSharesOutForSharesIn(
            shares,
            shareReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            longsOutstanding,
            shortsOutstanding,
            pricePerShare
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

        // Calculate the withdrawal proceeds of the LP. This includes the base,
        // long withdrawal shares, and short withdrawal shares that the LP
        // receives.
        (
            uint256 shareProceeds,
            uint256 longWithdrawalShares,
            uint256 shortWithdrawalShares
        ) = HyperdriveMath.calculateOutForLpSharesIn(
                _shares,
                shareReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                longsOutstanding,
                shortsOutstanding,
                _pricePerShare()
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

        // TODO: Update this when we implement tranches.
        //
        // Mint the long and short withdrawal tokens.
        _mint(
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.LongWithdrawalShare,
                0,
                0
            ),
            msg.sender,
            longWithdrawalShares
        );
        longWithdrawalSharesOutstanding += longWithdrawalShares;
        _mint(
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.ShortWithdrawalShare,
                0,
                0
            ),
            msg.sender,
            shortWithdrawalShares
        );
        shortWithdrawalSharesOutstanding += shortWithdrawalShares;

        // Withdraw the shares from the yield source
        // TODO - Good destination support.
        withdraw(shareProceeds, msg.sender);
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

        // Load price per share from the yield source
        uint256 sharePrice = _pricePerShare();
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
        if (sharePrice.mulDown(shareReserves) < longsOutstanding) {
            revert Errors.BaseBufferExceedsShareReserves();
        }

        // Mint the bonds to the trader with an ID of the maturity time.
        _mint(
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Long,
                sharePrice,
                block.timestamp + positionDuration
            ),
            msg.sender,
            bondProceeds
        );
    }

    /// @notice Closes a long position with a specified maturity time.
    /// @param _openSharePrice The opening share price of the short.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of longs to close.
    function closeLong(
        uint256 _openSharePrice,
        uint32 _maturityTime,
        uint256 _bondAmount
    ) external {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Burn the longs that are being closed.
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            _openSharePrice,
            _maturityTime
        );
        _burn(assetId, msg.sender, _bondAmount);
        longsOutstanding -= _bondAmount;

        // Load the price per share
        uint256 sharePrice = _pricePerShare();

        // Calculate the pool and user deltas using the trading function.
        uint256 timeRemaining = block.timestamp < uint256(_maturityTime)
            ? (uint256(_maturityTime) - block.timestamp).divDown(
                positionDuration
            ) // use divDown to scale to fixed point
            : 0;
        (, uint256 poolBondDelta, uint256 shareProceeds) = HyperdriveMath
            .calculateOutGivenIn(
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

        // If there are outstanding long withdrawal shares, we attribute a
        // proportional amount of the proceeds to the withdrawal pool and the
        // active LPs. Otherwise, we use simplified accounting that has the same
        // behavior but is more gas efficient. Since the difference between the
        // base reserves and the longs outstanding stays the same or gets
        // larger, we don't need to verify the reserves invariants.
        if (longWithdrawalSharesOutstanding > 0) {
            _applyCloseLong(
                _bondAmount,
                poolBondDelta,
                shareProceeds,
                _openSharePrice,
                sharePrice
            );
        } else {
            shareReserves -= shareProceeds;
            bondReserves += poolBondDelta;
        }

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

        // Load the share price at the current block
        uint256 sharePrice = _pricePerShare();

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
        // And deposit it into the yield source
        uint256 baseProceeds = shareProceeds.mulDown(sharePrice);
        deposit(_bondAmount - baseProceeds);

        // Apply the trading deltas to the reserves and increase the bond buffer
        // by the amount of bonds that were shorted.
        shareReserves -= poolShareDelta;
        bondReserves += _bondAmount;
        shortsOutstanding += _bondAmount;

        // Since the share reserves are reduced, we need to verify that the base
        // reserves are greater than or equal to the amount of longs outstanding.
        if (sharePrice.mulDown(shareReserves) < longsOutstanding) {
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
    /// @param _openSharePrice The opening share price of the short.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of shorts to close.
    function closeShort(
        uint256 _openSharePrice,
        uint32 _maturityTime,
        uint256 _bondAmount
    ) external {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Burn the shorts that are being closed.
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Short,
            _openSharePrice,
            _maturityTime
        );
        _burn(assetId, msg.sender, _bondAmount);
        shortsOutstanding -= _bondAmount;

        // Load the share price
        uint256 sharePrice = _pricePerShare();

        // Calculate the pool and user deltas using the trading function.
        uint256 timeRemaining = block.timestamp < uint256(_maturityTime)
            ? (uint256(_maturityTime) - block.timestamp).divDown(
                positionDuration
            ) // use divDown to scale to fixed point
            : 0;
        (
            uint256 poolShareDelta,
            uint256 poolBondDelta,
            uint256 sharePayment
        ) = HyperdriveMath.calculateSharesInGivenBondsOut(
                shareReserves,
                bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                _bondAmount,
                timeRemaining,
                timeStretch,
                sharePrice,
                initialSharePrice
            );

        // If there are outstanding short withdrawal shares, we attribute a
        // proportional amount of the proceeds to the withdrawal pool and the
        // active LPs. Otherwise, we use simplified accounting that has the same
        // behavior but is more gas efficient. Since the share reserves increase
        // or stay the same, there is no need to check that the share reserves
        // are greater than or equal to the base buffer.
        if (shortWithdrawalSharesOutstanding > 0) {
            _applyCloseShort(
                _bondAmount,
                poolBondDelta,
                sharePayment,
                sharePrice
            );
        } else {
            shareReserves += poolShareDelta;
            bondReserves -= poolBondDelta;
        }

        // Convert the bonds to current shares
        uint256 _bondsInShares = _bondAmount.divDown(sharePrice);
        // Transfer the profit to the shorter. This includes the proceeds from
        // the short sale as well as the variable interest that was collected
        // on the face value of the bonds. The math for the short's proceeds is
        // given by:
        //
        // c * (dy / c_0 - dz)
        uint256 shortProceeds = (
            _bondsInShares.mulDown(sharePrice.divDown(_openSharePrice)).sub(
                sharePayment
            )
        );
        // Withdraw from the reserves
        // TODO - Better destination support
        withdraw(shortProceeds, msg.sender);
    }

    /// Helpers ///

    /// @dev Applies the trading deltas from a closed long to the reserves and
    ///      the withdrawal pool.
    /// @param _bondAmount The amount of longs that were closed.
    /// @param _poolBondDelta The amount of bonds that the pool would be
    ///        decreased by if we didn't need to account for the withdrawal
    ///        pool.
    /// @param _shareProceeds The proceeds in shares received from closing the
    ///        long.
    /// @param _openSharePrice The share price at the time the long was opened.
    /// @param _sharePrice The current share price
    function _applyCloseLong(
        uint256 _bondAmount,
        uint256 _poolBondDelta,
        uint256 _shareProceeds,
        uint256 _openSharePrice,
        uint256 _sharePrice
    ) internal {
        // Calculate the effect that the trade has on the pool's APR.
        uint256 apr = HyperdriveMath.calculateAPRFromReserves(
            shareReserves.sub(_shareProceeds),
            bondReserves.add(_poolBondDelta),
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            positionDuration,
            timeStretch
        );

        // Apply the LP proceeds from the trade proportionally to the long
        // withdrawal shares. The accounting for these proceeds is identical
        // to the close short accounting because LPs take the short position
        // when longs are opened. The math for the withdrawal proceeds is given
        // by:
        //
        // c * (dy / c_0 - dz) * (min(b_x, dy) / dy)
        uint256 withdrawalAmount = longWithdrawalSharesOutstanding < _bondAmount
            ? longWithdrawalSharesOutstanding
            : _bondAmount;
        uint256 withdrawalProceeds = _sharePrice
            .mulDown(_bondAmount.divDown(_openSharePrice).sub(_shareProceeds))
            .mulDown(withdrawalAmount.divDown(_bondAmount));
        longWithdrawalSharesOutstanding -= withdrawalAmount;
        longWithdrawalShareProceeds += withdrawalProceeds;

        // Apply the trading deltas to the reserves. These updates reflect
        // the fact that some of the reserves will be attributed to the
        // withdrawal pool. The math for the share reserves update is given by:
        //
        // z -= dz + (dy / c_0 - dz) * (min(b_x, dy) / dy)
        shareReserves -= _shareProceeds.add(
            withdrawalProceeds.divDown(_sharePrice)
        );
        bondReserves = HyperdriveMath.calculateBondReserves(
            shareReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
    }

    /// @dev Applies the trading deltas from a closed short to the reserves and
    ///      the withdrawal pool.
    /// @param _bondAmount The amount of shorts that were closed.
    /// @param _poolBondDelta The amount of bonds that the pool would be
    ///        decreased by if we didn't need to account for the withdrawal
    ///        pool.
    /// @param _sharePayment The payment in shares required to close the short.
    /// @param _sharePrice The current share price
    function _applyCloseShort(
        uint256 _bondAmount,
        uint256 _poolBondDelta,
        uint256 _sharePayment,
        uint256 _sharePrice
    ) internal {
        // Calculate the effect that the trade has on the pool's APR.
        uint256 apr = HyperdriveMath.calculateAPRFromReserves(
            shareReserves.add(_sharePayment),
            bondReserves.sub(_poolBondDelta),
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            positionDuration,
            timeStretch
        );

        // Apply the LP proceeds from the trade proportionally to the short
        // withdrawal pool. The accounting for these proceeds is identical
        // to the close long accounting because LPs take on a long position when
        // shorts are opened. The math for the withdrawal proceeds is given
        // by:
        //
        // c * dz * (min(b_y, dy) / dy)
        uint256 withdrawalAmount = shortWithdrawalSharesOutstanding <
            _bondAmount
            ? shortWithdrawalSharesOutstanding
            : _bondAmount;
        uint256 withdrawalProceeds = _sharePrice.mulDown(_sharePayment).mulDown(
            withdrawalAmount.divDown(_bondAmount)
        );
        shortWithdrawalSharesOutstanding -= withdrawalAmount;
        shortWithdrawalShareProceeds += withdrawalProceeds;

        // Apply the trading deltas to the reserves. These updates reflect
        // the fact that some of the reserves will be attributed to the
        // withdrawal pool. The math for the share reserves update is given by:
        //
        // z += dz - dz * (min(b_y, dy) / dy)
        shareReserves += _sharePayment.sub(
            withdrawalProceeds.divDown(_sharePrice)
        );
        bondReserves = HyperdriveMath.calculateBondReserves(
            shareReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
    }
}
