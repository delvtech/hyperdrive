// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";

contract ReentrantEthReceiver {
    uint256 callDepth;
    address internal target;
    bytes internal data;

    receive() external payable {
        if (callDepth++ == 0) {
            (bool success, ) = target.call(data);
            if (!success) {
                revert("ReentrantEthReceiver: call failed");
            }
        }
    }

    function setTarget(address _target) external {
        target = _target;
    }

    function setData(bytes calldata _data) external {
        data = _data;
    }
}

contract ReentrantERC20 is ERC20Mintable {
    uint256 callDepth;
    address internal target;
    bytes internal data;

    function setTarget(address _target) external {
        target = _target;
    }

    function setData(bytes calldata _data) external {
        data = _data;
    }

    function _afterTokenTransfer(address, address, uint256) internal override {
        if (callDepth++ == 0) {
            (bool success, ) = target.call(data);
            if (!success) {
                revert("ReentrantERC20: call failed");
            }
        }
    }
}

// FIXME:
//
// [ ] Add reentrancy tests for ERC20
// [ ] Add reentrancy tests for ETH
contract ReentrancyTest is HyperdriveTest {
    function setUp() public override {
        super.setUp();

        // Deploy a reentrant ERC20.
        baseToken = new ReentrantERC20();
    }
}
