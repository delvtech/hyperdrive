// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { Authority } from "solmate/auth/Auth.sol";
import { MultiRolesAuthority } from "solmate/auth/authorities/MultiRolesAuthority.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

contract ERC20Mintable is ERC20, MultiRolesAuthority {
    bool public immutable isCompetitionMode;
    uint256 public maxMintAmount;
    mapping(address => bool) public isUnrestricted;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        address admin,
        bool isCompetitionMode_,
        uint256 maxMintAmount_
    )
        ERC20(name, symbol, decimals)
        MultiRolesAuthority(admin, Authority(address(address(this))))
    {
        isCompetitionMode = isCompetitionMode_;
        maxMintAmount = maxMintAmount_;
    }

    modifier requiresAuthDuringCompetition() {
        if (isCompetitionMode) {
            require(
                isAuthorized(msg.sender, msg.sig),
                "ERC20Mintable: not authorized"
            );
        }
        _;
    }

    function mint(uint256 amount) external requiresAuthDuringCompetition {
        if (!isUnrestricted[msg.sender]) {
            require(
                amount <= maxMintAmount,
                "ERC20Mintable: Invalid mint amount"
            );
        }
        _mint(msg.sender, amount);
    }

    function mint(
        address destination,
        uint256 amount
    ) external requiresAuthDuringCompetition {
        if (!isUnrestricted[msg.sender]) {
            require(
                amount <= maxMintAmount,
                "ERC20Mintable: Invalid mint amount"
            );
        }
        _mint(destination, amount);
    }

    function burn(uint256 amount) external requiresAuthDuringCompetition {
        _burn(msg.sender, amount);
    }

    function burn(
        address destination,
        uint256 amount
    ) external requiresAuthDuringCompetition {
        _burn(destination, amount);
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
}
