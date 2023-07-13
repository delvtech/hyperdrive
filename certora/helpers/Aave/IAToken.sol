// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.18;
interface IAToken {
    function totalSupply() external view returns (uint256);

    function scaledTotalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function scaledBalanceOf(address account) external view returns (uint128);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    function mint(address caller, address onBehalfOf, uint256 amount, uint256 index) external returns (bool);

    function burn(address from, address receiverOfUnderlying, uint256 amount, uint256 index) external ;

    function RESERVE_TREASURY_ADDRESS() external view returns (address);

    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
