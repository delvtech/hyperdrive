// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveTarget0 } from "../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveCore } from "../interfaces/IHyperdriveCore.sol";
import { HyperdriveAdmin } from "../internal/HyperdriveAdmin.sol";
import { HyperdriveBase } from "../internal/HyperdriveBase.sol";
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
///     ############   XXXXX        ++@+        +@++        XXXXX   ###########     
///   ##////////////########       ++@@++      ++@@++       ########///////////##   
///  ##////////////##########      ++@@@++    ++@@@++      ##########///////////## 
///  ##%%%%%%/////      ######     ++@@@0+    +0@@@++     ######     /////%%%%%%## 
///    %%%%%%%%&&             ##   ++@@@@+    +@@@@++   ##           &&%%%%%%%%%    
///         %&&&                ##  +o@@0+    +0@@o+  ##              &&&%               
///                              ## ++@@+-    -+@@++ ##                             
///                               #% ++0+      +0++ %#                              
///                               ###-:Oo.++++.oO:-###                  
///                                ##: @@++++++@@ :##                               
///                    #S###########* @++@0+++0@++@ *##########S#                   
///                  #S               % $ @+++@ $ %              S#                 
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
    ///         tateful functions.
    address public immutable target3;

    /// @notice The typehash used to calculate the EIP712 hash for `permitForAll`.
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "PermitForAll(address owner,address spender,bool _approved,uint256 nonce,uint256 deadline)"
        );

    /// @notice This contract's EIP712 domain separator.
    bytes32 public immutable DOMAIN_SEPARATOR; // solhint-disable-line var-name-mixedcase

    /// @notice Instantiates a Hyperdrive pool.
    /// @param _config The configuration of the pool.
    /// @param _target0 The target0 address.
    /// @param _target1 The target1 address.
    /// @param _target2 The target2 address.
    /// @param _target3 The target3 address.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _target0,
        address _target1,
        address _target2,
        address _target3
    ) HyperdriveStorage(_config) {
        // Initialize the target contracts.
        target0 = _target0;
        target1 = _target1;
        target2 = _target2;
        target3 = _target3;

        // NOTE: It's convenient to keep this in the `Hyperdrive.sol`
        //       entry-point to avoiding issues with initializing the domain
        //       separator with the contract address. If this is moved to one of
        //       the targets, the domain separator will need to be computed
        //       differently.
        DOMAIN_SEPARATOR = keccak256(
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

    /// @notice Opens a long position.
    function openLong(
        uint256,
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external payable returns (uint256, uint256) {
        _delegate(target2);
    }

    /// @notice Closes a long position with a specified maturity time.
    function closeLong(
        uint256,
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external returns (uint256) {
        _delegate(target3);
    }

    /// Shorts ///

    /// @notice Opens a short position.
    function openShort(
        uint256,
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external payable returns (uint256, uint256) {
        _delegate(target2);
    }

    /// @notice Closes a short position with a specified maturity time.
    function closeShort(
        uint256,
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external returns (uint256) {
        _delegate(target3);
    }

    /// LPs ///

    /// @notice Allows the first LP to initialize the market with a target APR.
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
        uint256,
        IHyperdrive.Options calldata
    ) external payable returns (uint256) {
        _delegate(target1);
    }

    /// @notice Allows an LP to burn shares and withdraw from the pool.
    function removeLiquidity(
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external returns (uint256, uint256) {
        _delegate(target1);
    }

    /// @notice Redeems withdrawal shares by giving the LP a pro-rata amount of
    ///         the withdrawal pool's proceeds. This function redeems the
    ///         maximum amount of the specified withdrawal shares given the
    ///         amount of withdrawal shares ready to withdraw.
    function redeemWithdrawalShares(
        uint256,
        uint256,
        IHyperdrive.Options calldata
    ) external returns (uint256, uint256) {
        _delegate(target1);
    }

    /// Checkpoints ///

    /// @notice Allows anyone to mint a new checkpoint.
    function checkpoint(uint256) external {
        _delegate(target3);
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
                    DOMAIN_SEPARATOR,
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
