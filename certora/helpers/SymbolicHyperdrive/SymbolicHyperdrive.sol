pragma solidity ^0.8.18;

import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
// import { Hyperdrive } from "../../contracts/src/Hyperdrive.sol";
import { MultiToken } from "../../../contracts/src/MultiToken.sol";
import "../../../contracts/src/HyperdriveStorage.sol";
import { Errors } from "../../../contracts/src/libraries/Errors.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { IPool } from "@aave/interfaces/IPool.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

contract SymbolicHyperdrive is HyperdriveStorage, MultiToken {
    using FixedPointMath for uint256;
    using SafeCast for uint256;

    ///////// AAVE HYPERDRIVE /////////
    // The aave deployment details, the a token for this asset and the aave pool
    // IERC20 internal immutable aToken;
    // IPool internal immutable pool;

    // The shares created by this pool, starts at one to one with deposits and increases
    uint256 internal totalShares;

    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash_, 
        address _factory_,
        IERC20 _aToken,
        IPool _pool
    ) HyperdriveStorage(_config) MultiToken(_dataProvider, _linkerCodeHash_, _factory_) {
        // aToken = _aToken;
        // pool = _pool;
    }

    function balanceOf(uint256 tokenId, address account) public view returns (uint256) {
        return _balanceOf[tokenId][account];
    }


    mapping(address => uint256) public balances;
    function _pricePerShare() internal view returns (uint256) {
        uint256 assets = balances[address(this)];
        uint256 totalShares_ = totalShares;
        if (totalShares_ != 0) {
            return assets.divDown(totalShares_);
        }
        return 0;
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

        uint256 sharePrice = _pricePerShare();
        _applyCheckpoint(_maturityTime, sharePrice);

        _burn(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _maturityTime),
            msg.sender,
            _bondAmount
        );

        GhostVars memory decompose = calculateCloseLong(_bondAmount, sharePrice, _maturityTime);
        uint256 shareReservesDelta = decompose.shareReservesDelta;
        uint256 bondReservesDelta = decompose.bondReservesDelta;
        uint256 shareProceeds = decompose.shareProceeds;


        if (block.timestamp < _maturityTime) {
            _applyCloseLong(
                _bondAmount,
                bondReservesDelta,
                shareProceeds,
                shareReservesDelta,
                _maturityTime,
                sharePrice
            );
        }

        (uint256 baseProceeds, ) = _withdraw(
            shareProceeds,
            _destination,
            _asUnderlying
        );

        if (_minOutput > baseProceeds) revert Errors.OutputLimit();

        return (baseProceeds);
    }

    struct GhostVars {
        uint256 shareReservesDelta;
        uint256 bondReservesDelta;
        uint256 shareProceeds;
    }

    GhostVars public returnGhost;

    function calculateCloseLong(
        uint256 var1, 
        uint256 var2, 
        uint256 var3
    ) internal returns (GhostVars memory)
    { return returnGhost; }

    function _applyCheckpoint(
        uint256 _checkpointTime,
        uint256 _sharePrice
    ) internal returns (uint256 openSharePrice) {
        if (
            _checkpoints[_checkpointTime].sharePrice != 0 ||
            _checkpointTime > block.timestamp
        ) {
            return _checkpoints[_checkpointTime].sharePrice;
        }

        _checkpoints[_checkpointTime].sharePrice = _sharePrice.toUint128();

        uint256 maturedLongsAmount = _totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _checkpointTime)
        ];
        if (maturedLongsAmount > 0) {
            _applyCloseLong(
                maturedLongsAmount,
                0,
                maturedLongsAmount.divDown(_sharePrice),
                0,
                _checkpointTime,
                _sharePrice
            );
        }

        uint256 maturedShortsAmount = _totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _checkpointTime)
        ];
        if (maturedShortsAmount > 0) {
            _applyCloseShort(
                maturedShortsAmount,
                0,
                maturedShortsAmount.divDown(_sharePrice),
                0,
                _checkpointTime,
                _sharePrice
            );
        }

        return _checkpoints[_checkpointTime].sharePrice;
    }

    function _applyCloseLong(
        uint256 _bondAmount,
        uint256 _bondReservesDelta,
        uint256 _shareProceeds,
        uint256 _shareReservesDelta,
        uint256 _maturityTime,
        uint256 _sharePrice
    ) internal {
        _marketState.shareReserves -= _shareReservesDelta.toUint128();
        _marketState.bondReserves += _bondReservesDelta.toUint128();

        _updateLiquidity(-int256(_shareProceeds - _shareReservesDelta));

        uint256 withdrawalSharesOutstanding = _totalSupply[AssetId._WITHDRAWAL_SHARE_ASSET_ID] - _withdrawPool.readyToWithdraw;
        if (withdrawalSharesOutstanding > 0) {

            uint256 openSharePrice = _checkpoints[_maturityTime - _positionDuration].longSharePrice;

            uint256 withdrawalProceeds = HyperdriveMath.calculateShortProceeds(
                _bondAmount,
                _shareProceeds,
                openSharePrice,
                _sharePrice,
                _sharePrice
            );

            _updateLiquidity(-int256(withdrawalProceeds));
        }
    }

    function _applyCloseShort(
        uint256 _bondAmount,
        uint256 _bondReservesDelta,
        uint256 _sharePayment,
        uint256 _shareReservesDelta,
        uint256 _maturityTime,
        uint256 _sharePrice
    ) internal {
        _marketState.shareReserves += _shareReservesDelta.toUint128();
        _marketState.bondReserves -= _bondReservesDelta.toUint128();

        _updateLiquidity(int256(_sharePayment - _shareReservesDelta));

        uint256 withdrawalSharesOutstanding = _totalSupply[AssetId._WITHDRAWAL_SHARE_ASSET_ID] - _withdrawPool.readyToWithdraw;

        if (withdrawalSharesOutstanding > 0) {
            _updateLiquidity(-int256(_sharePayment));
        }
    }

    function _withdraw(
        uint256 shares,
        address destination,
        bool asUnderlying
    ) internal returns (uint256 amountWithdrawn, uint256 sharePrice) {
        uint256 totalShares_ = totalShares;
        if (shares > totalShares_) {
            shares = totalShares_;
        }
        // uint256 assets = aToken.balanceOf(address(this));
        // uint256 assets = balances[address(this)];
        uint256 withdrawValue = shares * 3;

        totalShares -= shares;

        balances[destination] += withdrawValue;

        sharePrice = 3;
        return (withdrawValue, sharePrice);
    }


    function _updateLiquidity(int256 _shareReservesDelta) internal {
        uint256 shareReserves = _marketState.shareReserves;
        if (_shareReservesDelta != 0 && shareReserves > 0) {
            int256 updatedShareReserves = int256(shareReserves) +
                _shareReservesDelta;

            _marketState.shareReserves = uint256(updatedShareReserves).toUint128();

            _marketState.bondReserves = uint256(_marketState.bondReserves)
                .mulDivDown(_marketState.shareReserves, shareReserves)
                .toUint128();
        }
    }

}