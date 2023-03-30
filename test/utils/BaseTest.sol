// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import "forge-std/Vm.sol";

import { Test } from "forge-std/Test.sol";
import { Hyperdrive } from "contracts/src/Hyperdrive.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ERC20PresetFixedSupply } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import { ForwarderFactory } from "contracts/src/ForwarderFactory.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BaseTest is Test {
    using FixedPointMath for uint256;

    ForwarderFactory forwarderFactory;

    address alice;
    address bob;
    address celine;
    address dan;
    address eve;

    address minter;
    address deployer;
    address governance;

    error WhaleBalanceExceeded();
    error WhaleIsContract();

    uint256 mainnetForkId;
    uint256 goerliForkId;

    uint256 __init__; // time setup function was ran

    constructor() {
        // TODO Hide these in environment variables
        mainnetForkId = vm.createFork(
            "https://eth-mainnet.alchemyapi.io/v2/kwjMP-X-Vajdk1ItCfU-56Uaq1wwhamK"
        );
        goerliForkId = vm.createFork(
            "https://eth-goerli.alchemyapi.io/v2/kwjMP-X-Vajdk1ItCfU-56Uaq1wwhamK"
        );
    }

    function setUp() public virtual {
        alice = createUser("alice");
        bob = createUser("bob");
        celine = createUser("celine");
        dan = createUser("dan");
        eve = createUser("eve");

        deployer = createUser("deployer");
        minter = createUser("minter");
        governance = createUser("governance");

        __init__ = block.timestamp;
    }

    modifier __mainnet_fork(uint256 blockNumber) {
        vm.selectFork(mainnetForkId);
        vm.rollFork(blockNumber);

        _;
    }

    modifier __goerli_fork(uint256 blockNumber) {
        vm.selectFork(goerliForkId);
        vm.rollFork(blockNumber);

        _;
    }

    // creates a user
    function createUser(string memory name) public returns (address _user) {
        _user = address(uint160(uint256(keccak256(abi.encode(name)))));
        vm.label(_user, name);
        vm.deal(_user, 10000 ether);
    }

    // (2^32) * 10^8 * 2.5 / 10^18 = ~100%
    // Useful for fuzzing rates
    function scaleRate(uint32 _variableRate) public pure returns (uint256) {
        return uint256(_variableRate).mulDown(10e26).mulDown(2.5e18);
    }

    function whaleTransfer(
        address whale,
        IERC20 token,
        address to
    ) public returns (uint256) {
        return whaleTransfer(whale, token, token.balanceOf(whale), to);
    }

    function whaleTransfer(
        address whale,
        IERC20 token,
        uint256 amount,
        address to
    ) public returns (uint256) {
        uint256 whaleBalance = token.balanceOf(whale);
        if (amount > whaleBalance) revert WhaleBalanceExceeded();
        if (Address.isContract(whale)) revert WhaleIsContract();
        vm.stopPrank();
        vm.startPrank(whale);
        vm.deal(whale, 1 ether);
        token.transfer(to, amount);
        return amount;
    }

    function assertWithDelta(
        uint256 _value,
        int256 _delta,
        uint256 _targetValue
    ) public {
        bool positiveDelta = _delta >= 0;

        if (positiveDelta) {
            assertTrue(
                _targetValue >= _value,
                "_targetValue should be greater than or equal to _value"
            );
        } else {
            assertTrue(
                _value > _targetValue,
                "_targetValue should be less than _value"
            );
        }

        uint256 upperBound = positiveDelta ? _value + uint256(_delta) : _value;
        uint256 lowerBound = !positiveDelta
            ? _value - uint256(-_delta)
            : _value;

        // targetValue must be within the range
        if (_targetValue < lowerBound || _targetValue > upperBound) {
            assertGe(_targetValue, lowerBound, "exceeds lower bound");
            assertLe(_targetValue, upperBound, "exceeds upper bound");
            return;
        }

        // If the delta is positive it indicates the target value is value + delta
        if (positiveDelta) {
            uint256 valueToTarget = _targetValue - _value;
            if (valueToTarget < uint256(_delta)) {
                console2.log(
                    "Precision increased by: %s",
                    uint256(_delta) - valueToTarget
                );
                console2.log("Old Delta: %s", _delta);
                console2.log("New Delta: %s", valueToTarget);
            } else {
                assertEq(
                    upperBound,
                    _targetValue,
                    "expected upperBound to match _targetValue"
                );
            }
        } else {
            uint256 valueToTarget = _value - _targetValue;
            if (valueToTarget < uint256(-_delta)) {
                console2.log(
                    "Precision increased by: %s",
                    uint256(-_delta) - valueToTarget
                );
                console2.log("Old Delta: %s", _delta);
                console2.log("New Delta: -%s", valueToTarget);
            } else {
                assertEq(
                    lowerBound,
                    _targetValue,
                    "expected lowerBound to match _targetValue"
                );
            }
        }
    }
}
