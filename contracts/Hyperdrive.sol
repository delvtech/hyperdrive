// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ElementError } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
import { IERC20Mintable } from "contracts/interfaces/IERC20Mintable.sol";

contract Hyperdrive {
    /// Tokens ///

    IERC20 public immutable baseToken;
    IERC20Mintable public immutable lpToken;

    /// Time ///

    uint256 public immutable termLength;
    uint256 public immutable timeStretch;

    /// Market state ///

    uint256 public shareReserves;
    uint256 public bondReserves;
    uint256 public baseBuffer;
    uint256 public bondBuffer;
    uint256 public sharePrice;
    uint256 public immutable initialSharePrice;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _baseToken The base asset of this Hyperdrive instance.
    /// @param _lpToken The LP token of this Hyperdrive instance.
    /// @param _termLength The length of the terms supported by this Hyperdrive in seconds.
    /// @param _timeStretch The time stretch of the pool.
    constructor(
        IERC20 _baseToken,
        IERC20Mintable _lpToken,
        uint256 _termLength,
        uint256 _timeStretch
    ) {
        baseToken = _baseToken;
        lpToken = _lpToken;
        termLength = _termLength;
        timeStretch = _timeStretch;

        // TODO: This isn't correct. This will need to be updated when asset
        // delegation is implemented.
        initialSharePrice = FixedPointMath.ONE_18;
        sharePrice = FixedPointMath.ONE_18;
    }

    /// @notice Allows the first LP to initialize the market with a target APR.
    /// @param _contribution The amount of base asset to contribute.
    /// @param _apr The target APR.
    function initialize(uint256 _contribution, uint256 _apr) external {
        // Ensure that the pool hasn't been initialized yet.
        if (shareReserves > 0) {
            revert ElementError.PoolAlreadyInitialized();
        }

        // Pull the contribution into the contract.
        baseToken.transferFrom(msg.sender, address(this), _contribution);

        // Update the reserves.
        shareReserves = _contribution;
        bondReserves = HyperdriveMath.calculateBondReserves(
            _contribution,
            initialSharePrice,
            sharePrice,
            _apr,
            termLength,
            timeStretch
        );

        // Mint LP tokens for the initializer.
        lpToken.mint(msg.sender, _contribution);
    }
}
