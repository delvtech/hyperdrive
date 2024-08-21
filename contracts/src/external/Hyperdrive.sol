// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "../interfaces/IERC20.sol";
import { HyperdriveTarget0 } from "../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveCore } from "../interfaces/IHyperdriveCore.sol";
import { IMultiTokenCore } from "../interfaces/IMultiTokenCore.sol";
import { HyperdriveAdmin } from "../internal/HyperdriveAdmin.sol";
import { HyperdriveCheckpoint } from "../internal/HyperdriveCheckpoint.sol";
import { HyperdriveLong } from "../internal/HyperdriveLong.sol";
import { HyperdriveLP } from "../internal/HyperdriveLP.sol";
import { HyperdriveShort } from "../internal/HyperdriveShort.sol";
import { HyperdriveStorage } from "../internal/HyperdriveStorage.sol";

///      ______  __                           _________      _____
///      ___  / / /____  ___________________________  /_________(_)__   ______
///      __  /_/ /__  / / /__  __ \  _ \_  ___/  __  /__  ___/_  /__ | / /  _ \
///      _  __  / _  /_/ /__  /_/ /  __/  /   / /_/ / _  /   _  / __ |/ //  __/
///      /_/ /_/  _\__, / _   ___/\___//_/    \__,_/  /_/    /_/  _____/ \___/
///               /____/   /_/
///                     XXX          ++          ++          XXX
///     ############   XXXXX        ++0+        +0++        XXXXX   ###########
///   ##////////////########       ++00++      ++00++       ########///////////##
///  ##////////////##########      ++000++    ++000++      ##########///////////##
///  ##%%%%%%/////      ######     ++0000+    +0000++     ######     /////%%%%%%##
///    %%%%%%%%&&             ##   ++0000+    +0000++   ##           &&%%%%%%%%%
///         %&&&                ##  +o000+    +000o+  ##              &&&%
///                              ## ++00+-    -+00++ ##
///                               #% ++0+      +0++ %#
///                               ###-:Oo.++++.oO:-###
///                                ##: 00++++++00 :##
///                    #S###########* 0++00+++00++0 *##########S#
///                  #S               % $ 0+++0 $ %              S#
///                #S   ----------   %+++++:#:+++++%-----------    S#
///              #S   ------------- %++++: ### :++++%------------    S#
///             S    ---------------%++++*\ | /*++++%-------------     S
///           #S     --------------- %++++ ~W~ ++++%666--o UUUU o-      S#
///         #S?      ---------------  %+++++~+++++%&&&8 o  \  /  o       ?S#
///        ?*????**+++;::,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,::;+++**????*?
///      #?+////////////////////////////////////////////////////////////////+?#
///    #;;;;;//////////////////////////////////////////////////////////////;;;;;#
///  S;;;;;;;;;//////////////////////////////////////////////////////////;;;;;;;;;S
/// /;;;;;;;;;;;///////////////////////////////////////////////////////;;;;;;;;;;;;\
/// |||OOOOOOOO||OOOOOOOO=========== __  ___        ===========OOOOOOOO||OOOOOOOO|||
/// |||OOOOOOOO||OOOOOOOO===========|  \[__ |   \  /===========OOOOOOOO||OOOOOOOO|||
/// |||OOOOOOOO||OOOOOOOO===========|__/[___|___ \/ ===========OOOOOOOO||OOOOOOOO|||
/// ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
/// |||////////000000000000\\\\\\\\|:::::::::::::::|////////00000000000\\\\\\\\\\|||
/// SSS\\\\\\\\000000000000////////|:::::0x666:::::|\\\\\\\\00000000000//////////SSS
/// SSS|||||||||||||||||||||||||||||:::::::::::::::||||||||||||||||||||||||||||||SSS
/// SSSSSSSS|_______________|______________||_______________|______________|SSSSSSSS
/// SSSSSSSS                                                                SSSSSSSS
/// SSSSSSSS                                                                SSSSSSSS
///
/// @author DELV
/// @title Hyperdrive
/// @notice A fixed-rate AMM that mints bonds on demand for longs and shorts.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract Hyperdrive is
    IHyperdriveCore,
    HyperdriveAdmin,
    HyperdriveLP,
    HyperdriveLong,
    HyperdriveShort,
    HyperdriveCheckpoint
{
    /// @notice The target0 address. This is a logic contract that contains all
    ///         of the getters for the Hyperdrive pool as well as some stateful
    ///         functions.
    address public immutable target0;

    /// @notice The target1 address. This is a logic contract that contains
    ///         stateful functions.
    address public immutable target1;

    /// @notice The target2 address. This is a logic contract that contains
    ///         stateful functions.
    address public immutable target2;

    /// @notice The target3 address. This is a logic contract that contains
    ///         stateful functions.
    address public immutable target3;

    /// @notice The target4 address. This is a logic contract that contains
    ///         stateful functions.
    address public immutable target4;

    /// @notice The typehash used to calculate the EIP712 hash for `permitForAll`.
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "PermitForAll(address owner,address spender,bool _approved,uint256 nonce,uint256 deadline)"
        );

    /// @notice Instantiates a Hyperdrive pool.
    /// @param __name The pool's name.
    /// @param _config The configuration of the pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this contract.
    /// @param _target0 The target0 address.
    /// @param _target1 The target1 address.
    /// @param _target2 The target2 address.
    /// @param _target3 The target3 address.
    /// @param _target4 The target4 address.
    constructor(
        string memory __name,
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        address _target0,
        address _target1,
        address _target2,
        address _target3,
        address _target4
    ) HyperdriveStorage(_config, __adminController) {
        // NOTE: This is initialized here rather than in `HyperdriveStorage` to
        // avoid needing to set the name in all of the target contracts. Since
        // this is a storage value, it will still be accessible.
        //
        // Initialize the pool's name.
        _name = __name;

        // Initialize the target contracts.
        target0 = _target0;
        target1 = _target1;
        target2 = _target2;
        target3 = _target3;
        target4 = _target4;
    }

    /// @notice If we get to the fallback function, we make a read-only
    ///         delegatecall to the target0 contract. This target contains all
    ///         of the getters for the Hyperdrive pool.
    /// @param _data The data to be passed to the data provider.
    /// @return The return data from the data provider.
    fallback(bytes calldata _data) external returns (bytes memory) {
        // We use a force-revert delegatecall pattern to ensure that no state
        // changes were made during the read call.
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

    /// @inheritdoc IHyperdriveCore
    function openLong(
        uint256,
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external payable returns (uint256, uint256) {
        _delegate(target2);
    }

    /// @inheritdoc IHyperdriveCore
    function closeLong(
        uint256,
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external returns (uint256) {
        _delegate(target1);
    }

    /// Shorts ///

    /// @inheritdoc IHyperdriveCore
    function openShort(
        uint256,
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external payable returns (uint256, uint256) {
        _delegate(target2);
    }

    /// @inheritdoc IHyperdriveCore
    function closeShort(
        uint256,
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external returns (uint256) {
        _delegate(target1);
    }

    /// LPs ///

    /// @inheritdoc IHyperdriveCore
    function initialize(
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external payable returns (uint256) {
        _delegate(target3);
    }

    /// @inheritdoc IHyperdriveCore
    function addLiquidity(
        uint256,
        uint256,
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external payable returns (uint256) {
        _delegate(target3);
    }

    /// @inheritdoc IHyperdriveCore
    function removeLiquidity(
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external returns (uint256, uint256) {
        _delegate(target4);
    }

    /// @inheritdoc IHyperdriveCore
    function redeemWithdrawalShares(
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external returns (uint256, uint256) {
        _delegate(target4);
    }

    /// Checkpoints ///

    /// @inheritdoc IHyperdriveCore
    function checkpoint(uint256, uint256) external {
        _delegate(target4);
    }

    /// Admin ///

    /// @inheritdoc IHyperdriveCore
    function collectGovernanceFee(
        IHyperdrive.Options calldata
    ) external returns (uint256) {
        _delegate(target0);
    }

    /// @inheritdoc IHyperdriveCore
    function pause(bool) external {
        _delegate(target0);
    }

    /// @inheritdoc IHyperdriveCore
    function setGovernance(address) external {
        _delegate(target0);
    }

    /// @inheritdoc IHyperdriveCore
    function setPauser(address, bool) external {
        _delegate(target0);
    }

    /// @inheritdoc IHyperdriveCore
    function sweep(IERC20) external {
        _delegate(target0);
    }

    /// MultiToken ///

    /// @inheritdoc IMultiTokenCore
    function transferFrom(uint256, address, address, uint256) external {
        _delegate(target0);
    }

    /// @inheritdoc IMultiTokenCore
    function transferFromBridge(
        uint256,
        address,
        address,
        uint256,
        address
    ) external {
        _delegate(target0);
    }

    /// @inheritdoc IMultiTokenCore
    function setApprovalBridge(uint256, address, uint256, address) external {
        _delegate(target0);
    }

    /// @inheritdoc IMultiTokenCore
    function setApprovalForAll(address, bool) external {
        _delegate(target0);
    }

    /// @inheritdoc IMultiTokenCore
    function setApproval(uint256, address, uint256) external {
        _delegate(target0);
    }

    /// @inheritdoc IMultiTokenCore
    function batchTransferFrom(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata
    ) external {
        _delegate(target0);
    }

    /// @notice Allows a caller who is not the owner of an account to execute the
    ///      functionality of 'approve' for all assets with the owners signature.
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
        address owner,
        address spender,
        bool _approved,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        (bool success, bytes memory result) = target0.delegatecall(
            abi.encodeCall(
                HyperdriveTarget0.permitForAll,
                (
                    domainSeparator(),
                    PERMIT_TYPEHASH,
                    owner,
                    spender,
                    _approved,
                    deadline,
                    v,
                    r,
                    s
                )
            )
        );
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        assembly {
            return(add(result, 32), mload(result))
        }
    }

    /// EIP712

    /// @notice Computes the EIP712 domain separator which prevents user signed
    ///         messages for this contract to be replayed in other contracts:
    ///         https://eips.ethereum.org/EIPS/eip-712.
    /// @return The EIP712 domain separator.
    function domainSeparator() public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes("1")),
                    block.chainid,
                    address(this)
                )
            );
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
