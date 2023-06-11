pragma solidity ^0.8.18;

import { MultiToken } from "../../../contracts/src/MultiToken.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { Errors } from "../../../contracts/src/libraries/Errors.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";


contract SymbolicHyperdrive is MultiToken {
    using FixedPointMath for uint256;

    uint256 internal rate;
    uint256 internal totalShares;
    uint256 internal lastUpdated;

    IERC20 internal _baseToken;

    constructor(
        address _dataProvider,
        bytes32 _linkerCodeHash_, 
        address _factory_
    )  MultiToken(_dataProvider, _linkerCodeHash_, _factory_) { }


    function balanceOf(uint256 tokenId, address account) public view returns (uint256) {
        return _balanceOf[tokenId][account];
    }

    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256) {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        uint256 pricePerShare = _pricePerShare();
        uint256 shareProceeds = _bondAmount.divDown(pricePerShare);

        _burn(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _maturityTime),
            msg.sender,
            _bondAmount
        );

        (uint256 baseProceeds, ) = _withdraw(
            shareProceeds,
            _destination,
            _asUnderlying
        );

        return (baseProceeds);
    }

    error UnsupportedOption();

    function _withdraw(
        uint256 _shares,
        address _destination,
        bool _asUnderlying
    ) internal returns (uint256 amountWithdrawn, uint256 sharePrice) {
        if (!_asUnderlying) revert UnsupportedOption();

        accrueInterest();

        sharePrice = _pricePerShare();
        amountWithdrawn = _shares.mulDown(sharePrice);
        bool success = _baseToken.transfer(_destination, amountWithdrawn);
        if (!success) {
            revert Errors.TransferFailed();
        }

        return (amountWithdrawn, sharePrice);
    }

    function _pricePerShare() internal view returns (uint256) {
        uint256 underlying = _baseToken.balanceOf(address(this)) +
            getAccruedInterest();
        return underlying.divDown(totalShares);
    }


    function getAccruedInterest() internal view returns (uint256) {
        // base_balance = base_balance * (1 + r * t)
        uint256 timeElapsed = (block.timestamp - lastUpdated).divDown(365 days);
        return
            _baseToken.balanceOf(address(this)).mulDown(
                rate.mulDown(timeElapsed)
            );
    }

    function accrueInterest() internal {
        ERC20Mintable(address(_baseToken)).mint(getAccruedInterest());
        lastUpdated = block.timestamp;
    }
}