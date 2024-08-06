// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { console2 } from "forge-std/console2.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "../../contracts/src/interfaces/IERC20.sol";
import { ERC20ForwarderFactory } from "../../contracts/src/token/ERC20ForwarderFactory.sol";

contract BaseTest is Test {
    address alice;
    address bob;
    address celine;
    address dan;
    address eve;

    address minter;
    address deployer;
    address feeCollector;
    address sweepCollector;
    address governance;
    address pauser;
    address registrar;
    address rewardSource;

    error WhaleBalanceExceeded();
    error WhaleIsContract();

    uint256 __init__; // time setup function was ran

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");

    bool isForked;

    function setUp() public virtual {
        alice = createUser("alice");
        bob = createUser("bob");
        celine = createUser("celine");
        dan = createUser("dan");
        eve = createUser("eve");

        deployer = createUser("deployer");
        minter = createUser("minter");
        feeCollector = createUser("feeCollector");
        sweepCollector = createUser("sweepCollector");
        governance = createUser("governance");
        pauser = createUser("pauser");
        registrar = createUser("registrar");
        rewardSource = createUser("rewardSource");

        __init__ = block.timestamp;
    }

    modifier __mainnet_fork(uint256 blockNumber) {
        uint256 mainnetForkId = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetForkId);
        vm.rollFork(blockNumber);
        isForked = true;

        _;
    }

    modifier __sepolia_fork(uint256 blockNumber) {
        uint256 sepoliaForkId = vm.createFork(SEPOLIA_RPC_URL);
        vm.selectFork(sepoliaForkId);
        vm.rollFork(blockNumber);
        isForked = true;

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
        vm.stopPrank();
        vm.startPrank(whale);
        vm.deal(whale, 1 ether);
        token.transfer(to, amount);
        return amount;
    }

    function fundAccounts(
        address hyperdrive,
        IERC20 token,
        address source,
        address[] memory accounts
    ) internal {
        uint256 sourceBalance = token.balanceOf(source);
        for (uint256 i = 0; i < accounts.length; i++) {
            // Transfer the tokens to the account.
            whaleTransfer(
                source,
                token,
                sourceBalance / accounts.length,
                accounts[i]
            );

            // Approve Hyperdrive on behalf of the account.
            vm.startPrank(accounts[i]);
            token.approve(hyperdrive, type(uint256).max);
        }
    }
}
