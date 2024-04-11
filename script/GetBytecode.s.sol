// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ETH } from "contracts/src/libraries/Constants.sol";
import { console2 as console } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";
import { MockLido } from "contracts/test/MockLido.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Lib } from "test/utils/Lib.sol";

contract GetBytecode is Script {
    using FixedPointMath for *;
    using AssetId for *;
    using Lib for *;

    HyperdriveFactory internal constant FACTORY =
        HyperdriveFactory(payable(0x338D5634c391ef47FB797417542aa75F4f71A4a6));
    IHyperdrive POOL =
        IHyperdrive(address(0x4E38fd41c03ff11b3426efaE53138b86116797b8));

    address internal constant LIDO =
        address(0x6977eC5fae3862D3471f0f5B6Dcc64cDF5Cfd959);
    address internal constant DAI =
        address(0x58fa9611D2a14CBec045b92Cef06b600897a4fB6);
    address internal constant SDAI =
        address(0xC672A891525532d29b842B9753046F6d30ce613c);
    address internal constant LINKER_FACTORY =
        address(0x13b0AcFA6B77C0464Ce26Ff80da7758b8e1f526E);
    bytes32 internal constant LINKER_CODE_HASH =
        bytes32(
            0xbce832c0ea372ef949945c6a4846b1439b728e08890b93c2aa99e2e3c50ece34
        );

    uint256 internal constant CONTRIBUTION = 1e18;
    uint256 internal constant FIXED_APR = 0.05e18;
    uint256 internal constant POSITION_DURATION = 30 days;

    function setUp() external {}

    function run() external view {
        IHyperdrive steth_hyperdrive = IHyperdrive(
            0x4E38fd41c03ff11b3426efaE53138b86116797b8
        );

        IHyperdrive.PoolConfig memory config = steth_hyperdrive.getPoolConfig();

        console.log("%s", config.initialVaultSharePrice);

        // IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
        //     baseToken: IERC20(ETH),
        //     vaultSharesToken: IERC20(LIDO),
        //     linkerFactory: LINKER_FACTORY,
        //     linkerCodeHash: LINKER_CODE_HASH,
        //     initialVaultSharePrice: 1000001797945915675,
        //     minimumShareReserves: 1e15,
        //     minimumTransactionAmount: 1e15,
        //     positionDuration: POSITION_DURATION,
        //     checkpointDuration: 1 days,
        //     timeStretch: 0, // NOTE: Will be overridden.
        //     governance: FACTORY.hyperdriveGovernance(),
        //     feeCollector: FACTORY.feeCollector(),
        //     sweepCollector: FACTORY.sweepCollector(),
        //     fees: IHyperdrive.Fees({
        //         curve: 0.01e18, // 100 bps
        //         flat: 0.0005e18.mulDivDown(POSITION_DURATION, 365 days), // 5 bps
        //         governanceLP: 0.15e18, // 1500 bps
        //         governanceZombie: 0.03e18 // 300 bps
        //     })
        // });
        //
        // // Deploy
        // bytes memory args = abi.encode(
        //     config,
        //     address(0xc89F3B57367647d44233c79179DfEF36d6fC1118),
        //     address(0x3741C190EE079dC1aFdBa939325695ad2E0FdB25),
        //     address(0xbdFF34ca95aD0cC988E6cDf2E1713cCeB6589455),
        //     address(0xc44BC326831B34bBB125a05Eb826629C378F3055),
        //     address(0xA435ac01A6Bc157669aA153D020544FeC7f2aED3)
        // );
        // console.logBytes(args);
        // bytes memory bytecode = abi.encodePacked(
        //     vm.getCode("StETHHyperdrive.sol:StETHHyperdrive"),
        //     args
        // );
        // console.logBytes(bytecode);
    }
}
