// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { HyperdriveStorage, MultiTokenStorage, IERC20 } from "../../contracts/src/HyperdriveStorage.sol";
import { IHyperdrive } from "../../contracts/src/interfaces/IHyperdrive.sol";

abstract contract HyperdriveStorageGetters is HyperdriveStorage {

    function factory() public view returns (address) {
        return _factory;
    }

    function linkerCodeHash() public view returns (bytes32) {
        return _linkerCodeHash;
    }

    function balanceOfByToken(uint256 tokenId, address account) public view returns (uint256) {
        return _balanceOf[tokenId][account];
    }

    function totalSupplyByToken(uint256 tokenId) public view returns (uint256) {
        return _totalSupply[tokenId];
    }

    function isApprovedForAllByToken(address owner, address spender) public view returns (bool) {
        return _isApprovedForAll[owner][spender];
    }

    function perTokenApprovals(uint256 tokenId, address owner, address spender) public view returns (uint256) {
        return _perTokenApprovals[tokenId][owner][spender];
    }
        
    function baseToken() public view returns (IERC20) {
        return _baseToken;
    }

    function checkpointDuration() public view returns (uint256) {
        return _checkpointDuration;
    }

    function positionDuration() public view returns (uint256) {
        return _positionDuration;
    }

    function timeStretch() public view returns (uint256) {
        return _timeStretch;
    }

    function initialSharePrice() public view returns (uint256) {
        return _initialSharePrice;
    }

    function marketState() public view returns (IHyperdrive.MarketState memory state) {
        state = _marketState;
    }

    function stateShareReserves() public view returns (uint128) {
        return _marketState.shareReserves;
    }

    function stateBondReserves() public view returns (uint128) {
        return _marketState.bondReserves;
    }

    function withdrawPool() public view returns (IHyperdrive.WithdrawPool memory withdrawPool) {
        withdrawPool = _withdrawPool;
    }

    function curveFee() public view returns (uint256) {
        return _curveFee;
    }

    function flatFee() public view returns (uint256) {
        return _flatFee;
    }

    function governanceFee() public view returns (uint256) {
        return _governanceFee;
    }

    function checkPoints(uint256 checkpointTime) public view returns (IHyperdrive.Checkpoint memory checkpoint) {
        checkpoint = _checkpoints[checkpointTime];
    }

    function checkPointSharePrice(uint256 checkpointTime) public view returns (uint128) {
        return _checkpoints[checkpointTime].sharePrice;
    }

    function pausers(address who) public view returns (bool) {
        return _pausers[who];
    }

    function governanceFeesAccrued() public view returns (uint256) {
        return _governanceFeesAccrued;
    }

    function governance() public view returns (address) {
        return _governance;
    }

    function updateGap() public view returns (uint256) {
        return _updateGap;
    }
}
