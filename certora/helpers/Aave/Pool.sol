// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.18;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAToken} from "./IAToken.sol";
interface IPool {
    /**
    * @notice Supplies an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
    * - E.g. User supplies 100 USDC and gets in return 100 aUSDC
    * @param asset The address of the underlying asset to supply
    * @param amount The amount to be supplied
    * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
    *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
    *   is a different wallet
    * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
    *   0 if the action is executed directly by the user, without any middle-man
    */
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    /** 
    * @notice Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
    * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
    * @param asset The address of the underlying asset to withdraw
    * @param amount The underlying amount to be withdrawn
    *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
    * @param to The address that will receive the underlying, same as msg.sender if the user
    *   wants to receive it on his own wallet, or a different address if the beneficiary is a
    *   different wallet
    * @return The final amount withdrawn
    */
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    /**
    * @notice Returns the normalized income of the reserve
    * @param asset The address of the underlying asset of the reserve
    * @return The reserve's normalized income
    */
    function getReserveNormalizedIncome(address asset) external view returns (uint256);
}

contract Pool is IPool {
    // underlying asset address -> AToken address of that token.
    mapping(address => address) public underlyingAssetToAToken;
    // underlying asset -> pool liquidity index of that asset
    // This index is used to convert the underlying token to its matching
    // AToken inside the pool, and vice versa.
    mapping(address => mapping(uint256 => uint256)) public liquidityIndex;

    /**
    * @dev Deposits underlying token in the Atoken's contract on behalf of the user,
        and mints Atoken on behalf of the user in return.
    * @param asset The underlying sent by the user and to which Atoken shall be minted
    * @param amount The amount of underlying token sent by the user
    * @param onBehalfOf The recipient of the minted Atokens
    **/
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16
    ) external {
        IERC20(asset).transferFrom(
            msg.sender,
            underlyingAssetToAToken[asset],
            amount
        );
        
        IAToken(underlyingAssetToAToken[asset]).mint(
            msg.sender,
            onBehalfOf,
            amount,
            liquidityIndex[asset][block.timestamp]
        );
    }

    /**
     * @dev Burns Atokens in exchange for underlying asset
     * @param asset The underlying asset to which the Atoken is connected
     * @param amount The amount of underlying tokens to be burned
     * @param to The recipient of the burned Atokens
     * @return The `amount` of tokens withdrawn
     **/
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        IAToken(underlyingAssetToAToken[asset]).burn(
            msg.sender,
            to,
            amount,
            liquidityIndex[asset][block.timestamp]
        );
        return amount;
    }

    /**
     * @dev A simplification returning a constant
     * @param asset The underlying asset to which the Atoken is connected
     * @return liquidityIndex the `liquidityIndex` of the asset
     **/
    function getReserveNormalizedIncome(address asset)
        external
        view
        returns (uint256)
    {
        return liquidityIndex[asset][block.timestamp];
    }

    // Returns the pool liquidity index of an underlying asset.
    function liquidityIndexByAsset(address asset) external view returns(uint256) {
        return liquidityIndex[asset][block.timestamp];
    }
}