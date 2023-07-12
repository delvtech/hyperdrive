// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

// FIXME
import "forge-std/console.sol";

import { stdError } from "forge-std/StdError.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract ReentrantEthReceiver {
    uint256 callDepth;
    address internal target;
    bytes internal data;

    receive() external payable {
        if (callDepth++ == 0) {
            (bool success, ) = target.call(data);
            assert(!success);
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
    using Lib for *;

    // State that determines the target of the reentrant call and the data that
    // will be used.
    address internal _target;
    bytes internal _data;

    // A boolean flag indicating whether or not the test passes.
    bool public testPassed;

    function setTarget(address _target_) external {
        _target = _target_;
    }

    function setData(bytes calldata _data_) external {
        _data = _data_;
    }

    function _afterTokenTransfer(address, address, uint256) internal override {
        // If the target calls this token, make a reentrant call and verify
        // that it fails with the correct error. This is disabled when the
        // target is zero.
        if (msg.sender == _target) {
            (bool success, bytes memory data) = _target.call(_data);
            if (!success && data.eq("REENTRANCY".toError())) {
                testPassed = true;
            }
        }
    }
}

// FIXME:
//
// [ ] Add reentrancy tests for ERC20
// [ ] Add reentrancy tests for ETH
contract ReentrancyTest is HyperdriveTest {
    ReentrantERC20 reentrantToken;

    function setUp() public override {
        super.setUp();

        // Deploy a Hyperdrive term with a reentrant ERC20 as the base token.
        vm.startPrank(deployer);
        reentrantToken = new ReentrantERC20();
        baseToken = reentrantToken;
        IHyperdrive.PoolConfig memory config = testConfig(0.05e18);
        config.baseToken = IERC20(address(baseToken));
        deploy(deployer, config);
    }

    /// LP ///

    function test_reentrancy_initialize() external {
        // Set up the reentrant call.
        uint256 contribution = 500_000_000e18;
        uint256 fixedRate = 0.02e18;
        reentrantToken.setData(
            abi.encodeCall(
                hyperdrive.initialize,
                (contribution, fixedRate, alice, true)
            )
        );
        reentrantToken.setTarget(address(hyperdrive));

        // Ensure that `initialize` can't be reentered.
        initialize(alice, fixedRate, contribution);
        assert(reentrantToken.testPassed());
    }

    function test_reentrancy_addLiquidity() external {
        // Initialize the pool.
        initialize(alice, 0.02e18, 500_000_000e18);

        // Set up the reentrant call.
        uint256 contribution = 500_000_000e18;
        reentrantToken.setData(
            abi.encodeCall(
                hyperdrive.addLiquidity,
                (contribution, 0, 1e18, alice, true)
            )
        );
        reentrantToken.setTarget(address(hyperdrive));

        // Ensure that `addLiquidity` can't be reentered.
        addLiquidity(alice, contribution);
        assert(reentrantToken.testPassed());
    }

    function test_reentrancy_removeLiquidity() external {
        // Initialize the pool.
        uint256 lpShares = initialize(alice, 0.02e18, 500_000_000e18);

        // Set up the reentrant call.
        reentrantToken.setData(
            abi.encodeCall(
                hyperdrive.removeLiquidity,
                (lpShares, 0, alice, true)
            )
        );
        reentrantToken.setTarget(address(hyperdrive));

        // Ensure that `removeLiquidity` can't be reentered.
        removeLiquidity(alice, lpShares);
        assert(reentrantToken.testPassed());
    }

    function test_reentrancy_redeemWithdrawalShares() external {
        // Initialize the pool.
        uint256 lpShares = initialize(alice, 0.02e18, 500_000_000e18);

        // Bob opens a long.
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, 10e18);

        // Alice removes her liquidity.
        (, uint256 withdrawalShares) = removeLiquidity(alice, lpShares);

        // Bob closes his long.
        closeLong(bob, maturityTime, bondAmount);

        // Set up the reentrant call.
        reentrantToken.setData(
            abi.encodeCall(
                hyperdrive.redeemWithdrawalShares,
                (withdrawalShares, 0, alice, true)
            )
        );
        reentrantToken.setTarget(address(hyperdrive));

        // Ensure that `redeemWithdrawalShares` can't be reentered.
        redeemWithdrawalShares(alice, withdrawalShares);
        assert(reentrantToken.testPassed());
    }

    /// Long ///

    function test_reentrancy_openLong() external {
        // Initialize the pool.
        initialize(alice, 0.02e18, 500_000_000e18);

        // Set up the reentrant call.
        uint256 basePaid = 10e18;
        reentrantToken.setData(
            abi.encodeCall(hyperdrive.openLong, (basePaid, 0, alice, true))
        );
        reentrantToken.setTarget(address(hyperdrive));

        // Ensure that `openLong` can't be reentered.
        openLong(alice, basePaid);
        assert(reentrantToken.testPassed());
    }

    function test_reentrancy_closeLong() external {
        // Initialize the pool and open a long.
        initialize(alice, 0.02e18, 500_000_000e18);
        (uint256 maturityTime, uint256 bondAmount) = openLong(alice, 10e18);

        // Set up the reentrant call.
        reentrantToken.setData(
            abi.encodeCall(
                hyperdrive.closeLong,
                (maturityTime, bondAmount, 0, alice, true)
            )
        );
        reentrantToken.setTarget(address(hyperdrive));

        // Ensure that `closeLong` can't be reentered.
        closeLong(alice, maturityTime, bondAmount);
        assert(reentrantToken.testPassed());
    }

    /// Short ///

    function test_reentrancy_openShort() external {
        // Initialize the pool.
        initialize(alice, 0.02e18, 500_000_000e18);

        // Set up the reentrant call.
        uint256 bondAmount = 10e18;
        reentrantToken.setData(
            abi.encodeCall(
                hyperdrive.openShort,
                (bondAmount, type(uint256).max, alice, true)
            )
        );
        reentrantToken.setTarget(address(hyperdrive));

        // Ensure that `openShort` can't be reentered.
        openShort(alice, bondAmount);
        assert(reentrantToken.testPassed());
    }

    function test_reentrancy_closeShort() external {
        // Initialize the pool and open a short.
        initialize(alice, 0.02e18, 500_000_000e18);
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(alice, bondAmount);

        // Set up the reentrant call.
        reentrantToken.setData(
            abi.encodeCall(
                hyperdrive.closeShort,
                (maturityTime, bondAmount, 0, alice, true)
            )
        );
        reentrantToken.setTarget(address(hyperdrive));

        // Ensure that `closeShort` can't be reentered.
        closeShort(alice, maturityTime, bondAmount);
        assert(reentrantToken.testPassed());
    }
}
