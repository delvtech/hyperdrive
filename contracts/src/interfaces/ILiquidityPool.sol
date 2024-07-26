// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IEETH } from "./IEETH.sol";

interface ILiquidityPool {
    function eETH() external view returns (IEETH);

    function numPendingDeposits() external view returns (uint32);
    function totalValueOutOfLp() external view returns (uint128);
    function totalValueInLp() external view returns (uint128);
    function getTotalEtherClaimOf(
        address _user
    ) external view returns (uint256);
    function getTotalPooledEther() external view returns (uint256);
    function sharesForAmount(uint256 _amount) external view returns (uint256);
    function sharesForWithdrawalAmount(
        uint256 _amount
    ) external view returns (uint256);
    function amountForShare(uint256 _share) external view returns (uint256);

    function deposit() external payable returns (uint256);
    function deposit(address _referral) external payable returns (uint256);
    function deposit(
        address _user,
        address _referral
    ) external payable returns (uint256);
    function depositToRecipient(
        address _recipient,
        uint256 _amount,
        address _referral
    ) external returns (uint256);

    function rebase(int128 _accruedRewards) external;
    function addEthAmountLockedForWithdrawal(uint128 _amount) external;
    function reduceEthAmountLockedForWithdrawal(uint128 _amount) external;
}
