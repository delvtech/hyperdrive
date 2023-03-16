// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IPool } from "@aave/interfaces/IPool.sol";
import { IPoolAddressesProvider } from "@aave/interfaces/IPoolAddressesProvider.sol";
import { IPoolDataProvider } from "@aave/interfaces/IPoolDataProvider.sol";
import { ICreditDelegationToken } from "@aave/interfaces/ICreditDelegationToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

contract AaveFixedBorrowAction {
    // Hyperdrive contract
    IHyperdrive hyperdrive;
    /// Aave Pool contract
    IPool public pool;
    /// Token to borrow and short with
    IERC20 public debtToken;
    /// Token which tracks users variable debt
    ICreditDelegationToken public variableDebtToken;
    // Token which can be borrowed against
    IERC20 public collateralToken;

    error CollateralTokenNotFound();

    constructor(IHyperdrive _hyperdrive, IPool _pool, IERC20 _collateralToken) {
        // Assign variables
        hyperdrive = _hyperdrive;
        pool = _pool;
        // The token we wish to borrow and short can be called from hyperdrive
        // directly
        debtToken = IERC20(hyperdrive.baseToken());

        // Get the Aave pool address provider
        IPoolAddressesProvider poolAddressesProvider = IPoolAddressesProvider(
            pool.ADDRESSES_PROVIDER()
        );

        // Get the Aave pool data provider
        IPoolDataProvider poolDataProvider = IPoolDataProvider(
            poolAddressesProvider.getPoolDataProvider()
        );

        // Get the variableDebtToken
        (, , address _variableDebtToken) = poolDataProvider
            .getReserveTokensAddresses(address(debtToken));
        variableDebtToken = ICreditDelegationToken(_variableDebtToken);

        // Get the list of tokens which can be used as collateral
        IPoolDataProvider.TokenData[] memory reserveTokens = poolDataProvider
            .getAllReservesTokens();

        // Validate the specified collateral token can be used
        for (uint256 i = 0; i < reserveTokens.length; i++) {
            if (reserveTokens[i].tokenAddress == address(_collateralToken)) {
                collateralToken = _collateralToken;
                break;
            }
        }

        // Revert if the collateral token is found
        if (address(collateralToken) == address(0)) {
            revert CollateralTokenNotFound();
        }

        // Approvals for this contract
        collateralToken.approve(address(pool), type(uint256).max);
        debtToken.approve(address(hyperdrive), type(uint256).max);
    }

    /// @notice This function performs three actions
    ///         - Supply Aave collateral on behalf of user
    ///         - Borrow some base on behalf of user
    ///         - Short an amount of bonds
    /// @param _supplyAmount The amount of collateral
    /// @param _borrowAmount The amount of base to be borrowed
    /// @param _bondAmount The amount of bonds to short
    /// @param _maxDeposit The max amount of base to be used to make the short
    /// @return baseDeposited The amount of base used to make the short
    /// @return baseRemaining The amount of unused base which was returned to
    ///                       the user
    function supplyBorrowAndOpenShort(
        uint256 _supplyAmount,
        uint256 _borrowAmount,
        uint256 _bondAmount,
        uint256 _maxDeposit
    ) public returns (uint256 baseDeposited, uint256 baseRemaining) {
        // Transfers users collateral to this contract
        collateralToken.transferFrom(msg.sender, address(this), _supplyAmount);

        // Supply the aave pool with collateral on behalf of user
        pool.supply(address(collateralToken), _supplyAmount, msg.sender, 0);

        // Borrow on behalf of the user
        pool.borrow(address(debtToken), _borrowAmount, 2, 0, msg.sender);

        // Open short
        baseDeposited = hyperdrive.openShort(
            _bondAmount,
            _maxDeposit,
            msg.sender,
            true
        );

        // Get the unused amount of base that was borrowed
        baseRemaining = _borrowAmount - baseDeposited;

        // Transfer remaining to user
        debtToken.transfer(msg.sender, baseRemaining);
    }
}
