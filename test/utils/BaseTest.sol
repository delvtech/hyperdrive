// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "../../contracts/src/interfaces/IERC20.sol";

contract BaseTest is Test {
    address internal alice;
    uint256 internal alicePK;
    address internal bob;
    uint256 internal bobPK;
    address internal celine;
    uint256 internal celinePK;
    address internal dan;
    uint256 internal danPK;
    address internal eve;
    uint256 internal evePK;

    address internal minter;
    uint256 internal minterPK;
    address internal deployer;
    uint256 internal deployerPK;
    address internal feeCollector;
    uint256 internal feeCollectorPK;
    address internal sweepCollector;
    uint256 internal sweepCollectorPK;
    address internal governance;
    uint256 internal governancePK;
    address internal pauser;
    uint256 internal pauserPK;
    address internal registrar;
    uint256 internal registrarPK;
    address internal rewardSource;
    uint256 internal rewardSourcePK;

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
        (alice, alicePK) = createUser("alice");
        (bob, bobPK) = createUser("bob");
        (celine, celinePK) = createUser("celine");
        (dan, danPK) = createUser("dan");
        (eve, evePK) = createUser("eve");

        (deployer, deployerPK) = createUser("deployer");
        (minter, minterPK) = createUser("minter");
        (feeCollector, feeCollectorPK) = createUser("feeCollector");
        (sweepCollector, sweepCollectorPK) = createUser("sweepCollector");
        (governance, governancePK) = createUser("governance");
        (pauser, pauserPK) = createUser("pauser");
        (registrar, registrarPK) = createUser("registrar");
        (rewardSource, rewardSourcePK) = createUser("rewardSource");

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
    function createUser(
        string memory _name
    ) public returns (address user, uint256 privateKey) {
        (user, privateKey) = makeAddrAndKey(_name);
        vm.deal(user, 10000 ether);
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
