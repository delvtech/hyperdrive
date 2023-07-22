// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626 } from "solmate/mixins/ERC4626.sol";
import { FixedPointMath } from "../src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "./ERC20Mintable.sol";

contract MockERC4626 is ERC4626 {
    using FixedPointMath for uint256;

    uint256 internal rate;
    uint256 internal lastUpdated;

    constructor(
        ERC20Mintable _asset,
        string memory _name,
        string memory _symbol,
        uint256 _initialRate
    ) ERC4626(ERC20(address(_asset)), _name, _symbol) {
        rate = _initialRate;
        lastUpdated = block.timestamp;
    }

    /// Overrides ///

    function deposit(
        uint256 assets,
        address receiver
    ) public override returns (uint256) {
        accrue();
        return super.deposit(assets, receiver);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public override returns (uint256) {
        accrue();
        return super.mint(shares, receiver);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256) {
        accrue();
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256) {
        accrue();
        return super.redeem(shares, receiver, owner);
    }

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this)) + getAccruedInterest();
    }

    /// Interest Accrual ///

    function accrue() internal {
        ERC20Mintable(address(asset)).mint(getAccruedInterest());
        lastUpdated = block.timestamp;
    }

    function getAccruedInterest() internal view returns (uint256) {
        // base_balance = base_balance * (1 + r * t)
        uint256 timeElapsed = (block.timestamp - lastUpdated).divDown(365 days);
        return
            asset.balanceOf(address(this)).mulDown(rate.mulDown(timeElapsed));
    }
}
