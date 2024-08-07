// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdError } from "forge-std/StdError.sol";
import { ReentrancyGuard } from "openzeppelin/utils/ReentrancyGuard.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { ETH } from "../../../contracts/src/libraries/Constants.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract ReentrancyTester {
    using Lib for *;

    // State that determines the target of the reentrant call and the data that
    // will be used.
    address internal _target;
    bytes internal _data;

    // A boolean flag indicating whether or not the test passes.
    bool public isSuccess;

    function setTarget(address _target_) external {
        _target = _target_;
    }

    function setData(bytes calldata _data_) external {
        _data = _data_;
    }

    function _testReentrancy() internal {
        (bool success, bytes memory data) = _target.call(_data);
        if (
            !success &&
            data.eq(
                abi.encodeWithSelector(
                    ReentrancyGuard.ReentrancyGuardReentrantCall.selector
                )
            )
        ) {
            isSuccess = true;
        }
    }
}

contract ReentrantEthReceiver is ReentrancyTester {
    receive() external payable {
        // If the target calls this token, make a reentrant call and verify
        // that it fails with the correct error.
        if (msg.sender == _target) {
            _testReentrancy();
        }
    }
}

contract ReentrantERC20 is ERC20Mintable, ReentrancyTester {
    constructor()
        ERC20Mintable(
            "ReentrantERC20",
            "REENT",
            18,
            address(0),
            false,
            type(uint256).max
        )
    {}

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        super.transfer(to, amount);

        // If the target calls this token, make a reentrant call and verify
        // that it fails with the correct error.
        if (msg.sender == _target) {
            _testReentrancy();
        }

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        super.transferFrom(from, to, amount);

        // If the target calls this token, make a reentrant call and verify
        // that it fails with the correct error.
        if (msg.sender == _target) {
            _testReentrancy();
        }

        return true;
    }
}

