// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget0 } from "contracts/src/external/HyperdriveTarget0.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IMultiToken } from "contracts/src/interfaces/IMultiToken.sol";
import { HyperdriveMultiToken } from "contracts/src/internal/HyperdriveMultiToken.sol";
import { HyperdriveStorage } from "contracts/src/internal/HyperdriveStorage.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { MockHyperdriveBase, MockHyperdriveTarget0 } from "contracts/test/MockHyperdrive.sol";

/// DEPRECATED: Don't use this for new tests.
interface IMockMultiToken is IMultiToken {
    function __setBalanceOf(
        uint256 _tokenId,
        address _who,
        uint256 _amount
    ) external;

    function __external_transferFrom(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount,
        address caller
    ) external;

    function mint(uint256 tokenID, address to, uint256 amount) external;

    function burn(uint256 tokenID, address from, uint256 amount) external;
}

contract MockMultiToken is HyperdriveMultiToken, MockHyperdriveBase {
    address internal immutable target0;

    /// @notice The typehash used to calculate the EIP712 hash for `permitForAll`.
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "PermitForAll(address owner,address spender,bool _approved,uint256 nonce,uint256 deadline)"
        );

    /// @notice This contract's EIP712 domain separator.
    bytes32 public immutable domainSeparator; // solhint-disable-line var-name-mixedcase

    constructor(
        bytes32 _linkerCodeHash,
        address _linkerFactory
    )
        HyperdriveStorage(
            IHyperdrive.PoolConfig({
                baseToken: IERC20(address(0)),
                vaultSharesToken: IERC20(address(0)),
                linkerFactory: _linkerFactory,
                linkerCodeHash: _linkerCodeHash,
                initialVaultSharePrice: 1e18,
                minimumShareReserves: 1e18,
                minimumTransactionAmount: 1e15,
                positionDuration: 365 days,
                checkpointDuration: 1 days,
                timeStretch: HyperdriveMath.calculateTimeStretch(
                    0.05e18,
                    365 days
                ),
                governance: address(0),
                feeCollector: address(0),
                sweepCollector: address(0),
                fees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                })
            })
        )
    {
        // Deploy the target0 contract.
        target0 = address(
            new MockHyperdriveTarget0(
                IHyperdrive.PoolConfig({
                    baseToken: IERC20(address(0)),
                    vaultSharesToken: IERC20(address(0)),
                    linkerFactory: _linkerFactory,
                    linkerCodeHash: _linkerCodeHash,
                    initialVaultSharePrice: 1e18,
                    minimumShareReserves: 1e18,
                    minimumTransactionAmount: 1e15,
                    positionDuration: 365 days,
                    checkpointDuration: 1 days,
                    timeStretch: HyperdriveMath.calculateTimeStretch(
                        0.05e18,
                        365 days
                    ),
                    governance: address(0),
                    feeCollector: address(0),
                    sweepCollector: address(0),
                    fees: IHyperdrive.Fees({
                        curve: 0,
                        flat: 0,
                        governanceLP: 0,
                        governanceZombie: 0
                    })
                })
            )
        );

        // NOTE: It's convenient to keep this in the `Hyperdrive.sol`
        //       entry-point to avoiding issues with initializing the domain
        //       separator with the contract address. If this is moved to one of
        //       the targets, the domain separator will need to be computed
        //       differently.
        domainSeparator = keccak256(
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

    // NOTE: We delegate read and write access to the target0 contract. This
    // target includes all of the read and write functions for the multi-token.
    fallback(bytes calldata _data) external returns (bytes memory) {
        // We use a force-revert delegatecall pattern to ensure that no state
        // changes were made during the read call.
        (bool success, bytes memory returndata) = target0.delegatecall(_data);
        if (!success) {
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

        return returndata;
    }

    /// Overrides ///

    // HACK: This is a hack to get around the fact that MockHyperdriveBase
    // needs this to be defined.
    function _applyCheckpoint(
        uint256,
        uint256
    ) internal pure override returns (uint256) {
        return 0;
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
                    domainSeparator,
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

    /// Mocks ///

    function __setBalanceOf(
        uint256 _tokenId,
        address _who,
        uint256 _amount
    ) external {
        _balanceOf[_tokenId][_who] = _amount;
    }

    function __external_transferFrom(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount,
        address caller
    ) external {
        _transferFrom(tokenID, from, to, amount, caller);
    }

    function mint(uint256 tokenID, address to, uint256 amount) external {
        _mint(tokenID, to, amount);
    }

    function burn(uint256 tokenID, address from, uint256 amount) external {
        _burn(tokenID, from, amount);
    }
}
