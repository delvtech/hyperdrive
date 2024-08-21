// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC20 } from "./IERC20.sol";
import { IHyperdrive } from "./IHyperdrive.sol";
import { IMultiTokenCore } from "./IMultiTokenCore.sol";

interface IHyperdriveCore is IMultiTokenCore {
    /// Longs ///

    /// @notice Opens a long position.
    /// @param _amount The amount of capital provided to open the long. The
    ///        units of this quantity are either base or vault shares, depending
    ///        on the value of `_options.asBase`.
    /// @param _minOutput The minimum number of bonds to receive.
    /// @param _minVaultSharePrice The minimum vault share price at which to
    ///        open the long. This allows traders to protect themselves from
    ///        opening a long in a checkpoint where negative interest has
    ///        accrued.
    /// @param _options The options that configure how the trade is settled.
    /// @return maturityTime The maturity time of the bonds.
    /// @return bondProceeds The amount of bonds the user received.
    function openLong(
        uint256 _amount,
        uint256 _minOutput,
        uint256 _minVaultSharePrice,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256 maturityTime, uint256 bondProceeds);

    /// @notice Closes a long position with a specified maturity time.
    /// @param _maturityTime The maturity time of the long.
    /// @param _bondAmount The amount of longs to close.
    /// @param _minOutput The minimum proceeds the trader will accept. The units
    ///        of this quantity are either base or vault shares, depending on
    ///        the value of `_options.asBase`.
    /// @param _options The options that configure how the trade is settled.
    /// @return proceeds The proceeds the user receives. The units of this
    ///         quantity are either base or vault shares, depending on the value
    ///         of `_options.asBase`.
    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) external returns (uint256 proceeds);

    /// Shorts ///

    /// @notice Opens a short position.
    /// @param _bondAmount The amount of bonds to short.
    /// @param _maxDeposit The most the user expects to deposit for this trade.
    ///        The units of this quantity are either base or vault shares,
    ///        depending on the value of `_options.asBase`.
    /// @param _minVaultSharePrice The minimum vault share price at which to open
    ///        the short. This allows traders to protect themselves from opening
    ///        a short in a checkpoint where negative interest has accrued.
    /// @param _options The options that configure how the trade is settled.
    /// @return maturityTime The maturity time of the short.
    /// @return deposit The amount the user deposited for this trade. The units
    ///         of this quantity are either base or vault shares, depending on
    ///         the value of `_options.asBase`.
    function openShort(
        uint256 _bondAmount,
        uint256 _maxDeposit,
        uint256 _minVaultSharePrice,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256 maturityTime, uint256 deposit);

    /// @notice Closes a short position with a specified maturity time.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of shorts to close.
    /// @param _minOutput The minimum output of this trade. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _options The options that configure how the trade is settled.
    /// @return proceeds The proceeds of closing this short. The units of this
    ///         quantity are either base or vault shares, depending on the value
    ///         of `_options.asBase`.
    function closeShort(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) external returns (uint256 proceeds);

    /// LPs ///

    /// @notice Allows the first LP to initialize the market with a target APR.
    /// @param _contribution The amount of capital to supply. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _apr The target APR.
    /// @param _options The options that configure how the operation is settled.
    /// @return lpShares The initial number of LP shares created.
    function initialize(
        uint256 _contribution,
        uint256 _apr,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256 lpShares);

    /// @notice Allows LPs to supply liquidity for LP shares.
    /// @param _contribution The amount of capital to supply. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _minLpSharePrice The minimum LP share price the LP is willing
    ///        to accept for their shares. LPs incur negative slippage when
    ///        adding liquidity if there is a net curve position in the market,
    ///        so this allows LPs to protect themselves from high levels of
    ///        slippage. The units of this quantity are either base or vault
    ///        shares, depending on the value of `_options.asBase`.
    /// @param _minApr The minimum APR at which the LP is willing to supply.
    /// @param _maxApr The maximum APR at which the LP is willing to supply.
    /// @param _options The options that configure how the operation is settled.
    /// @return lpShares The LP shares received by the LP.
    function addLiquidity(
        uint256 _contribution,
        uint256 _minLpSharePrice,
        uint256 _minApr,
        uint256 _maxApr,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256 lpShares);

    /// @notice Allows an LP to burn shares and withdraw from the pool.
    /// @param _lpShares The LP shares to burn.
    /// @param _minOutputPerShare The minimum amount the LP expects to receive
    ///        for each withdrawal share that is burned. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _options The options that configure how the operation is settled.
    /// @return proceeds The amount the LP removing liquidity receives. The
    ///         units of this quantity are either base or vault shares,
    ///         depending on the value of `_options.asBase`.
    /// @return withdrawalShares The base that the LP receives buys out some of
    ///         their LP shares, but it may not be sufficient to fully buy the
    ///         LP out. In this case, the LP receives withdrawal shares equal in
    ///         value to the present value they are owed. As idle capital
    ///         becomes available, the pool will buy back these shares.
    function removeLiquidity(
        uint256 _lpShares,
        uint256 _minOutputPerShare,
        IHyperdrive.Options calldata _options
    ) external returns (uint256 proceeds, uint256 withdrawalShares);

    /// @notice Redeems withdrawal shares by giving the LP a pro-rata amount of
    ///         the withdrawal pool's proceeds. This function redeems the
    ///         maximum amount of the specified withdrawal shares given the
    ///         amount of withdrawal shares ready to withdraw.
    /// @param _withdrawalShares The withdrawal shares to redeem.
    /// @param _minOutputPerShare The minimum amount the LP expects to
    ///        receive for each withdrawal share that is burned. The units of
    ///        this quantity are either base or vault shares, depending on the
    ///        value of `_options.asBase`.
    /// @param _options The options that configure how the operation is settled.
    /// @return proceeds The amount the LP received. The units of this quantity
    ///         are either base or vault shares, depending on the value of
    ///         `_options.asBase`.
    /// @return withdrawalSharesRedeemed The amount of withdrawal shares that
    ///         were redeemed.
    function redeemWithdrawalShares(
        uint256 _withdrawalShares,
        uint256 _minOutputPerShare,
        IHyperdrive.Options calldata _options
    ) external returns (uint256 proceeds, uint256 withdrawalSharesRedeemed);

    /// Checkpoints ///

    /// @notice Attempts to mint a checkpoint with the specified checkpoint time.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @param _maxIterations The number of iterations to use in the Newton's
    ///        method component of `_distributeExcessIdleSafe`. This defaults to
    ///        `LPMath.SHARE_PROCEEDS_MAX_ITERATIONS` if the specified value is
    ///        smaller than the constant.
    function checkpoint(
        uint256 _checkpointTime,
        uint256 _maxIterations
    ) external;

    /// Admin ///

    // TODO: This function doesn't do anything anymore and is only here for
    // backwards compatability. This can be removed when the factory is upgraded.
    //
    /// @notice A stub for the old setPauser functions that doesn't do anything
    ///         anymore.
    /// @dev Don't call this. It doesn't do anything.
    function setGovernance(address _who) external;

    // TODO: This function doesn't do anything anymore and is only here for
    // backwards compatability. This can be removed when the factory is upgraded.
    //
    /// @notice A stub for the old setPauser functions that doesn't do anything
    ///         anymore.
    /// @dev Don't call this. It doesn't do anything.
    function setPauser(address, bool) external;

    /// @notice This function collects the governance fees accrued by the pool.
    /// @param _options The options that configure how the fees are settled.
    /// @return proceeds The governance fees collected. The units of this
    ///         quantity are either base or vault shares, depending on the value
    ///         of `_options.asBase`.
    function collectGovernanceFee(
        IHyperdrive.Options calldata _options
    ) external returns (uint256 proceeds);

    /// @notice Allows an authorized address to pause this contract.
    /// @param _status True to pause all deposits and false to unpause them.
    function pause(bool _status) external;

    /// @notice Transfers the contract's balance of a target token to the fee
    ///         collector address.
    /// @dev WARN: It is unlikely but possible that there is a selector overlap
    ///      with 'transferFrom'. Any integrating contracts should be checked
    ///      for that, as it may result in an unexpected call from this address.
    /// @param _target The target token to sweep.
    function sweep(IERC20 _target) external;
}
