// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { console2 as console } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";
import { MockLido } from "contracts/test/MockLido.sol";
import { Lib } from "test/utils/Lib.sol";

contract PoolDeployment is Script {
    using FixedPointMath for *;
    using Lib for *;

    HyperdriveFactory internal constant FACTORY =
        HyperdriveFactory(payable(0x338D5634c391ef47FB797417542aa75F4f71A4a6));

    address internal constant SENDER =
        address(0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8);
    address internal constant LIDO =
        address(0x6977eC5fae3862D3471f0f5B6Dcc64cDF5Cfd959);
    address internal constant STETH_HYPERDRIVE_DEPLOYER_COORDINATOR =
        address(0x6aa9615F0dF3F3891e8d2723A6b2A7973b5da299);
    address internal constant LINKER_FACTORY =
        address(0x13b0AcFA6B77C0464Ce26Ff80da7758b8e1f526E);
    bytes32 internal constant LINKER_CODE_HASH =
        bytes32(
            0xbce832c0ea372ef949945c6a4846b1439b728e08890b93c2aa99e2e3c50ece34
        );
    bytes32 internal constant DEPLOYMENT_ID = bytes32(uint256(0xf00b00));
    bytes32 internal constant SALT = bytes32(uint256(0xB00B5));

    uint256 internal constant CONTRIBUTION = 1e18;
    uint256 internal constant FIXED_APR = 0.05e18;
    uint256 internal constant POSITION_DURATION = 30 days;

    function setUp() external {}

    function run() external {
        vm.startBroadcast();

        // Set up the pool config.
        IHyperdrive.PoolDeployConfig memory config = IHyperdrive
            .PoolDeployConfig({
                baseToken: IERC20(ETH),
                vaultSharesToken: IERC20(LIDO),
                linkerFactory: LINKER_FACTORY,
                linkerCodeHash: LINKER_CODE_HASH,
                minimumShareReserves: 1e15,
                minimumTransactionAmount: 1e15,
                positionDuration: POSITION_DURATION,
                checkpointDuration: 1 days,
                timeStretch: 0, // NOTE: Will be overridden.
                governance: FACTORY.hyperdriveGovernance(),
                feeCollector: FACTORY.feeCollector(),
                sweepCollector: FACTORY.sweepCollector(),
                fees: IHyperdrive.Fees({
                    curve: 0.01e18, // 100 bps
                    flat: 0.0005e18.mulDivDown(POSITION_DURATION, 365 days), // 5 bps
                    governanceLP: 0.15e18, // 1500 bps
                    governanceZombie: 0.03e18 // 300 bps
                })
            });

        // Mint LIDO.
        // ERC20Mintable(LIDO).mint(500e18);

        // Approve the deployer coordinator.
        ERC20Mintable(LIDO).approve(
            STETH_HYPERDRIVE_DEPLOYER_COORDINATOR,
            2 * CONTRIBUTION
        );

        console.log(
            "balance of = %s",
            ERC20Mintable(LIDO).balanceOf(SENDER).toString(18)
        );
        console.log(
            "allowance of = %s",
            ERC20Mintable(LIDO)
                .allowance(SENDER, STETH_HYPERDRIVE_DEPLOYER_COORDINATOR)
                .toString(18)
        );

        // Deploy the targets.
        FACTORY.deployTarget(
            DEPLOYMENT_ID,
            STETH_HYPERDRIVE_DEPLOYER_COORDINATOR,
            config,
            new bytes(0),
            FIXED_APR,
            FIXED_APR,
            0,
            SALT
        );
        FACTORY.deployTarget(
            DEPLOYMENT_ID,
            STETH_HYPERDRIVE_DEPLOYER_COORDINATOR,
            config,
            new bytes(0),
            FIXED_APR,
            FIXED_APR,
            1,
            SALT
        );
        FACTORY.deployTarget(
            DEPLOYMENT_ID,
            STETH_HYPERDRIVE_DEPLOYER_COORDINATOR,
            config,
            new bytes(0),
            FIXED_APR,
            FIXED_APR,
            2,
            SALT
        );
        FACTORY.deployTarget(
            DEPLOYMENT_ID,
            STETH_HYPERDRIVE_DEPLOYER_COORDINATOR,
            config,
            new bytes(0),
            FIXED_APR,
            FIXED_APR,
            3,
            SALT
        );
        FACTORY.deployTarget(
            DEPLOYMENT_ID,
            STETH_HYPERDRIVE_DEPLOYER_COORDINATOR,
            config,
            new bytes(0),
            FIXED_APR,
            FIXED_APR,
            4,
            SALT
        );

        // Deploy a pool.
        IHyperdrive hyperdrive = FACTORY.deployAndInitialize(
            DEPLOYMENT_ID,
            STETH_HYPERDRIVE_DEPLOYER_COORDINATOR,
            config,
            new bytes(0),
            CONTRIBUTION,
            FIXED_APR,
            FIXED_APR,
            IHyperdrive.Options({
                destination: SENDER,
                asBase: false,
                extraData: new bytes(0)
            }),
            SALT
        );
        console.log("pool = %s", address(hyperdrive));

        IHyperdrive.PoolInfo memory p = hyperdrive.getPoolInfo();

        console.log("shareReserves: %s", p.shareReserves);
        console.log("shareAdjustment: %s", p.shareAdjustment);
        console.log("zombieBaseProceeds: %s", p.zombieBaseProceeds);
        console.log("zombieShareReserves: %s", p.zombieShareReserves);
        console.log("bondReserves: %s", p.bondReserves);
        console.log("lpTotalSupply: %s", p.lpTotalSupply);
        console.log("vaultSharePrice: %s", p.vaultSharePrice);
        console.log("longsOutstanding: %s", p.longsOutstanding);
        console.log("longAverageMaturityTime: %s", p.longAverageMaturityTime);
        console.log("shortsOutstanding: %s", p.shortsOutstanding);
        console.log("shortAverageMaturityTime: %s", p.shortAverageMaturityTime);
        console.log(
            "withdrawalSharesReadyToWithdraw: %s",
            p.withdrawalSharesReadyToWithdraw
        );
        console.log("withdrawalSharesProceeds: %s", p.withdrawalSharesProceeds);
        console.log("lpSharePrice: %s", p.lpSharePrice);
        console.log("longExposure: %s", p.longExposure);

        vm.stopBroadcast();
    }
}
