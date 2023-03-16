// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IPool } from "@aave/interfaces/IPool.sol";
import { IPoolAddressesProvider } from "@aave/interfaces/IPoolAddressesProvider.sol";
import { IPoolDataProvider } from "@aave/interfaces/IPoolDataProvider.sol";
import { ICreditDelegationToken } from "@aave/interfaces/ICreditDelegationToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { DataTypes } from "@aave/protocol/libraries/types/DataTypes.sol";

contract AaveFixedBorrowAction {
    // Hyperdrive contract
    IHyperdrive public hyperdrive;
    /// Aave Pool contract
    IPool public pool;
    /// Token to borrow and short with
    IERC20 public debtToken;
    /// Token which tracks users variable debt
    ICreditDelegationToken public variableDebtToken;

    constructor(IHyperdrive _hyperdrive, IPool _pool) {
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
    function supplyBorrowAndOpenShort(
        address _collateralToken,
        uint256 _supplyAmount,
        uint256 _borrowAmount,
        uint256 _bondAmount,
        uint256 _maxDeposit
    ) public returns (uint256 baseDeposited) {
        // Transfers users collateral to this contract
        IERC20(_collateralToken).transferFrom(
            msg.sender,
            address(this),
            _supplyAmount
        );

        // Supply the aave pool with collateral on behalf of user
        pool.supply(_collateralToken, _supplyAmount, msg.sender, 0);

        // Borrow on behalf of the user
        pool.borrow(
            address(debtToken),
            _borrowAmount,
            uint256(DataTypes.InterestRateMode.VARIABLE),
            0,
            msg.sender
        );

        // Open short
        baseDeposited = hyperdrive.openShort(
            _bondAmount,
            _maxDeposit,
            msg.sender,
            true
        );

        // Any remaining amount of borrowings is repayed on the debt position
        pool.repay(
            address(debtToken),
            _borrowAmount - baseDeposited,
            uint256(DataTypes.InterestRateMode.VARIABLE),
            msg.sender
        );
    }

    /// TODO This should probably an admin only function
    ///
    /// @notice Sets approvals for other contracts to send tokens on this
    ///         contracts behalf
    /// @param _token The token contract
    /// @param _spender The spender which is to be approved
    /// @param _amount The amount the spender is allowed to transfer on behalf
    ///                of this contract
    function setApproval(
        address _token,
        address _spender,
        uint256 _amount
    ) public {
        IERC20(_token).approve(_spender, _amount);
    }
}
