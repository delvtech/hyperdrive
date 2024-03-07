// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveRead } from "../interfaces/IHyperdriveRead.sol";
import { HyperdriveAdmin } from "../internal/HyperdriveAdmin.sol";
import { HyperdriveCheckpoint } from "../internal/HyperdriveCheckpoint.sol";
import { HyperdriveLong } from "../internal/HyperdriveLong.sol";
import { HyperdriveLP } from "../internal/HyperdriveLP.sol";
import { HyperdriveMultiToken } from "../internal/HyperdriveMultiToken.sol";
import { HyperdriveShort } from "../internal/HyperdriveShort.sol";
import { HyperdriveStorage } from "../internal/HyperdriveStorage.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { LPMath } from "../libraries/LPMath.sol";

/// @author DELV
/// @title HyperdriveTarget0
/// @notice Hyperdrive's target 0 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveTarget0 is
    IHyperdriveRead,
    HyperdriveAdmin,
    HyperdriveMultiToken,
    HyperdriveLP,
    HyperdriveLong,
    HyperdriveShort,
    HyperdriveCheckpoint
{
    using FixedPointMath for uint256;

    /// @notice Instantiates target0.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveStorage(_config) {}

    /// Admin ///

    /// @notice This function collects the governance fees accrued by the pool.
    /// @param _options The options that configure how the fees are settled.
    /// @return proceeds The governance fees collected. The units of this
    ///         quantity are either base or vault shares, depending on the value
    ///         of `_options.asBase`.
    function collectGovernanceFee(
        IHyperdrive.Options calldata _options
    ) external returns (uint256 proceeds) {
        return _collectGovernanceFee(_options);
    }

    /// @notice Allows an authorized address to pause this contract.
    /// @param _status True to pause all deposits and false to unpause them.
    function pause(bool _status) external {
        _pause(_status);
    }

    /// @notice Allows governance to change governance.
    /// @param _who The new governance address.
    function setGovernance(address _who) external {
        _setGovernance(_who);
    }

    /// @notice Allows governance to change the pauser status of an address.
    /// @param who The address to change.
    /// @param status The new pauser status.
    function setPauser(address who, bool status) external {
        _setPauser(who, status);
    }

    /// MultiToken ///

    /// @notice Transfers an amount of assets from the source to the destination.
    /// @param tokenID The token identifier.
    /// @param from The address whose balance will be reduced.
    /// @param to The address whose balance will be increased.
    /// @param amount The amount of token to move.
    function transferFrom(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount
    ) external {
        // Forward to our internal version
        _transferFrom(tokenID, from, to, amount, msg.sender);
    }

    /// @notice Permissioned transfer for the bridge to access, only callable by
    ///         the ERC20 linking bridge.
    /// @param tokenID The token identifier.
    /// @param from The address whose balance will be reduced.
    /// @param to The address whose balance will be increased.
    /// @param amount The amount of token to move.
    /// @param caller The msg.sender from the bridge.
    function transferFromBridge(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount,
        address caller
    ) external onlyLinker(tokenID) {
        // Route to our internal transfer
        _transferFrom(tokenID, from, to, amount, caller);
    }

    /// @notice Allows the compatibility linking contract to forward calls to
    ///         set asset approvals.
    /// @param tokenID The asset to approve the use of.
    /// @param operator The address who will be able to use the tokens.
    /// @param amount The max tokens the approved person can use, setting to
    ///        uint256.max will cause the value to never decrement [saving gas
    ///        on transfer].
    /// @param caller The eth address which called the linking contract.
    function setApprovalBridge(
        uint256 tokenID,
        address operator,
        uint256 amount,
        address caller
    ) external onlyLinker(tokenID) {
        _setApproval(tokenID, operator, amount, caller);
    }

    /// @notice Allows a user to approve an operator to use all of their assets.
    /// @param operator The eth address which can access the caller's assets.
    /// @param approved True to approve, false to remove approval.
    function setApprovalForAll(address operator, bool approved) external {
        // set the appropriate state
        _isApprovedForAll[msg.sender][operator] = approved;
        // Emit an event to track approval
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @notice Allows a user to set an approval for an individual asset with
    ///         specific amount.
    /// @param tokenID The asset to approve the use of.
    /// @param operator The address who will be able to use the tokens.
    /// @param amount The max tokens the approved person can use, setting to
    ///        uint256.max will cause the value to never decrement (saving gas
    ///        on transfer).
    function setApproval(
        uint256 tokenID,
        address operator,
        uint256 amount
    ) external {
        _setApproval(tokenID, operator, amount, msg.sender);
    }

    /// @notice Transfers several assets from one account to another.
    /// @param from The source account.
    /// @param to The destination account.
    /// @param ids The array of token ids of the asset to transfer.
    /// @param values The amount of each token to transfer.
    function batchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values
    ) external {
        _batchTransferFrom(from, to, ids, values);
    }

    /// @notice Allows a caller who is not the owner of an account to execute
    ///         the functionality of 'approve' for all assets with the owner's
    ///         signature.
    /// @param domainSeparator The EIP712 domain separator of the contract.
    /// @param permitTypeHash The EIP712 domain separator of the contract.
    /// @param owner The owner of the account which is having the new approval set.
    /// @param spender The address which will be allowed to spend owner's tokens.
    /// @param _approved A boolean of the approval status to set to.
    /// @param deadline The timestamp which the signature must be submitted by
    ///        to be valid.
    /// @param v Extra ECDSA data which allows public key recovery from
    ///        signature assumed to be 27 or 28.
    /// @param r The r component of the ECDSA signature.
    /// @param s The s component of the ECDSA signature.
    /// @dev The signature for this function follows EIP 712 standard and should
    ///      be generated with the eth_signTypedData JSON RPC call instead of
    ///      the eth_sign JSON RPC call. If using out of date parity signing
    ///      libraries the v component may need to be adjusted. Also it is very
    ///      rare but possible for v to be other values, those values are not
    ///      supported.
    function permitForAll(
        bytes32 domainSeparator,
        bytes32 permitTypeHash,
        address owner,
        address spender,
        bool _approved,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _permitForAll(
            domainSeparator,
            permitTypeHash,
            owner,
            spender,
            _approved,
            deadline,
            v,
            r,
            s
        );
    }

    /// Getters ///

    /// @notice Gets the pauser status of an address.
    /// @param _account The account to check.
    /// @return The pauser status.
    function isPauser(address _account) external view returns (bool) {
        _revert(abi.encode(_pausers[_account]));
    }

    /// @notice Gets the base token.
    /// @return The base token.
    function baseToken() external view returns (address) {
        _revert(abi.encode(_baseToken));
    }

    /// @notice Gets a specified checkpoint.
    /// @param _checkpointTime The checkpoint time.
    /// @return The checkpoint.
    function getCheckpoint(
        uint256 _checkpointTime
    ) external view returns (IHyperdrive.Checkpoint memory) {
        _revert(abi.encode(_checkpoints[_checkpointTime]));
    }

    /// @notice Gets the checkpoint exposure at a specified time.
    /// @param _checkpointTime The checkpoint time.
    /// @return The checkpoint exposure.
    function getCheckpointExposure(
        uint256 _checkpointTime
    ) external view returns (int256) {
        _revert(
            abi.encode(_nonNettedLongs(_checkpointTime + _positionDuration))
        );
    }

    /// @notice Gets the pool's configuration parameters.
    /// @dev These parameters are immutable, so this should only need to be
    ///      called once.
    /// @return The PoolConfig struct.
    function getPoolConfig()
        external
        view
        returns (IHyperdrive.PoolConfig memory)
    {
        _revert(
            abi.encode(
                IHyperdrive.PoolConfig({
                    baseToken: _baseToken,
                    linkerFactory: _linkerFactory,
                    linkerCodeHash: _linkerCodeHash,
                    initialVaultSharePrice: _initialVaultSharePrice,
                    minimumShareReserves: _minimumShareReserves,
                    minimumTransactionAmount: _minimumTransactionAmount,
                    positionDuration: _positionDuration,
                    checkpointDuration: _checkpointDuration,
                    timeStretch: _timeStretch,
                    governance: _governance,
                    feeCollector: _feeCollector,
                    fees: IHyperdrive.Fees(
                        _curveFee,
                        _flatFee,
                        _governanceLPFee,
                        _governanceZombieFee
                    )
                })
            )
        );
    }

    /// @notice Gets info about the pool's reserves and other state that is
    ///         important to evaluate potential trades.
    /// @return The pool info.
    function getPoolInfo() external view returns (IHyperdrive.PoolInfo memory) {
        uint256 vaultSharePrice = _pricePerVaultShare();
        uint256 lpTotalSupply = _totalSupply[AssetId._LP_ASSET_ID] +
            _totalSupply[AssetId._WITHDRAWAL_SHARE_ASSET_ID] -
            _withdrawPool.readyToWithdraw;
        uint256 presentValue = vaultSharePrice > 0
            ? LPMath
                .calculatePresentValue(_getPresentValueParams(vaultSharePrice))
                .mulDown(vaultSharePrice)
            : 0;
        IHyperdrive.PoolInfo memory poolInfo = IHyperdrive.PoolInfo({
            shareReserves: _marketState.shareReserves,
            shareAdjustment: _marketState.shareAdjustment,
            zombieBaseProceeds: _marketState.zombieBaseProceeds,
            zombieShareReserves: _marketState.zombieShareReserves,
            bondReserves: _marketState.bondReserves,
            vaultSharePrice: vaultSharePrice,
            longsOutstanding: _marketState.longsOutstanding,
            longAverageMaturityTime: _marketState.longAverageMaturityTime,
            shortsOutstanding: _marketState.shortsOutstanding,
            shortAverageMaturityTime: _marketState.shortAverageMaturityTime,
            lpTotalSupply: lpTotalSupply,
            lpSharePrice: lpTotalSupply == 0
                ? 0
                : presentValue.divDown(lpTotalSupply),
            withdrawalSharesReadyToWithdraw: _withdrawPool.readyToWithdraw,
            withdrawalSharesProceeds: _withdrawPool.proceeds,
            longExposure: _marketState.longExposure
        });
        _revert(abi.encode(poolInfo));
    }

    /// @notice Gets information about the withdrawal pool.
    /// @return Hyperdrive's withdrawal pool information.
    function getWithdrawPool()
        external
        view
        returns (IHyperdrive.WithdrawPool memory)
    {
        _revert(
            abi.encode(
                IHyperdrive.WithdrawPool({
                    readyToWithdraw: _withdrawPool.readyToWithdraw,
                    proceeds: _withdrawPool.proceeds
                })
            )
        );
    }

    /// @notice Gets info about the fees presently accrued by the pool.
    /// @return Governance fees denominated in shares yet to be collected.
    function getUncollectedGovernanceFees() external view returns (uint256) {
        _revert(abi.encode(_governanceFeesAccrued));
    }

    /// @notice Gets the market state.
    /// @return The market state.
    function getMarketState()
        external
        view
        returns (IHyperdrive.MarketState memory)
    {
        _revert(abi.encode(_marketState));
    }

    /// @notice Allows plugin data libs to provide getters or other complex
    ///         logic instead of the main.
    /// @param _slots The storage slots the caller wants the data from.
    /// @return A raw array of loaded data.
    function load(
        uint256[] calldata _slots
    ) external view returns (bytes32[] memory) {
        bytes32[] memory loaded = new bytes32[](_slots.length);

        // Iterate on requested loads and then do them.
        for (uint256 i = 0; i < _slots.length; ) {
            uint256 slot = _slots[i];
            bytes32 data;
            assembly ("memory-safe") {
                data := sload(slot)
            }
            loaded[i] = data;
            unchecked {
                ++i;
            }
        }

        _revert(abi.encode(loaded));
    }

    /// @notice Gets an account's balance of a sub-token.
    /// @param tokenId The sub-token id.
    /// @param account The account.
    /// @return The balance.
    function balanceOf(
        uint256 tokenId,
        address account
    ) external view returns (uint256) {
        _revert(abi.encode(_balanceOf[tokenId][account]));
    }

    /// @notice Gets the total supply of a sub-token.
    /// @param tokenId The sub-token id.
    /// @return The total supply.
    function totalSupply(uint256 tokenId) external view returns (uint256) {
        _revert(abi.encode(_totalSupply[tokenId]));
    }

    /// @notice Gets the approval status of an operator for an account.
    /// @param account The account.
    /// @param operator The operator.
    /// @return The approval status.
    function isApprovedForAll(
        address account,
        address operator
    ) external view returns (bool) {
        _revert(abi.encode(_isApprovedForAll[account][operator]));
    }

    /// @notice Gets the approval status of an operator for an account.
    /// @param tokenId The sub-token id.
    /// @param account The account.
    /// @param spender The spender.
    /// @return The approval status.
    function perTokenApprovals(
        uint256 tokenId,
        address account,
        address spender
    ) external view returns (uint256) {
        _revert(abi.encode(_perTokenApprovals[tokenId][account][spender]));
    }

    /// @notice Gets the decimals of the MultiToken. This is the same as the
    ///         decimals used by the base token.
    /// @return The decimals of the MultiToken.
    function decimals() external view virtual returns (uint8) {
        _revert(abi.encode(_baseToken.decimals()));
    }

    /// @notice Gets the name of a sub-token.
    /// @param tokenId The sub-token id.
    /// @return The name.
    function name(uint256 tokenId) external pure returns (string memory) {
        _revert(abi.encode(AssetId.assetIdToName(tokenId)));
    }

    /// @notice Gets the symbol of a sub-token.
    /// @param tokenId The sub-token id.
    /// @return The symbol.
    function symbol(uint256 tokenId) external pure returns (string memory) {
        _revert(abi.encode(AssetId.assetIdToSymbol(tokenId)));
    }

    /// @notice Gets the permitForAll signature nonce for an account.
    /// @param account The account.
    /// @return The signature nonce.
    function nonces(address account) external view returns (uint256) {
        _revert(abi.encode(_nonces[account]));
    }

    /// Helpers ///

    /// @dev Reverts with the provided bytes. This is useful in getters used
    ///      with the force-revert delegatecall pattern.
    /// @param _bytes The bytes to revert with.
    function _revert(bytes memory _bytes) internal pure {
        revert IHyperdrive.ReturnData(_bytes);
    }
}
