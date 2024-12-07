// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;
import { console2 as console } from "forge-std/console2.sol";

import { IERC20 } from "./IERC20.sol";

interface IMToken is IERC20 {

    // IMoonwellComptroller comptroller;
    function accrualBlockTimestamp() external view returns (uint);
    function interestRateModel() external view returns (IMoonwellInterestRateModel);
    function comptroller() external view returns (address);
    function underlying() external view returns (address);

    function borrowIndex() external view returns (uint256);

    function reserveFactorMantissa() external view returns (uint256);

    function totalBorrows() external view returns (uint256);

    /// @notice Total amount of reserves of the underlying held in this market
    function totalReserves() external view returns (uint256);

    /// @notice Total number of tokens in circulation
    function totalSupply() external view returns (uint256);

    /// @notice Returns the current per-second supply interest rate for this mToken
    /// @return The supply interest rate per timestamp, scaled by 1e18
    function supplyRatePerTimestamp() external view returns (uint);

    function getCash() external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function accrueInterest() external returns (uint);

    function mint(uint256 mintAmount) external returns (uint256);
    
    function redeem(uint256 redeemTokens) external returns (uint256);

    // function mint(uint mintAmount) external returns (uint) {
    //     (, uint shareAmount) = this.mintInternal(mintAmount);
    //     console.log("mint: ", shareAmount);
    //     return shareAmount;
    // }

    // function mintInternal(uint256 mintAmount) external virtual returns (uint, uint);

}

interface IMoonwellComptroller {

    /// @notice Allows anyone to claim the rewards accrued on the staked USDS.
    ///         After this is called, the funds can be swept by the sweep
    ///         collector.
    function claimRewards() external;

}

interface IMoonwellInterestRateModel {
    function getBorrowRate(uint cash, uint borrows, uint reserves) external view returns(uint256);
    function getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa) external view returns(uint256);
}