// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.18;

import {IAToken} from "./IAToken.sol";
import {AaveMath} from "./AaveMath.sol";
import {IPool, IERC20} from "./Pool.sol";

abstract contract AToken is IAToken {
    using AaveMath for uint256;
    /**
    * @dev Only pool can call functions marked by this modifier.
    **/
    modifier onlyPool() {
        require(msg.sender == address(POOL), "CALLER_MUST_BE_POOL");
        _;
    }

    /**
    * @dev UserState - additionalData is a flexible field.
    * ATokens and VariableDebtTokens use this field store the index of the
    * user's last supply/withdrawal/borrow/repayment. StableDebtTokens use
    * this field to store the user's stable rate.
    */
    struct UserState {
        uint128 balance;
        uint128 additionalData;
    }
    // Map of users address and their state data (userAddress => userStateData)
    mapping(address => UserState) internal _userState;
    // Total supply
    uint256 internal _totalSupply;
    // Allowances
    mapping(address => mapping(address => uint256)) internal _allowance;

    address internal immutable treasury;
    address internal immutable underlyingAsset;
    IPool internal immutable POOL;

    constructor(address _treasury, address _asset, address _pool)
    {
        POOL = IPool(_pool);
        treasury = _treasury;
        underlyingAsset = _asset;
    }

    function scaledTotalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function scaledBalanceOf(address account) public view returns (uint128) {
        return _userState[account].balance;
    }

    function _msgSender() internal view returns (address payable) {
        return payable(msg.sender);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function mint(
        address caller,
        address onBehalfOf,
        uint256 amount,
        uint256 index
    ) external onlyPool returns (bool) {
        return _mintScaled(caller, onBehalfOf, amount, index);
    }

    function burn(
        address from,
        address receiverOfUnderlying,
        uint256 amount,
        uint256 index
    ) external onlyPool {
        _burnScaled(from, receiverOfUnderlying, amount, index);
        if (receiverOfUnderlying != address(this)) {
            (IERC20(underlyingAsset)).transfer(receiverOfUnderlying, amount);
        }
    }

    /**
    * @notice Mints tokens to an account and apply incentives if defined
    * @param account The address receiving tokens
    * @param amount The amount of tokens to mint
    */
    function _mint(address account, uint128 amount) internal {
        _totalSupply += amount;
        _userState[account].balance += amount;
    }

    /**
    * @notice Burns tokens from an account and apply incentives if defined
    * @param account The account whose tokens are burnt
    * @param amount The amount of tokens to burn
    */
    function _burn(address account, uint128 amount) internal virtual {
        _totalSupply -=  amount;
        _userState[account].balance -= amount;
    }

    /**
    * @notice Implements the basic logic to mint a scaled balance token.
    * @param caller caller of the mint transaction
    * @param onBehalfOf The address of the user that will receive the scaled tokens
    * @param amount The amount of tokens getting minted
    * @param index The next liquidity index of the reserve
    * @return `true` if the the previous balance of the user was 0
    **/
    function _mintScaled(
        address caller,
        address onBehalfOf,
        uint256 amount,
        uint256 index
    ) internal returns (bool) {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, "INVALID_MINT_AMOUNT");

        uint256 scaledBalance = scaledBalanceOf(onBehalfOf);

        _userState[onBehalfOf].additionalData = index.toUint128();

        _mint(onBehalfOf, amountScaled.toUint128());
    
        return (scaledBalance == 0);
    }

    /**
    * @notice Implements the basic logic to burn a scaled balance token.
    * @dev In some instances, a burn transaction will emit a mint event
    * if the amount to burn is less than the interest that the user accrued
    * @param user The user which debt is burnt
    * @param amount The amount getting burned
    * @param index The variable debt index of the reserve
    **/
    function _burnScaled(
        address user,
        address target,
        uint256 amount,
        uint256 index
    ) internal {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, "INVALID_BURN_AMOUNT");

        _userState[user].additionalData = index.toUint128();

        _burn(user, amountScaled.toUint128());
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
    uint128 castAmount = amount.toUint128();
        _approve(sender,msg.sender, _allowance[sender][_msgSender()] - castAmount);
        _transfer(sender, recipient, castAmount);
        return true;
    }

    function transfer(address recipient, uint256 amount)
        external
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount.toUint128());
        return true;
    }

    /**
    * @notice Approve `spender` to use `amount` of `owner`s balance
    * @param owner The address owning the tokens
    * @param spender The address approved for spending
    * @param amount The amount of tokens to approve spending of
    */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        _allowance[owner][spender] = amount;
    }

    /**
    * @notice Overrides the parent _transfer to force validated transfer() and transferFrom()
    * @param from The source address
    * @param to The destination address
    * @param amount The amount getting transferred
    **/
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        uint256 index = POOL.getReserveNormalizedIncome(underlyingAsset);

        _scaledTransfer(from, to, amount.rayDiv(index).toUint128());
    }

    /**
    * @notice Transfers tokens between two users and apply incentives if defined.
    * @param sender The source address
    * @param recipient The destination address
    * @param amount The amount getting transferred
    */
    function _scaledTransfer(
        address sender,
        address recipient,
        uint128 amount
    ) internal {
        _userState[sender].balance -= amount;
        _userState[recipient].balance += amount;
    }

    function allowance(address owner, address spender)
        external
        view
        returns (uint256)
    {
        return _allowance[owner][spender];
    }

    function balanceOf(address user) public view returns (uint256) {
        return uint256(scaledBalanceOf(user)).rayMul(POOL.getReserveNormalizedIncome(underlyingAsset));
    }

    function totalSupply() public view override returns (uint256) {
        uint256 currentSupplyScaled = scaledTotalSupply();

        if (currentSupplyScaled == 0) {
            return 0;
        }

        return currentSupplyScaled.rayMul(POOL.getReserveNormalizedIncome(underlyingAsset));
    }

    function RESERVE_TREASURY_ADDRESS() external view  returns (address) {
        return treasury;
    }

    function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
        return underlyingAsset;
    }
}