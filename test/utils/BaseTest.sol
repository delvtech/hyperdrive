// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "../../contracts/src/interfaces/IERC20.sol";

contract BaseTest is Test {
    address internal alice;
    address internal bob;
    address internal celine;
    address internal dan;
    address internal eve;

    address internal minter;
    address internal deployer;
    address internal feeCollector;
    address internal sweepCollector;
    address internal governance;
    address internal pauser;
    address internal registrar;
    address internal rewardSource;

    error WhaleBalanceExceeded();
    error WhaleIsContract();

    uint256 __init__; // time setup function was ran

    string internal ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    string internal BASE_RPC_URL = vm.envString("BASE_RPC_URL");
    string internal GNOSIS_CHAIN_RPC_URL = vm.envString("GNOSIS_CHAIN_RPC_URL");
    string internal LINEA_RPC_URL = vm.envString("LINEA_RPC_URL");
    string internal MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string internal SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");

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

    modifier __arbitrum_fork(uint256 blockNumber) {
        uint256 arbitrumForkId = vm.createFork(ARBITRUM_RPC_URL);
        vm.selectFork(arbitrumForkId);
        vm.rollFork(blockNumber);
        isForked = true;

        _;
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

    modifier __gnosis_chain_fork(uint256 blockNumber) {
        uint256 gnosisChainForkId = vm.createFork(GNOSIS_CHAIN_RPC_URL);
        vm.selectFork(gnosisChainForkId);
        vm.rollFork(blockNumber);
        isForked = true;

        _;
    }

    modifier __linea_fork(uint256 blockNumber) {
        uint256 lineaForkId = vm.createFork(LINEA_RPC_URL);
        vm.selectFork(lineaForkId);
        vm.rollFork(blockNumber);
        isForked = true;

        _;
    }

    modifier __base_fork(uint256 blockNumber) {
        uint256 baseForkId = vm.createFork(BASE_RPC_URL);
        vm.selectFork(baseForkId);
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
        address approvalTarget,
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

            // Approve the approval target on behalf of the account.
            vm.startPrank(accounts[i]);
            token.approve(approvalTarget, type(uint256).max);
        }
    }
}
