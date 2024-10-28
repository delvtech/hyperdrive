// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "./IERC20.sol";

interface IMToken is IERC20 {

    // IMoonwellComptroller comptroller;

    function comptroller() external view returns (address);

    function underlying() external view returns (address);

    /// @notice Total amount of reserves of the underlying held in this market
    function totalReserves() external view returns (uint256);

    /// @notice Total number of tokens in circulation
    function totalSupply() external view returns (uint256);

    /// @notice Returns the current per-second supply interest rate for this mToken
    /// @return The supply interest rate per timestamp, scaled by 1e18
    function supplyRatePerTimestamp() external view returns (uint);

    function getCash() external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function mint(uint256 mintAmount) external returns (uint256);
    
    function redeem(uint256 redeemTokens) external returns (uint256);

}

interface IMoonwellComptroller {

    /// @notice Allows anyone to claim the rewards accrued on the staked USDS.
    ///         After this is called, the funds can be swept by the sweep
    ///         collector.
    function claimRewards() external;

}

// interface IMoonwellRewardsDistributor {

//     struct RewardInfo{
//         address emissionToken;
//         uint totalAmount;
//         uint supplySide;
//         uint borrowSide;
//     }

//     struct MarketEmissionConfig {
//         MarketConfig config;
//         mapping(address => uint) supplierIndices;
//         mapping(address => uint) supplierRewardsAccrued;
//         mapping(address => uint) borrowerIndices;
//         mapping(address => uint) borrowerRewardsAccrued;
//     }

//     mapping(address => MarketEmissionConfig[]) public marketConfigs;

//     function getOutstandingRewardsForUser(
//         IMToken _mToken,
//         address _user
//     ) external view (RewardInfo[] memory) {
//         // Global config for this mToken
//         MarketEmissionConfig[] storage configs = marketConfigs[
//             address(_mToken)
//         ];

//         // Output var
//         RewardInfo[] memory outputRewardData = new RewardInfo[](configs.length);

//         // Code golf to avoid too many local vars :rolling-eyes:
//         CalculatedData memory calcData = CalculatedData({
//             marketData: CurrentMarketData({
//                 totalMTokens: _mToken.totalSupply(),
//                 totalBorrows: _mToken.totalBorrows(),
//                 marketBorrowIndex: Exp({mantissa: _mToken.borrowIndex()})
//             }),
//             mTokenInfo: MTokenData({
//                 mTokenBalance: _mToken.balanceOf(_user),
//                 borrowBalanceStored: _mToken.borrowBalanceStored(_user)
//             })
//         });

//         for (uint256 index = 0; index < configs.length; index++) {
//             MarketEmissionConfig storage emissionConfig = configs[index];

//             // Calculate our new global supply index
//             IndexUpdate memory supplyUpdate = calculateNewIndex(
//                 emissionConfig.config.supplyEmissionsPerSec,
//                 emissionConfig.config.supplyGlobalTimestamp,
//                 emissionConfig.config.supplyGlobalIndex,
//                 emissionConfig.config.endTime,
//                 calcData.marketData.totalMTokens
//             );

//             // Calculate our new global borrow index
//             IndexUpdate memory borrowUpdate = calculateNewIndex(
//                 emissionConfig.config.borrowEmissionsPerSec,
//                 emissionConfig.config.borrowGlobalTimestamp,
//                 emissionConfig.config.borrowGlobalIndex,
//                 emissionConfig.config.endTime,
//                 div_(
//                     calcData.marketData.totalBorrows,
//                     calcData.marketData.marketBorrowIndex
//                 )
//             );

//             // Calculate outstanding supplier side rewards
//             uint256 supplierRewardsAccrued = calculateSupplyRewardsForUser(
//                 emissionConfig,
//                 supplyUpdate.newIndex,
//                 calcData.mTokenInfo.mTokenBalance,
//                 _user
//             );

//             uint256 borrowerRewardsAccrued = calculateBorrowRewardsForUser(
//                 emissionConfig,
//                 borrowUpdate.newIndex,
//                 calcData.marketData.marketBorrowIndex,
//                 calcData.mTokenInfo,
//                 _user
//             );

//             outputRewardData[index] = RewardInfo({
//                 emissionToken: emissionConfig.config.emissionToken,
//                 totalAmount: borrowerRewardsAccrued + supplierRewardsAccrued,
//                 supplySide: supplierRewardsAccrued,
//                 borrowSide: borrowerRewardsAccrued
//             });
//         }

//         return outputRewardData;
//     }

//     function _updateSupplySpeed(
//         MToken _mToken,
//         address _emissionToken,
//         uint256 _newSupplySpeed
//     ) external virtual;
// }