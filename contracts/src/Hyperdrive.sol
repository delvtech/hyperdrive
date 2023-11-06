// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { HyperdriveAdmin } from "./HyperdriveAdmin.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";
import { HyperdriveCheckpoint } from "./HyperdriveCheckpoint.sol";
import { HyperdriveLong } from "./HyperdriveLong.sol";
import { HyperdriveLP } from "./HyperdriveLP.sol";
import { HyperdriveShort } from "./HyperdriveShort.sol";

// FIXME: This should implement an interface
//
// FIXME: Natspec
abstract contract Hyperdrive is
    HyperdriveBase,
    HyperdriveAdmin,
    HyperdriveLP,
    HyperdriveLong,
    HyperdriveShort,
    HyperdriveCheckpoint
{
    /// @notice The address of the extras contract.
    address public immutable extras;

    // FIXME: Natspec
    /// @notice Instantiates a Hyperdrive pool.
    /// @param _config The configuration of the pool.
    /// @param _extras The address of the extras contract.
    /// @param _dataProvider The address of the data provider.
    /// @param _linkerCodeHash The code hash of the linker contract.
    /// @param _linkerFactory The address of the linker factory.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _extras,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory
    ) HyperdriveBase(_config, _dataProvider, _linkerCodeHash, _linkerFactory) {
        extras = _extras;
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
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of longs to close.
    /// @param _minOutput The minimum amount of base the trader will accept.
    /// @param _options The options that configure how the trade is settled.
    /// @return The amount of underlying the user receives.
    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) external returns (uint256) {
        return _closeLong(_maturityTime, _bondAmount, _minOutput, _options);
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
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of shorts to close.
    /// @param _minOutput The minimum output of this trade.
    /// @param _options The options that configure how the trade is settled.
    /// @return The amount of base tokens produced by closing this short
    function closeShort(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) external returns (uint256) {
        return _closeShort(_maturityTime, _bondAmount, _minOutput, _options);
    }

    /// LPs ///

    /// @notice Allows the first LP to initialize the market with a target APR.
    /// @param _contribution The amount of base to supply.
    /// @param _apr The target APR.
    /// @param _options The options that configure how the operation is settled.
    /// @return lpShares The initial number of LP shares created.
    function initialize(
        uint256 _contribution,
        uint256 _apr,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256 lpShares) {
        return _initialize(_contribution, _apr, _options);
    }

    /// @notice Allows LPs to supply liquidity for LP shares.
    /// @param _contribution The amount of base to supply.
    /// @param _minApr The minimum APR at which the LP is willing to supply.
    /// @param _maxApr The maximum APR at which the LP is willing to supply.
    /// @param _options The options that configure how the operation is settled.
    /// @return lpShares The number of LP tokens created
    function addLiquidity(
        uint256 _contribution,
        uint256 _minApr,
        uint256 _maxApr,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256 lpShares) {
        return _addLiquidity(_contribution, _minApr, _maxApr, _options);
    }

    function removeLiquidity(
        uint256 _shares,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) external returns (uint256 baseProceeds, uint256 withdrawalShares) {
        return _removeLiquidity(_shares, _minOutput, _options);
    }

    function redeemWithdrawalShares(
        uint256 _shares,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) external returns (uint256 proceeds, uint256 sharesRedeemed) {
        return _redeemWithdrawalShares(_shares, _minOutput, _options);
    }

    /// Checkpoints ///

    function checkpoint(uint256 _checkpointTime) external {
        _checkpoint(_checkpointTime);
    }

    /// Admin ///

    /// @notice This function collects the governance fees accrued by the pool.
    /// @return proceeds The amount of base collected.
    function collectGovernanceFee(
        IHyperdrive.Options calldata
    ) external returns (uint256 proceeds) {
        // FIXME: DRY This up into a function.
        (bool success, bytes memory result) = extras.delegatecall(msg.data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        return abi.decode(result, (uint256));
    }

    /// @notice Allows an authorized address to pause this contract.
    function pause(bool) external {
        // FIXME: DRY This up into a function.
        (bool success, bytes memory result) = extras.delegatecall(msg.data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @notice Allows governance to change governance.
    function setGovernance(address) external {
        // FIXME: DRY This up into a function.
        (bool success, bytes memory result) = extras.delegatecall(msg.data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @notice Allows governance to change the pauser status of an address.
    function setPauser(address, bool) external {
        // FIXME: DRY This up into a function.
        (bool success, bytes memory result) = extras.delegatecall(msg.data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// Token ///

    /// @notice Transfers an amount of assets from the source to the destination.
    function transferFrom(uint256, address, address, uint256) external {
        // FIXME: DRY This up into a function.
        (bool success, bytes memory result) = extras.delegatecall(msg.data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
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
        // FIXME: DRY This up into a function.
        (bool success, bytes memory result) = extras.delegatecall(msg.data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @notice Allows the compatibility linking contract to forward calls to
    ///         set asset approvals.
    function setApprovalBridge(
        uint256,
        address,
        uint256,
        address
    ) external override {
        // FIXME: DRY This up into a function.
        (bool success, bytes memory result) = extras.delegatecall(msg.data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @notice Allows a user to approve an operator to use all of their assets.
    function setApprovalForAll(address, bool) external override {
        // FIXME: DRY This up into a function.
        (bool success, bytes memory result) = extras.delegatecall(msg.data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @notice Allows a user to set an approval for an individual asset with
    ///         specific amount.
    function setApproval(uint256, address, uint256) external override {
        // FIXME: DRY This up into a function.
        (bool success, bytes memory result) = extras.delegatecall(msg.data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @notice Transfers several assets from one account to another
    function batchTransferFrom(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata
    ) external {
        // FIXME: DRY This up into a function.
        (bool success, bytes memory result) = extras.delegatecall(msg.data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @notice Allows a caller who is not the owner of an account to execute the
    ///      functionality of 'approve' for all assets with the owners signature.
    function permitForAll(
        address,
        address,
        bool,
        uint256,
        uint8,
        bytes32,
        bytes32
    ) external {
        // FIXME: DRY This up into a function.
        (bool success, bytes memory result) = extras.delegatecall(msg.data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
