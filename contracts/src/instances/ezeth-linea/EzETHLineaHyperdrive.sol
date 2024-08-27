// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { Hyperdrive } from "../../external/Hyperdrive.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IXRenzoDeposit } from "../../interfaces/IXRenzoDeposit.sol";
import { EzETHLineaBase } from "./EzETHLineaBase.sol";

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
/// @title EzETHLineaHyperdrive
/// @notice A Hyperdrive instance that uses EzETH on Linea as a yield source.
/// @dev This instance supports the Renzo protocol on Linea. The vault shares token
///      is the rebasing LRT token xezETH. There are a few special things about
///      this integration:
///
///      - The base token address is the ETH constant.
///      - The vault shares token address is the xezETH address.
///      - The vault share price is provided by an oracle.
///      - Interest accrues sporadically when the oracle is updated.
///      - Base deposits aren't supported since there is a deposit fee for
///        minting xezETH.
///      - Base withdrawals aren't supported since there isn't an instantaneous
///        way to withdraw from xezETH.
///      - The minimum share reserves and minimum transaction amount are both
///        1e15.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EzETHLineaHyperdrive is Hyperdrive, EzETHLineaBase {
    /// @notice Instantiates Hyperdrive with a EzETHLinea vault as the yield source.
    /// @param __name The pool's name.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _target0 The target0 address.
    /// @param _target1 The target1 address.
    /// @param _target2 The target2 address.
    /// @param _target3 The target3 address.
    /// @param _target4 The target4 address.
    /// @param __xRenzoDeposit The xRenzoDeposit contract that provides the
    ///        vault share price.
    constructor(
        string memory __name,
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        address _target0,
        address _target1,
        address _target2,
        address _target3,
        address _target4,
        IXRenzoDeposit __xRenzoDeposit
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
        EzETHLineaBase(__xRenzoDeposit)
    {}
}
