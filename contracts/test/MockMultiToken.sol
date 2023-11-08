// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { IERC20 } from "../src/interfaces/IERC20.sol";
import { IHyperdrive } from "../src/interfaces/IHyperdrive.sol";
import { IMultiToken } from "../src/interfaces/IMultiToken.sol";
import { HyperdriveMultiToken } from "../src/internal/HyperdriveMultiToken.sol";
import { HyperdriveStorage } from "../src/internal/HyperdriveStorage.sol";
import { MockHyperdriveBase, MockHyperdriveTarget0 } from "./MockHyperdrive.sol";

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

    constructor(
        bytes32 _linkerCodeHash,
        address _linkerFactory
    )
        HyperdriveStorage(
            IHyperdrive.PoolConfig({
                baseToken: IERC20(address(0)),
                initialSharePrice: 1e18,
                minimumShareReserves: 1e18,
                minimumTransactionAmount: 1e15,
                positionDuration: 365 days,
                checkpointDuration: 1 days,
                timeStretch: HyperdriveUtils.calculateTimeStretch(0.05e18),
                governance: address(0),
                feeCollector: address(0),
                fees: IHyperdrive.Fees({ curve: 0, flat: 0, governance: 0 })
            }),
            _linkerCodeHash,
            _linkerFactory
        )
    {
        target0 = address(
            new MockHyperdriveTarget0(
                IHyperdrive.PoolConfig({
                    baseToken: IERC20(address(0)),
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e18,
                    minimumTransactionAmount: 1e15,
                    positionDuration: 365 days,
                    checkpointDuration: 1 days,
                    timeStretch: HyperdriveUtils.calculateTimeStretch(0.05e18),
                    governance: address(0),
                    feeCollector: address(0),
                    fees: IHyperdrive.Fees({ curve: 0, flat: 0, governance: 0 })
                })
            )
        );
    }

    // solhint-disable no-complex-fallback
    //
    // NOTE: We delegate read and write access to the target0 contract. This
    // target includes all of the read and write functions for the multi-token.
    fallback(bytes calldata _data) external returns (bytes memory) {
        // We use a force-revert delegatecall pattern to ensure that no state
        // changes were made during the read call.
        // solhint-disable avoid-low-level-calls
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
