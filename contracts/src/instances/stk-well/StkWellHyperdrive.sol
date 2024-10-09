// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { Hyperdrive } from "../../external/Hyperdrive.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IStakedToken } from "../../interfaces/IStakedToken.sol";
import { StkWellBase } from "./StkWellBase.sol";

///      ______  __                           _________      _____
///      ___  / / /____  ___________________________  /_________(_)__   ______
///      __  /_/ /__  / / /__  __ \  _ \_  ___/  __  /__  ___/_  /__ | / /  _ \
///      _  __  / _  /_/ /__  /_/ /  __/  /   / /_/ / _  /   _  / __ |/ //  __/
///      /_/ /_/  _\__, / _   ___/\___//_/    \__,_/  /_/    /_/  _____/ \___/
///               /____/   /_/
///                     XXX          ++          ++          XXX
///     ############   XXXXX        ++0+        +0++        XXXXX   ###########
///   ##////////////########       ++00++      ++00++       ########///////////##
///  ##////////////##########      ++000++    ++000++      ##########///////////##
///  ##%%%%%%/////      ######     ++0000+    +0000++     ######     /////%%%%%%##
///    %%%%%%%%&&             ##   ++0000+    +0000++   ##           &&%%%%%%%%%
///         %&&&                ##  +o000+    +000o+  ##              &&&%
///                              ## ++00+-    -+00++ ##
///                               #% ++0+      +0++ %#
///                               ###-:Oo.++++.oO:-###
///                                ##: 00++++++00 :##
///                    #S###########* 0++00+++00++0 *##########S#
///                  #S               % $ 0+++0 $ %              S#
///                #S   ----------   %+++++:#:+++++%-----------    S#
///              #S   ------------- %++++: ### :++++%------------    S#
///             S    ---------------%++++*\ | /*++++%-------------     S
///           #S     --------------- %++++ ~W~ ++++%666--o UUUU o-      S#
///         #S?      ---------------  %+++++~+++++%&&&8 o  \  /  o       ?S#
///        ?*????**+++;::,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,::;+++**????*?
///      #?+////////////////////////////////////////////////////////////////+?#
///    #;;;;;//////////////////////////////////////////////////////////////;;;;;#
///  S;;;;;;;;;//////////////////////////////////////////////////////////;;;;;;;;;S
/// /;;;;;;;;;;;///////////////////////////////////////////////////////;;;;;;;;;;;;\
/// |||OOOOOOOO||OOOOOOOO=========== __  ___        ===========OOOOOOOO||OOOOOOOO|||
/// |||OOOOOOOO||OOOOOOOO===========|  \[__ |   \  /===========OOOOOOOO||OOOOOOOO|||
/// |||OOOOOOOO||OOOOOOOO===========|__/[___|___ \/ ===========OOOOOOOO||OOOOOOOO|||
/// ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
/// |||////////000000000000\\\\\\\\|:::::::::::::::|////////00000000000\\\\\\\\\\|||
/// SSS\\\\\\\\000000000000////////|:::::0x666:::::|\\\\\\\\00000000000//////////SSS
/// SSS|||||||||||||||||||||||||||||:::::::::::::::||||||||||||||||||||||||||||||SSS
/// SSSSSSSS|_______________|______________||_______________|______________|SSSSSSSS
/// SSSSSSSS                                                                SSSSSSSS
/// SSSSSSSS                                                                SSSSSSSS
///
/// @author DELV
/// @title StkWellHyperdrive
/// @notice A Hyperdrive instance that uses a StkWell vault as the yield source.
/// @dev This instance supports the Well staking vault on Base. The vault shares
///      token is staked well. Some high-level features of this yield source:
///
///      - The base token address is the staked token of the vault (the WELL
///        token).
///      - The vault shares token address is the StkWell address.
///      - The vault share price is always one since the staking contract doesn't
///        accrue interest.
///      - Base withdrawals aren't supported since there isn't an instantaneous
///        way to withdraw from StkWell.
///      - The minimum share reserves and minimum transaction amount are both
///        1e15.
///      - WELL rewards accrue to Hyperdrive over time and can be sent to
///        Hyperdrive by calling `claimRewards`.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StkWellHyperdrive is Hyperdrive, StkWellBase {
    using SafeERC20 for ERC20;

    /// @notice Instantiates Hyperdrive with a StkWell vault as the yield source.
    /// @param __name The pool's name.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _target0 The target0 address.
    /// @param _target1 The target1 address.
    /// @param _target2 The target2 address.
    /// @param _target3 The target3 address.
    /// @param _target4 The target4 address.
    constructor(
        string memory __name,
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        address _target0,
        address _target1,
        address _target2,
        address _target3,
        address _target4
    )
        Hyperdrive(
            __name,
            _config,
            __adminController,
            _target0,
            _target1,
            _target2,
            _target3,
            _target4
        )
    {
        // Approve the vault with 1 wei. This ensures that all of the subsequent
        // approvals will be writing to a dirty storage slot.
        ERC20(address(_config.baseToken)).forceApprove(
            address(_config.vaultSharesToken),
            1
        );
    }

    /// @notice Allows anyone to claim the Well rewards accrued by this contract.
    ///         These rewards will need to be swept by the sweep collector to be
    ///         distributed.
    function claimRewards() external {
        IStakedToken stkWell = IStakedToken(address(_vaultSharesToken));
        stkWell.claimRewards(
            address(this),
            stkWell.stakerRewardsToClaim(address(this))
        );
    }
}
