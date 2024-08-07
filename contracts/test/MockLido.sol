// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { Authority } from "solmate/auth/Auth.sol";
import { MultiRolesAuthority } from "solmate/auth/authorities/MultiRolesAuthority.sol";
import { FixedPointMath } from "../src/libraries/FixedPointMath.sol";

/// @author DELV
/// @title MockLido
/// @notice This mock yield source will accrue interest at a specified rate
///         Every stateful interaction will accrue interest, so the interest
///         accrual will approximate continuous compounding as the contract
///         is called more frequently.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MockLido is MultiRolesAuthority, ERC20 {
    using FixedPointMath for uint256;

    // Admin State
    bool public immutable isCompetitionMode;
    uint256 public maxMintAmount;
    mapping(address => bool) public isUnrestricted;

    // Interest State
    uint256 internal _rate;
    uint256 internal _lastUpdated;

    // Lido State
    uint256 internal totalPooledEther;
    uint256 internal totalShares;

    // The shares that each account owns.
    mapping(address => uint256) public sharesOf;

    // Emitted when shares are transferred.
    event TransferShares(
        address indexed from,
        address indexed to,
        uint256 sharesValue
    );

    constructor(
        uint256 _initialRate,
        address _admin,
        bool _isCompetitionMode,
        uint256 _maxMintAmount
    )
        ERC20("Liquid staked Ether 2.0", "stETH")
        MultiRolesAuthority(_admin, Authority(address(address(this))))
    {
        // Store the initial rate and the last updated time.
        _rate = _initialRate;
        _lastUpdated = block.timestamp;

        // Update the admin settings.
        isCompetitionMode = _isCompetitionMode;
        maxMintAmount = _maxMintAmount;
    }

    /// Admin ///

    modifier requiresAuthDuringCompetition() {
        if (isCompetitionMode) {
            require(
                isAuthorized(msg.sender, msg.sig),
                "MockLido: not authorized"
            );
        }
        _;
    }

    function mint(uint256 _amount) external requiresAuthDuringCompetition {
        _mintShares(msg.sender, _amount);
    }

    function mint(
        address _recipient,
        uint256 _amount
    ) external requiresAuthDuringCompetition {
        _mintShares(_recipient, _amount);
    }

    function _mintShares(address _recipient, uint256 _amount) internal {
        // If the sender is restricted, ensure that the mint amount is less than
        // the maximum.
        if (!isUnrestricted[msg.sender]) {
            require(_amount <= maxMintAmount, "MockLido: Invalid mint amount");
        }

        // Credit shares to the recipient.
        uint256 sharesAmount;
        if (getTotalShares() == 0) {
            sharesAmount = _amount;
        } else {
            sharesAmount = getSharesByPooledEth(_amount);
        }
        sharesOf[_recipient] += sharesAmount;

        // Update the Lido state.
        totalPooledEther += _amount;
        totalShares += sharesAmount;
    }

    function burn(uint256 amount) external requiresAuthDuringCompetition {
        _burnShares(msg.sender, amount);
    }

    function burn(
        address _target,
        uint256 _amount
    ) external requiresAuthDuringCompetition {
        _burnShares(_target, _amount);
    }

    function _burnShares(address _target, uint256 _amount) internal {
        // Debit shares from the recipient.
        uint256 sharesAmount = getSharesByPooledEth(_amount);
        sharesOf[_target] -= sharesAmount;

        // Update the Lido state.
        totalPooledEther -= _amount;
        totalShares -= sharesAmount;
    }

    function setMaxMintAmount(
        uint256 _maxMintAmount
    ) external requiresAuthDuringCompetition {
        maxMintAmount = _maxMintAmount;
    }

    function setUnrestrictedMintStatus(
        address _target,
        bool _status
    ) external requiresAuthDuringCompetition {
        isUnrestricted[_target] = _status;
    }

    /// ERC20 Functions ///

    function balanceOf(address _owner) public view override returns (uint256) {
        return getPooledEthByShares(sharesOf[_owner]);
    }

    function transfer(
        address _recipient,
        uint256 _amount
    ) public override returns (bool) {
        // Accrue interest.
        _accrue();

        // Transfer the tokens.
        uint256 sharesAmount = getSharesByPooledEth(_amount);
        _transferShares(_recipient, sharesAmount);

        // Emit the transfer events.
        emit Transfer(msg.sender, _recipient, _amount);
        emit TransferShares(msg.sender, _recipient, sharesAmount);

        return true;
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) public override returns (bool) {
        // Accrue interest.
        _accrue();

        // Transfer the tokens.
        uint256 sharesAmount = getSharesByPooledEth(_amount);
        _transferSharesFrom(_sender, _recipient, sharesAmount);

        // Emit the transfer events.
        emit Transfer(msg.sender, _recipient, _amount);
        emit TransferShares(msg.sender, _recipient, sharesAmount);

        return true;
    }

    /// stETH Functions ///

    function submit(address) external payable returns (uint256) {
        // Accrue interest.
        _accrue();

        // If this is the first deposit, mint shares 1:1.
        if (getTotalShares() == 0) {
            totalShares = msg.value;
            totalPooledEther = msg.value;
            sharesOf[msg.sender] += msg.value;
            return msg.value;
        }

        // Calculate the amount of stETH shares that should be minted.
        uint256 shares = msg.value.mulDivDown(
            getTotalShares(),
            getTotalPooledEther()
        );

        // Update the Lido state.
        totalPooledEther += msg.value;
        totalShares += shares;

        // Mint shares to the user.
        sharesOf[msg.sender] += shares;

        return shares;
    }

    function transferShares(
        address _recipient,
        uint256 _sharesAmount
    ) public returns (uint256) {
        // Accrue interest.
        _accrue();

        // Transfer the shares.
        uint256 tokenAmount = _transferShares(_recipient, _sharesAmount);

        // Emit the transfer events.
        emit Transfer(msg.sender, _recipient, tokenAmount);
        emit TransferShares(msg.sender, _recipient, _sharesAmount);

        return getPooledEthByShares(_sharesAmount);
    }

    function _transferShares(
        address _recipient,
        uint256 _sharesAmount
    ) internal returns (uint256) {
        // Debit shares from the sender.
        sharesOf[msg.sender] -= _sharesAmount;

        // Credit shares to the recipient.
        sharesOf[_recipient] += _sharesAmount;

        return getPooledEthByShares(_sharesAmount);
    }

    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256) {
        // Accrue interest.
        _accrue();

        // Transfer the shares.
        uint256 tokenAmount = _transferSharesFrom(
            _sender,
            _recipient,
            _sharesAmount
        );

        // Emit the transfer events.
        emit Transfer(_sender, _recipient, tokenAmount);
        emit TransferShares(_sender, _recipient, _sharesAmount);

        return tokenAmount;
    }

    function _transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) internal returns (uint256) {
        // Reduce the allowance.
        uint256 tokenAmount = getPooledEthByShares(_sharesAmount);
        _spendAllowance(_sender, msg.sender, tokenAmount);

        // Debit shares from the sender.
        sharesOf[_sender] -= _sharesAmount;

        // Credit shares to the recipient.
        sharesOf[_recipient] += _sharesAmount;

        return tokenAmount;
    }

    function getSharesByPooledEth(
        uint256 _ethAmount
    ) public view returns (uint256) {
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
}
