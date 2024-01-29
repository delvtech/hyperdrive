// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IMultiTokenEvents } from "./IMultiTokenEvents.sol";

interface IHyperdriveEvents is IMultiTokenEvents {
    event Initialize(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 vaultSharePrice,
        uint256 apr
    );

    event AddLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 vaultSharePrice,
        uint256 lpSharePrice
    );

    event RemoveLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 vaultSharePrice,
        uint256 withdrawalShareAmount,
        uint256 lpSharePrice
    );

    event RedeemWithdrawalShares(
        address indexed provider,
        uint256 withdrawalShareAmount,
        uint256 baseAmount,
        uint256 vaultSharePrice
    );

    event OpenLong(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 vaultSharePrice,
        uint256 bondAmount
    );

    event OpenShort(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 vaultSharePrice,
        uint256 bondAmount
    );

    event CloseLong(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 vaultSharePrice,
        uint256 bondAmount
    );

    event CloseShort(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 vaultSharePrice,
        uint256 bondAmount
    );

    event CreateCheckpoint(
        uint256 indexed checkpointTime,
        uint256 vaultSharePrice,
        uint256 maturedShorts,
        uint256 maturedLongs,
        uint256 lpSharePrice
    );

    event CollectGovernanceFee(address indexed collector, uint256 fees);

    event GovernanceUpdated(address indexed newGovernance);

    event PauserUpdated(address indexed newPauser);

    event PauseStatusUpdated(bool isPaused);
}
