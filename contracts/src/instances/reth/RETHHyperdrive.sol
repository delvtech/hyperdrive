// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { Hyperdrive } from "../../external/Hyperdrive.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { IRETHHyperdriveCore } from "../../interfaces/IRETHHyperdriveCore.sol";
import { ETH } from "../../libraries/Constants.sol";
import { IRocketStorage } from "../../interfaces/IRocketStorage.sol";
import { RETHBase } from "./RETHBase.sol";

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
/// @title RETHHyperdrive
/// @notice A Hyperdrive instance that uses RETH as the yield source.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract RETHHyperdrive is IRETHHyperdriveCore, Hyperdrive, RETHBase {
    /// @notice Instantiates Hyperdrive with RETH as the yield source.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _target0 The target0 address.
    /// @param _target1 The target1 address.
    /// @param _target2 The target2 address.
    /// @param _target3 The target3 address.
    /// @param _target4 The target4 address.
    /// @param __rocketStorage The Rocket Pool storage contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _target0,
        address _target1,
        address _target2,
        address _target3,
        address _target4,
        IRocketStorage __rocketStorage
    )
        Hyperdrive(_config, _target0, _target1, _target2, _target3, _target4)
        RETHBase(__rocketStorage)
    {
        // Ensure that the base token address is properly configured.
        if (address(_config.baseToken) != ETH) {
            revert IHyperdrive.InvalidBaseToken();
        }
    }

    /// @inheritdoc IRETHHyperdriveCore
    function sweep(IERC20) external {
        _delegate(target0);
    }
}