// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

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

contract PoolDeployment is Script {
    using FixedPointMath for *;

    HyperdriveFactory internal constant FACTORY =
        HyperdriveFactory(payable(0x338D5634c391ef47FB797417542aa75F4f71A4a6));

    address internal constant SENDER =
        address(0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8);
    address internal constant DAI =
        address(0x58fa9611D2a14CBec045b92Cef06b600897a4fB6);
    address internal constant SDAI =
        address(0xC672A891525532d29b842B9753046F6d30ce613c);
    address internal constant ERC4626_HYPERDRIVE_DEPLOYER_COORDINATOR =
        address(0x28273c4E6c69317626E14AF3020e063ab215e2b4);
    address internal constant LINKER_FACTORY =
        address(0x13b0AcFA6B77C0464Ce26Ff80da7758b8e1f526E);
    bytes32 internal constant LINKER_CODE_HASH =
        bytes32(
            0xbce832c0ea372ef949945c6a4846b1439b728e08890b93c2aa99e2e3c50ece34
        );
    bytes32 internal constant DEPLOYMENT_ID = bytes32(uint256(0x666666));
    bytes32 internal constant SALT = bytes32(uint256(0xdefeca8));

    uint256 internal constant CONTRIBUTION = 100e18;
    uint256 internal constant FIXED_APR = 0.05e18;

    function setUp() external {}

    function run() external {
        vm.startBroadcast();

        // Set up the pool config.
        IHyperdrive.PoolDeployConfig memory config = IHyperdrive
            .PoolDeployConfig({
                baseToken: IERC20(DAI),
                vaultSharesToken: IERC20(SDAI),
                linkerFactory: LINKER_FACTORY,
                linkerCodeHash: LINKER_CODE_HASH,
                minimumShareReserves: 10e18,
                minimumTransactionAmount: 1e15,
                positionDuration: 14 days,
                checkpointDuration: 1 days,
                timeStretch: 0, // NOTE: Will be overridden.
                governance: FACTORY.hyperdriveGovernance(),
                feeCollector: FACTORY.feeCollector(),
                sweepCollector: FACTORY.sweepCollector(),
                fees: IHyperdrive.Fees({
                    curve: 0.01e18, // 100 bps
                    flat: 0.0005e18.mulDivDown(14 days, 365 days), // 5 bps
                    governanceLP: 0.15e18, // 1500 bps
                    governanceZombie: 0.03e18 // 300 bps
                })
            });

        // Mint DAI.
        ERC20Mintable(DAI).mint(10_000e18);

        // Approve the deployer coordinator.
        ERC20Mintable(DAI).approve(
            ERC4626_HYPERDRIVE_DEPLOYER_COORDINATOR,
            CONTRIBUTION
        );

        // Deploy the targets.
        FACTORY.deployTarget(
            DEPLOYMENT_ID,
            ERC4626_HYPERDRIVE_DEPLOYER_COORDINATOR,
            config,
            new bytes(0),
            FIXED_APR,
            FIXED_APR,
            0,
            SALT
        );
        FACTORY.deployTarget(
            DEPLOYMENT_ID,
            ERC4626_HYPERDRIVE_DEPLOYER_COORDINATOR,
            config,
            new bytes(0),
            FIXED_APR,
            FIXED_APR,
            1,
            SALT
        );
        FACTORY.deployTarget(
            DEPLOYMENT_ID,
            ERC4626_HYPERDRIVE_DEPLOYER_COORDINATOR,
            config,
            new bytes(0),
            FIXED_APR,
            FIXED_APR,
            2,
            SALT
        );
        FACTORY.deployTarget(
            DEPLOYMENT_ID,
            ERC4626_HYPERDRIVE_DEPLOYER_COORDINATOR,
            config,
            new bytes(0),
            FIXED_APR,
            FIXED_APR,
            3,
            SALT
        );
        FACTORY.deployTarget(
            DEPLOYMENT_ID,
            ERC4626_HYPERDRIVE_DEPLOYER_COORDINATOR,
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
            ERC4626_HYPERDRIVE_DEPLOYER_COORDINATOR,
            config,
            new bytes(0),
            CONTRIBUTION,
            FIXED_APR,
            FIXED_APR,
            IHyperdrive.Options({
                destination: SENDER,
                asBase: true,
                extraData: new bytes(0)
            }),
            SALT
        );
        console.log("pool = %s", address(hyperdrive));

        vm.stopBroadcast();
    }
}
