// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import "forge-std/Vm.sol";

import { Test } from "forge-std/Test.sol";
import { Hyperdrive } from "contracts/Hyperdrive.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
import { ERC20PresetFixedSupply } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BaseTest is Test {
    using FixedPointMath for uint256;

    address alice;
    address bob;
    address celine;

    address minter;
    address deployer;

    error WhaleBalanceExceeded();
    error WhaleIsContract();

    uint256 mainnetForkId;

    constructor() {
        mainnetForkId = vm.createFork(
            "https://eth-mainnet.alchemyapi.io/v2/kwjMP-X-Vajdk1ItCfU-56Uaq1wwhamK"
        );
    }

    function setUp() public virtual {
        alice = createUser("alice");
        bob = createUser("bob");
        celine = createUser("celine");
        deployer = createUser("deployer");
        minter = createUser("minter");
    }

    modifier __mainnet_fork(uint256 blockNumber) {
        vm.selectFork(mainnetForkId);
        vm.rollFork(blockNumber);

        _;
    }

    // creates a user
    function createUser(string memory name) public returns (address _user) {
        _user = address(uint160(uint256(keccak256(abi.encode(name)))));
        vm.label(_user, name);
        vm.deal(_user, 10000 ether);
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
}