// This test suite validates that Hyperdrive's core functions cannot be reentered.
contract ReentrancyTest is HyperdriveTest {
    ReentrancyTester tester;

    uint256 internal constant CONTRIBUTION = 1_000e18;
    uint256 internal constant FIXED_RATE = 0.05e18;
    uint256 internal constant BASE_PAID = 50e18;
    uint256 internal constant BOND_AMOUNT = 50e18;

    /// Test ///

    function test_reentrancy() external {
        // NOTE: The `checkpoint` function isn't used here because it doesn't
        // invoke `_deposit` or `_withdraw`. It is included in the reentrant
        // data to ensure that it can't be called in the middle of another
        // Hyperdrive call.
        function(address, bytes memory) internal[]
            memory assertions = new function(address, bytes memory) internal[](
                8
            );
        assertions[0] = _reenter_initialize;
        assertions[1] = _reenter_addLiquidity;
        assertions[2] = _reenter_removeLiquidity;
        assertions[3] = _reenter_redeemWithdrawalShares;
        assertions[4] = _reenter_openLong;
        assertions[5] = _reenter_closeLong;
        assertions[6] = _reenter_openShort;
        assertions[7] = _reenter_closeShort;

        // Verify that none of the core Hyperdrive functions can be reentered
        // with a reentrant ERC20 token.
        _setUpERC20();
        bytes[] memory data = _generateReentrantData(alice);
        for (uint256 i = 0; i < assertions.length; i++) {
            for (uint256 j = 0; j < data.length; j++) {
                uint256 id = vm.snapshot();
                assertions[i](alice, data[j]);
                vm.revertTo(id);
            }
        }

        // Verify that none of the core Hyperdrive functions can be reentered
        // with a reentrant ETH receiver.
        _setUpETH();
        data = _generateReentrantData(address(tester));
        for (uint256 i = 0; i < assertions.length; i++) {
            for (uint256 j = 0; j < data.length; j++) {
                uint256 id = vm.snapshot();
                assertions[i](address(tester), data[j]);
                vm.revertTo(id);
            }
        }
    }

    /// Helpers ///

    function _generateReentrantData(
        address _trader
    ) internal view returns (bytes[] memory) {
        // Encode the reentrant data. We use reasonable values, but in practice,
        // the calls will fail immediately. With this in mind, the parameters
        // that are used aren't that important.
        bytes[] memory data = new bytes[](9);
        data[0] = abi.encodeCall(
            hyperdrive.initialize,
            (
                CONTRIBUTION,
                FIXED_RATE,
                IHyperdrive.Options({
                    destination: _trader,
                    asBase: true,
                    extraData: new bytes(0)
                })
            )
        );
        data[1] = abi.encodeCall(
            hyperdrive.addLiquidity,
            (
                CONTRIBUTION,
                0,
                0,
                1e18,
                IHyperdrive.Options({
                    destination: _trader,
                    asBase: true,
                    extraData: new bytes(0)
                })
            )
        );
        data[2] = abi.encodeCall(
            hyperdrive.removeLiquidity,
            (
                CONTRIBUTION,
                0,
                IHyperdrive.Options({
                    destination: _trader,
                    asBase: true,
                    extraData: new bytes(0)
                })
            )
        );
        data[3] = abi.encodeCall(
            hyperdrive.redeemWithdrawalShares,
            (
                BOND_AMOUNT,
                0,
                IHyperdrive.Options({
                    destination: _trader,
                    asBase: true,
                    extraData: new bytes(0)
                })
            )
        );
        data[4] = abi.encodeCall(
            hyperdrive.openLong,
            (
                BASE_PAID,
                0,
                0,
                IHyperdrive.Options({
                    destination: _trader,
                    asBase: true,
                    extraData: new bytes(0)
                })
            )
        );
        data[5] = abi.encodeCall(
            hyperdrive.closeLong,
            (
                block.timestamp,
                BOND_AMOUNT,
                0,
                IHyperdrive.Options({
                    destination: _trader,
                    asBase: true,
                    extraData: new bytes(0)
                })
            )
        );
        data[6] = abi.encodeCall(
            hyperdrive.openShort,
            (
                BOND_AMOUNT,
                type(uint256).max,
                0,
                IHyperdrive.Options({
                    destination: _trader,
                    asBase: true,
                    extraData: new bytes(0)
                })
            )
        );
        data[7] = abi.encodeCall(
            hyperdrive.closeShort,
            (
                block.timestamp,
                BOND_AMOUNT,
                0,
                IHyperdrive.Options({
                    destination: _trader,
                    asBase: true,
                    extraData: new bytes(0)
                })
            )
        );
        data[8] = abi.encodeCall(hyperdrive.checkpoint, (block.timestamp, 0));

        return data;
    }

    function _setUpERC20() internal {
        // Deploy a Hyperdrive term with a reentrant ERC20 as the base token.
        vm.startPrank(deployer);
        tester = new ReentrantERC20();
        baseToken = ERC20Mintable(address(tester));
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        config.baseToken = IERC20(address(baseToken));
        deploy(deployer, config);
    }

    function _setUpETH() internal {
        // Deploy a Hyperdrive term with a reentrant ERC20 as the base token.
        vm.startPrank(deployer);
        tester = new ReentrantEthReceiver();
        vm.deal(address(tester), 10_000e18);
        baseToken = ERC20Mintable(address(ETH));
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        config.baseToken = IERC20(address(ETH));
        deploy(deployer, config);
    }

    function _reenter_initialize(address _trader, bytes memory _data) internal {
        // Set up the reentrant call.
        tester.setTarget(address(hyperdrive));
        tester.setData(_data);

        // Ensure that `initialize` can't be reentered.
        initialize(
            _trader,
            FIXED_RATE,
            CONTRIBUTION,
            // NOTE: Depositing 1 wei more than the contribution to ensure that
            // the ETH receiver will receive a refund.
            DepositOverrides({
                asBase: true,
                destination: _trader,
                depositAmount: CONTRIBUTION + 1,
                minSharePrice: 0,
                minSlippage: 0,
                maxSlippage: type(uint256).max,
                extraData: new bytes(0)
            })
        );
        assert(tester.isSuccess());
    }

    function _reenter_addLiquidity(
        address _trader,
        bytes memory _data
    ) internal {
        // Initialize the pool.
        initialize(_trader, FIXED_RATE, CONTRIBUTION);

        // Set up the reentrant call.
        tester.setTarget(address(hyperdrive));
        tester.setData(_data);

        // Ensure that `addLiquidity` can't be reentered.
        addLiquidity(
            _trader,
            CONTRIBUTION,
            // NOTE: Depositing 1 wei more than the contribution to ensure that
            // the ETH receiver will receive a refund.
            DepositOverrides({
                asBase: true,
                destination: _trader,
                depositAmount: CONTRIBUTION + 1,
                minSharePrice: 0,
                minSlippage: 0,
                maxSlippage: type(uint256).max,
                extraData: new bytes(0)
            })
        );
        assert(tester.isSuccess());
    }

    function _reenter_removeLiquidity(
        address _trader,
        bytes memory _data
    ) internal {
        // Initialize the pool.
        uint256 lpShares = initialize(_trader, FIXED_RATE, CONTRIBUTION);

        // Set up the reentrant call.
        tester.setTarget(address(hyperdrive));
        tester.setData(_data);

        // Ensure that `removeLiquidity` can't be reentered.
        removeLiquidity(_trader, lpShares);
        assert(tester.isSuccess());
    }

    function _reenter_redeemWithdrawalShares(
        address _trader,
        bytes memory _data
    ) internal {
        // Initialize the pool.
        uint256 lpShares = initialize(_trader, FIXED_RATE, CONTRIBUTION);

        // Bob opens a short.
        openShort(bob, BOND_AMOUNT);

        // The trader removes their liquidity.
        (, uint256 withdrawalShares) = removeLiquidity(_trader, lpShares);
        assertGt(withdrawalShares, 0);

        // Set up the reentrant call.
        tester.setTarget(address(hyperdrive));
        tester.setData(_data);

        // Ensure that `redeemWithdrawalShares` can't be reentered.
        redeemWithdrawalShares(_trader, withdrawalShares);
        assert(tester.isSuccess());
    }

    function _reenter_openLong(address _trader, bytes memory _data) internal {
        // Initialize the pool.
        initialize(_trader, FIXED_RATE, CONTRIBUTION);

        // Set up the reentrant call.
        tester.setTarget(address(hyperdrive));
        tester.setData(_data);

        // Ensure that `openLong` can't be reentered.
        openLong(
            _trader,
            BASE_PAID,
            // NOTE: Depositing 1 wei more than the base payment to ensure that
            // the ETH receiver will receive a refund.
            DepositOverrides({
                asBase: true,
                destination: _trader,
                depositAmount: BASE_PAID + 1,
                minSharePrice: 0,
                minSlippage: 0,
                maxSlippage: type(uint256).max,
                extraData: new bytes(0)
            })
        );
        assert(tester.isSuccess());
    }

    function _reenter_closeLong(address _trader, bytes memory _data) internal {
        // Initialize the pool and open a long.
        initialize(_trader, FIXED_RATE, CONTRIBUTION);
        (uint256 maturityTime, uint256 bondAmount) = openLong(_trader, 10e18);

        // Set up the reentrant call.
        tester.setTarget(address(hyperdrive));
        tester.setData(_data);

        // Ensure that `closeLong` can't be reentered.
        closeLong(_trader, maturityTime, bondAmount);
        assert(tester.isSuccess());
    }

    function _reenter_openShort(address _trader, bytes memory _data) internal {
        // Initialize the pool.
        initialize(_trader, FIXED_RATE, CONTRIBUTION);

        // Set up the reentrant call.
        tester.setTarget(address(hyperdrive));
        tester.setData(_data);

        // Ensure that `openShort` can't be reentered.
        openShort(
            _trader,
            BOND_AMOUNT,
            // NOTE: Depositing more than the base payment to ensure that the
            // ETH receiver will receive a refund.
            DepositOverrides({
                asBase: true,
                destination: _trader,
                // NOTE: Roughly double deposit amount needed to cover 100% flat fee
                depositAmount: BOND_AMOUNT * 2,
                minSharePrice: 0,
                minSlippage: 0,
                maxSlippage: type(uint256).max,
                extraData: new bytes(0)
            })
        );
        assert(tester.isSuccess());
    }

    function _reenter_closeShort(address _trader, bytes memory _data) internal {
        // Initialize the pool and open a short.
        initialize(_trader, FIXED_RATE, CONTRIBUTION);
        (uint256 maturityTime, ) = openShort(
            _trader,
            BOND_AMOUNT,
            DepositOverrides({
                asBase: true,
                destination: _trader,
                // NOTE: Roughly double deposit amount needed to cover 100% flat fee
                depositAmount: BOND_AMOUNT * 2,
                minSharePrice: 0,
                minSlippage: 0,
                maxSlippage: type(uint256).max,
                extraData: new bytes(0)
            })
        );

        // Set up the reentrant call.
        tester.setTarget(address(hyperdrive));
        tester.setData(_data);

        // Ensure that `closeShort` can't be reentered.
        closeShort(_trader, maturityTime, BOND_AMOUNT);
        assert(tester.isSuccess());
    }
}
