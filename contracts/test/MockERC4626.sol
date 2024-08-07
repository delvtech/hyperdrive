// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { Authority } from "solmate/auth/Auth.sol";
import { MultiRolesAuthority } from "solmate/auth/authorities/MultiRolesAuthority.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626 } from "solmate/tokens/ERC4626.sol";
import { FixedPointMath } from "../src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "./ERC20Mintable.sol";

/// @author DELV
/// @title MockERC4626
/// @notice This mock yield source will accrue interest at a specified rate
///         Every stateful interaction will accrue interest, so the interest
///         accrual will approximate continuous compounding as the contract
///         is called more frequently.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MockERC4626 is ERC4626, MultiRolesAuthority {
    using FixedPointMath for uint256;

    uint256 internal _rate;
    uint256 internal _lastUpdated;

    bool public immutable isCompetitionMode;
    uint256 public maxMintAmount;
    mapping(address => bool) public isUnrestricted;

    constructor(
        ERC20Mintable _asset,
        string memory _name,
        string memory _symbol,
        uint256 _initialRate,
        address _admin,
        bool _isCompetitionMode,
        uint256 _maxMintAmount
    )
        ERC4626(ERC20(address(_asset)), _name, _symbol)
        MultiRolesAuthority(_admin, Authority(address(this)))
    {
        _rate = _initialRate;
        _lastUpdated = block.timestamp;
        isCompetitionMode = _isCompetitionMode;
        maxMintAmount = _maxMintAmount;
    }

    modifier requiresAuthDuringCompetition() {
        if (isCompetitionMode) {
            require(
                isAuthorized(msg.sender, msg.sig),
                "MockERC4626: not authorized"
            );
        }
        _;
    }

    /// Minting and Burning ///

    function mint(uint256 amount) external requiresAuthDuringCompetition {
        // If the sender is restricted to mint, ensure that their mint amount
        // is less than the max mint amount.
        if (!isUnrestricted[msg.sender]) {
            require(
                amount <= maxMintAmount,
                "MockERC4626: Invalid mint amount"
            );
        }

        // Mint assets to the vault.
        ERC20Mintable(address(asset)).mint(convertToAssets(amount));

        // Mint vault shares.
        _mint(msg.sender, amount);
    }

    function mint(
        address destination,
        uint256 amount
    ) external requiresAuthDuringCompetition {
        // If the sender is restricted to mint, ensure that their mint amount
        // is less than the max mint amount.
        if (!isUnrestricted[msg.sender]) {
            require(
                amount <= maxMintAmount,
                "MockERC4626: Invalid mint amount"
            );
        }

        // Mint assets to the vault.
        ERC20Mintable(address(asset)).mint(convertToAssets(amount));

        // Mint vault shares.
        _mint(destination, amount);
    }

    function burn(uint256 amount) external requiresAuthDuringCompetition {
        // Burn assets from the vault.
        ERC20Mintable(address(asset)).burn(convertToAssets(amount));

        // Burn the vault shares.
        _burn(msg.sender, amount);
    }

    function burn(
        address destination,
        uint256 amount
    ) external requiresAuthDuringCompetition {
        // Burn assets from the vault.
        ERC20Mintable(address(asset)).burn(convertToAssets(amount));

        // Burn the vault shares.
        _burn(destination, amount);
    }

    /// Overrides ///

    function deposit(
        uint256 _assets,
        address _receiver
    ) public override returns (uint256) {
        _accrue();
        return super.deposit(_assets, _receiver);
    }

    function mint(
        uint256 _shares,
        address _receiver
    ) public override returns (uint256) {
        _accrue();
        return super.mint(_shares, _receiver);
    }

    function withdraw(
        uint256 _assets,
        address _receiver,
        address _owner
    ) public override returns (uint256) {
        _accrue();
        return super.withdraw(_assets, _receiver, _owner);
    }

    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) public override returns (uint256) {
        _accrue();
        return super.redeem(_shares, _receiver, _owner);
    }

    function totalAssets() public view override returns (uint256) {
        return
            asset.balanceOf(address(this)) +
            _getAccruedInterest(block.timestamp);
    }

    function totalAssets(uint256 timestamp) public view returns (uint256) {
        return asset.balanceOf(address(this)) + _getAccruedInterest(timestamp);
    }

    /// Mock ///

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

    function setRate(uint256 _rate_) external requiresAuthDuringCompetition {
        _accrue();
        _rate = _rate_;
    }

    function getRate() external view returns (uint256) {
        return _rate;
    }

    function _accrue() internal {
        uint256 interest = _getAccruedInterest(block.timestamp);
        if (interest > 0) {
            ERC20Mintable(address(asset)).mint(interest);
        }
        _lastUpdated = block.timestamp;
    }

    function _getAccruedInterest(
        uint256 timestamp
    ) internal view returns (uint256) {
        // If the rate is zero, no interest has accrued.
        if (_rate == 0) {
            return 0;
        }

        // If the block timestamp is less than last updated, the accrual
        // calculation will underflow. This can occur when using anvil's state
        // snapshots.
        if (timestamp < _lastUpdated) {
            return 0;
        }

        // base_balance = base_balance * (1 + r * t)
        uint256 timeElapsed = (timestamp - _lastUpdated).divDown(365 days);
        uint256 accrued = asset.balanceOf(address(this)).mulDown(
            _rate.mulDown(timeElapsed)
        );
        return accrued;
    }
}
