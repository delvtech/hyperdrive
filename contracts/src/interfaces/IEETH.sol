// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IEETH {
    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalShares() external view returns (uint256);
    function shares(address _user) external view returns (uint256);
    function balanceOf(address _user) external view returns (uint256);
    function initialize(address _liquidityPool) external;
    function mintShares(address _user, uint256 _share) external;
    function burnShares(address _user, uint256 _share) external;
    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool);
    function transfer(
        address _recipient,
        uint256 _amount
    ) external returns (bool);
    function approve(address _spender, uint256 _amount) external returns (bool);
}
