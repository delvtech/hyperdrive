// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import "./SafeMath.sol";

// With approval checks
contract DummyERC20Impl {
    using SafeMath for uint256;

    uint256 public totalSupply;
    mapping (address => uint256) public balances;
    mapping (address => mapping (address => uint256)) public allowance;

    string public name;
    string public symbol;
    uint public decimals;

    function myAddress() public returns (address) {
        return address(this);
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }
    function transfer(address recipient, uint256 amount) external returns (bool) {
        require(msg.sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        balances[msg.sender] = balances[msg.sender].sub(amount);
        balances[recipient] = balances[recipient].add(amount);
        return true;
    }
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        balances[sender] = balances[sender].sub(amount);
        balances[recipient] = balances[recipient].add(amount);
        // Update allowance
        if (sender != msg.sender) {
            allowance[sender][msg.sender] = allowance[sender][msg.sender].sub(amount);
        }
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(sender != address(0), "ERC20: transfer from the zero address");
        return _transferFrom(sender, recipient, amount);
    }
}

contract DummyMintableERC20Impl is DummyERC20Impl {
    address public minter;

    modifier onlyMinter() {
        require (msg.sender == minter, "Mint callable by minter only");
        _;
    }

    // constructor (address _minter) {
    //     minter = _minter;
    // }

    function mint(address account, uint256 amount) external onlyMinter() {
        _mint(account, amount);
    }

    function _mint(address user, uint256 amount) internal {
        totalSupply += amount;
        balances[user] += amount;
    }
}

contract DummyBoringERC20Impl is DummyMintableERC20Impl {
    /// Mock implementations for the non-standard extensions that boring tokens have
    //
    // Note: Lacks some real functionality (e.g. safeTransferFrom is identical to non-safe).


    // This can be controlled from CVL
    bool _mockShouldAllowAll;

    // This is meant to be some kind of approval mechanism, utulizing on-chain signing of approval messages.
    // The original functionality just reverts if not approved, so this mock can be controlled from CVL.
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(_mockShouldAllowAll);
        allowance[owner][spender] = value;
    }

    function safeTransferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        return _transferFrom(sender, recipient, amount);
    }

    // Not sure if that's nessecary for the tool, 
    // (but maybe helps with rules that want to check things dynamically specifically with that behavior)
    function changeBehavior(bool new_behavior) public {
        _mockShouldAllowAll = new_behavior;
    }
}

