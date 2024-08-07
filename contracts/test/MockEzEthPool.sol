// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { MultiRolesAuthority } from "solmate/auth/authorities/MultiRolesAuthority.sol";
import { FixedPointMath } from "../src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "./ERC20Mintable.sol";
import { IERC20 } from "../src/interfaces/IERC20.sol";
import { IRestakeManager, IRenzoOracle } from "../src/interfaces/IRenzo.sol";

/// @author DELV
/// @title MockEzEthPool
/// @notice This mock yield source will accrue interest at a specified rate
///         Every stateful interaction will accrue interest, so the interest
///         accrual will approximate continuous compounding as the contract
///         is called more frequently.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MockEzEthPool is
    IRestakeManager,
    IRenzoOracle,
    MultiRolesAuthority,
    ERC20Mintable
{
    using FixedPointMath for uint256;

    /// @dev Error when calculating token amounts is invalid
    error InvalidTokenAmount();

    // Scale factor for all values of prices
    uint256 internal constant SCALE_FACTOR = 10 ** 18;

    // Interest State
    uint256 internal _rate;
    uint256 internal _lastUpdated;

    // Token State
    uint256 public totalPooledEther;
    uint256 public totalShares;

    constructor(
        uint256 _initialRate,
        address _admin,
        bool _isCompetitionMode,
        uint256 _maxMintAmount
    )
        ERC20Mintable(
            "Renzo ezETH",
            "ezETH",
            18,
            _admin,
            _isCompetitionMode,
            _maxMintAmount
        )
    {
        _rate = _initialRate;
        _lastUpdated = block.timestamp;
    }

    /// Overrides ///

    function submit(address) external payable returns (uint256) {
        // Accrue interest.
        _accrue();

        // If this is the first deposit, mint shares 1:1.
        if (getTotalShares() == 0) {
            totalShares = msg.value;
            totalPooledEther = msg.value;
            _mint(msg.sender, msg.value);
            return msg.value;
        }

        // Calculate the amount of ezETH shares that should be minted.
        uint256 shares = msg.value.mulDivDown(
            getTotalShares(),
            getTotalPooledEther()
        );

        // Update the token state.
        totalPooledEther += msg.value;
        totalShares += shares;

        // Mint the ezETH tokens to the user.
        _mint(msg.sender, msg.value);

        return shares;
    }

    function transferShares(
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256) {
        // Accrue interest.
        _accrue();

        // Calculate the amount of tokens that should be transferred.
        uint256 tokenAmount = _sharesAmount.mulDivDown(
            getTotalPooledEther(),
            getTotalShares()
        );

        // Transfer the tokens to the user.
        transfer(_recipient, tokenAmount);

        return tokenAmount;
    }

    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256) {
        // Accrue interest.
        _accrue();

        // Calculate the amount of tokens that should be transferred.
        uint256 tokenAmount = _sharesAmount.mulDivDown(
            getTotalPooledEther(),
            getTotalShares()
        );

        // Transfer the tokens to the user.
        transferFrom(_sender, _recipient, tokenAmount);

        return tokenAmount;
    }

    function getSharesByPooledEth(
        uint256 _ethAmount
    ) external view returns (uint256) {
        return _ethAmount.mulDivDown(getTotalShares(), getTotalPooledEther());
    }

    function getPooledEthByShares(
        uint256 _sharesAmount
    ) public view returns (uint256) {
        return
            _sharesAmount.mulDivDown(getTotalPooledEther(), getTotalShares());
    }

    function getBufferedEther() external pure returns (uint256) {
        return 0;
    }

    function getTotalPooledEther() public view returns (uint256) {
        return totalPooledEther + _getAccruedInterest();
    }

    function getTotalShares() public view returns (uint256) {
        return totalShares;
    }

    function sharesOf(address _account) external view returns (uint256) {
        uint256 tokenBalance = balanceOf[_account];
        return tokenBalance.mulDivDown(getTotalShares(), getTotalPooledEther());
    }

    /// Mock ///

    function setRate(uint256 _rate_) external requiresAuthDuringCompetition {
        _accrue();
        _rate = _rate_;
    }

    function getRate() external view returns (uint256) {
        return _rate;
    }

    function _accrue() internal {
        uint256 interest = _getAccruedInterest();
        if (interest > 0) {
            totalPooledEther += interest;
        }
        _lastUpdated = block.timestamp;
    }

    function _getAccruedInterest() internal view returns (uint256) {
        // If the rate is zero, no interest has accrued.
        if (_rate == 0) {
            return 0;
        }

        // If the block timestamp is less than last updated, the accrual
        // calculation will underflow. This can occur when using anvil's state
        // snapshots.
        if (block.timestamp < _lastUpdated) {
            return 0;
        }

        // base_balance = base_balance * (1 + r * t)
        uint256 timeElapsed = (block.timestamp - _lastUpdated).divDown(
            365 days
        );
        uint256 accrued = totalPooledEther.mulDown(_rate.mulDown(timeElapsed));
        return accrued;
    }

    function calculateTVLs()
        public
        view
        override
        returns (uint256[][] memory, uint256[] memory, uint256)
    {
        uint256[][] memory operator_tokens_tvls;
        uint256[] memory operator_tvls;
        uint256 tvl = totalSupply.mulDivDown(
            getTotalPooledEther(),
            getTotalShares()
        );
        return (operator_tokens_tvls, operator_tvls, tvl);
    }

    function depositETH() external payable {
        revert("depositETH: Not Implemented");
    }

    function ezETH() external view returns (address) {
        return address(this);
    }

    function renzoOracle() external view returns (address) {
        return address(this);
    }

    // Renzo Oracle Functions //

    function lookupTokenValue(
        IERC20, //_token,
        uint256 //_balance
    ) external pure returns (uint256) {
        revert("lookupTokenValue: Not Implemented");
    }

    function lookupTokenAmountFromValue(
        IERC20, // _token,
        uint256 // _value
    ) external pure returns (uint256) {
        revert("lookupTokenValue: Not Implemented");
    }

    function lookupTokenValues(
        IERC20[] memory, // _tokens,
        uint256[] memory // _balances
    ) external pure returns (uint256) {
        revert("lookupTokenValue: Not Implemented");
    }

    function calculateMintAmount(
        uint256 _currentValueInProtocol,
        uint256 _newValueAdded,
        uint256 _existingEzETHSupply
    ) external pure returns (uint256) {
        // For first mint, just return the new value added.
        // Checking both current value and existing supply to guard against gaming the initial mint
        if (_currentValueInProtocol == 0 || _existingEzETHSupply == 0) {
            return _newValueAdded; // value is priced in base units, so divide by scale factor
        }

        // Calculate the percentage of value after the deposit
        uint256 inflationPercentage = (SCALE_FACTOR * _newValueAdded) /
            (_currentValueInProtocol + _newValueAdded);

        // Calculate the new supply
        uint256 newEzETHSupply = (_existingEzETHSupply * SCALE_FACTOR) /
            (SCALE_FACTOR - inflationPercentage);

        // Subtract the old supply from the new supply to get the amount to mint
        uint256 mintAmount = newEzETHSupply - _existingEzETHSupply;

        // Sanity check
        if (mintAmount == 0) revert InvalidTokenAmount();

        return mintAmount;
    }

    function calculateRedeemAmount(
        uint256 _ezETHBeingBurned,
        uint256 _existingEzETHSupply,
        uint256 _currentValueInProtocol
    ) public pure returns (uint256) {
        // This is just returning the percentage of TVL that matches the percentage of ezETH being burned
        uint256 redeemAmount = (_currentValueInProtocol * _ezETHBeingBurned) /
            _existingEzETHSupply;

        // Sanity check
        if (redeemAmount == 0) revert InvalidTokenAmount();

        return redeemAmount;
    }
}
