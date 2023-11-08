// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveCore } from "../interfaces/IHyperdriveCore.sol";
import { HyperdriveAdmin } from "../internal/HyperdriveAdmin.sol";
import { HyperdriveBase } from "../internal/HyperdriveBase.sol";
import { HyperdriveCheckpoint } from "../internal/HyperdriveCheckpoint.sol";
import { HyperdriveLong } from "../internal/HyperdriveLong.sol";
import { HyperdriveLP } from "../internal/HyperdriveLP.sol";
import { HyperdrivePermitForAll } from "../internal/HyperdrivePermitForAll.sol";
import { HyperdriveShort } from "../internal/HyperdriveShort.sol";
import { HyperdriveStorage } from "../internal/HyperdriveStorage.sol";

// FIXME: This should implement an interface
//
// FIXME: Natspec
abstract contract Hyperdrive is
    IHyperdriveCore,
    HyperdrivePermitForAll,
    HyperdriveAdmin,
    HyperdriveLP,
    HyperdriveLong,
    HyperdriveShort,
    HyperdriveCheckpoint
{
    // FIXME: Natspec.
    //
    /// @notice The address of the extras contract.
    address public immutable target0;
    address public immutable target1;

    // FIXME: Natspec
    /// @notice Instantiates a Hyperdrive pool.
    /// @param _config The configuration of the pool.
    /// @param _target0 FIXME
    /// @param _target1 FIXME
    /// @param _linkerCodeHash The code hash of the linker contract.
    /// @param _linkerFactory The address of the linker factory.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _target0,
        address _target1,
        bytes32 _linkerCodeHash,
        address _linkerFactory
    )
        HyperdriveStorage(_config, _linkerCodeHash, _linkerFactory)
        HyperdrivePermitForAll()
    {
        // Initialize the target contracts.
        target0 = _target0;
        target1 = _target1;
    }

    // solhint-disable no-complex-fallback
    /// @notice If we get to the fallback function, we make a read-only
    ///         delegatecall to the target0 contract. This target contains all
    ///         of the getters for the Hyperdrive pool.
    /// @param _data The data to be passed to the data provider.
    /// @return The return data from the data provider.
    fallback(bytes calldata _data) external returns (bytes memory) {
        // We use a force-revert delegatecall pattern to ensure that no state
        // changes were made during the read call.
        // solhint-disable avoid-low-level-calls
        (bool success, bytes memory returndata) = target0.delegatecall(_data);
        if (success) {
            revert IHyperdrive.UnexpectedSuccess();
        }
        bytes4 selector = bytes4(returndata);
        if (selector != IHyperdrive.ReturnData.selector) {
            assembly {
                revert(add(returndata, 32), mload(returndata))
            }
        }

        // Read calls return their data inside of a `ReturnData(bytes)` error.
        // We unwrap the error and return the contents.
        assembly {
            mstore(add(returndata, 0x4), sub(mload(returndata), 4))
            returndata := add(returndata, 0x4)
        }
        returndata = abi.decode(returndata, (bytes));

        return returndata;
    }

    /// Longs ///

    /// @notice Opens a long position.
    /// @param _baseAmount The amount of base to use when trading.
    /// @param _minOutput The minium number of bonds to receive.
    /// @param _minSharePrice The minium share price at which to open the long.
    ///        This allows traders to protect themselves from opening a long in
    ///        a checkpoint where negative interest has accrued.
    /// @param _options The options that configure how the trade is settled.
    /// @return maturityTime The maturity time of the bonds.
    /// @return bondProceeds The amount of bonds the user received
    function openLong(
        uint256 _baseAmount,
        uint256 _minOutput,
        uint256 _minSharePrice,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256 maturityTime, uint256 bondProceeds) {
        return _openLong(_baseAmount, _minOutput, _minSharePrice, _options);
    }

    /// @notice Closes a long position with a specified maturity time.
    function closeLong(
        uint256,
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external returns (uint256) {
        _delegate(target1);
    }

    /// Shorts ///

    /// @notice Opens a short position.
    /// @param _bondAmount The amount of bonds to short.
    /// @param _maxDeposit The most the user expects to deposit for this trade
    /// @param _minSharePrice The minium share price at which to open the long.
    ///        This allows traders to protect themselves from opening a long in
    ///        a checkpoint where negative interest has accrued.
    /// @param _options The options that configure how the trade is settled.
    /// @return maturityTime The maturity time of the short.
    /// @return traderDeposit The amount the user deposited for this trade.
    function openShort(
        uint256 _bondAmount,
        uint256 _maxDeposit,
        uint256 _minSharePrice,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256 maturityTime, uint256 traderDeposit) {
        return _openShort(_bondAmount, _maxDeposit, _minSharePrice, _options);
    }

    /// @notice Closes a short position with a specified maturity time.
    function closeShort(
        uint256,
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external returns (uint256) {
        _delegate(target1);
    }

    /// LPs ///

    /// @notice Allows the first LP to initialize the market with a target APR.
    /// @return The initial number of LP shares created.
    function initialize(
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external payable returns (uint256) {
        _delegate(target1);
    }

    /// @notice Allows LPs to supply liquidity for LP shares.
    function addLiquidity(
        uint256,
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external payable returns (uint256) {
        _delegate(target1);
    }

    // FIXME: Natspec
    function removeLiquidity(
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external returns (uint256, uint256) {
        _delegate(target1);
    }

    // FIXME: Natspec
    function redeemWithdrawalShares(
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external returns (uint256, uint256) {
        _delegate(target1);
    }

    /// Checkpoints ///

    // FIXME: Comment this.
    function checkpoint(uint256) external {
        _delegate(target1);
    }

    /// Admin ///

    /// @notice This function collects the governance fees accrued by the pool.
    /// @return proceeds The amount of base collected.
    function collectGovernanceFee(
        IHyperdrive.Options calldata
    ) external returns (uint256) {
        _delegate(target0);
    }

    /// @notice Allows an authorized address to pause this contract.
    function pause(bool) external {
        _delegate(target0);
    }

    /// @notice Allows governance to change governance.
    function setGovernance(address) external {
        _delegate(target0);
    }

    /// @notice Allows governance to change the pauser status of an address.
    function setPauser(address, bool) external {
        _delegate(target0);
    }

    /// Token ///

    /// @notice Transfers an amount of assets from the source to the destination.
    function transferFrom(uint256, address, address, uint256) external {
        _delegate(target0);
    }

    /// @notice Permissioned transfer for the bridge to access, only callable by
    ///         the ERC20 linking bridge.
    function transferFromBridge(
        uint256,
        address,
        address,
        uint256,
        address
    ) external {
        _delegate(target0);
    }

    /// @notice Allows the compatibility linking contract to forward calls to
    ///         set asset approvals.
    function setApprovalBridge(uint256, address, uint256, address) external {
        _delegate(target0);
    }

    /// @notice Allows a user to approve an operator to use all of their assets.
    function setApprovalForAll(address, bool) external {
        _delegate(target0);
    }

    /// @notice Allows a user to set an approval for an individual asset with
    ///         specific amount.
    function setApproval(uint256, address, uint256) external {
        _delegate(target0);
    }

    /// @notice Transfers several assets from one account to another
    function batchTransferFrom(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata
    ) external {
        _delegate(target0);
    }

    /// MultiToken ///

    /// @notice Allows a caller who is not the owner of an account to execute the
    ///      functionality of 'approve' for all assets with the owners signature.
    /// @param owner The owner of the account which is having the new approval set.
    /// @param spender The address which will be allowed to spend owner's tokens
    /// @param _approved A boolean of the approval status to set to
    /// @param deadline The timestamp which the signature must be submitted by
    ///        to be valid.
    /// @param v Extra ECDSA data which allows public key recovery from
    ///        signature assumed to be 27 or 28.
    /// @param r The r component of the ECDSA signature
    /// @param s The s component of the ECDSA signature
    /// @dev The signature for this function follows EIP 712 standard and should
    ///      be generated with the eth_signTypedData JSON RPC call instead of
    ///      the eth_sign JSON RPC call. If using out of date parity signing
    ///      libraries the v component may need to be adjusted. Also it is very
    ///      rare but possible for v to be other values, those values are not
    ///      supported.
    function permitForAll(
        address owner,
        address spender,
        bool _approved,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _permitForAll(owner, spender, _approved, deadline, v, r, s);
    }

    /// Helpers ///

    /// @dev Makes a delegatecall to the extras contract with the provided
    ///      calldata. This will revert if the call is unsuccessful.
    /// @param _target The target of the delegatecall.
    /// @return The returndata of the delegatecall.
    function _delegate(address _target) internal returns (bytes memory) {
        (bool success, bytes memory result) = _target.delegatecall(msg.data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        assembly {
            return(add(result, 32), mload(result))
        }
    }
}
