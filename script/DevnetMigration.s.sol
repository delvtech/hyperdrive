// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { Script } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { MultiRolesAuthority } from "solmate/auth/authorities/MultiRolesAuthority.sol";
import { ERC4626HyperdriveDeployer } from "contracts/src/factory/ERC4626HyperdriveDeployer.sol";
import { ERC4626HyperdriveFactory } from "contracts/src/factory/ERC4626HyperdriveFactory.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";
import { MockHyperdriveMath } from "contracts/test/MockHyperdriveMath.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

/// @author DELV
/// @title DevnetMigration
/// @notice This script deploys a mock ERC4626 yield source and a Hyperdrive
///         factory on top of it. For convenience, it also deploys a Hyperdrive
///         pool with a 1 week duration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract DevnetMigration is Script {
    using stdJson for string;
    using HyperdriveUtils for *;

    function setUp() external {}

    struct Config {
        // admin configuration
        address admin;
        bool isCompetitionMode;
        // base token configuration
        string baseTokenName;
        string baseTokenSymbol;
        uint8 baseTokenDecimals;
        // vault configuration
        string vaultName;
        string vaultSymbol;
        uint256 vaultStartingRate;
        // factory configuration
        uint256 factoryCurveFee;
        uint256 factoryFlatFee;
        uint256 factoryGovernanceFee;
        uint256 factoryMaxCurveFee;
        uint256 factoryMaxFlatFee;
        uint256 factoryMaxGovernanceFee;
        // hyperdrive configuration
        uint256 hyperdriveContribution;
        uint256 hyperdriveFixedRate;
        uint256 hyperdriveInitialSharePrice;
        uint256 hyperdriveMinimumShareReserves;
        uint256 hyperdriveMinimumTransactionAmount;
        uint256 hyperdrivePositionDuration;
        uint256 hyperdriveCheckpointDuration;
        uint256 hyperdriveTimeStretchApr;
        uint256 hyperdriveOracleSize;
        uint256 hyperdriveUpdateGap;
    }

    function run() external {
        vm.startBroadcast();

        // Get the migration configuration from the environment and the defaults.
        uint256 baseTokenDecimals = vm.envOr(
            "BASE_TOKEN_DECIMALS",
            uint256(18)
        );
        if (baseTokenDecimals > type(uint8).max) {
            revert("BASE_TOKEN_DECIMALS exceeds uint8");
        }
        Config memory config = Config({
            admin: vm.envOr("ADMIN", msg.sender),
            isCompetitionMode: vm.envOr("IS_COMPETITION_MODE", false),
            baseTokenName: vm.envOr("BASE_TOKEN_NAME", string("Base")),
            baseTokenSymbol: vm.envOr("BASE_TOKEN_SYMBOL", string("BASE")),
            baseTokenDecimals: uint8(baseTokenDecimals),
            vaultName: vm.envOr("VAULT_NAME", string("Delvnet Yield Source")),
            vaultSymbol: vm.envOr("VAULT_SYMBOL", string("DELV")),
            vaultStartingRate: vm.envOr(
                "VAULT_STARTING_RATE",
                uint256(0.05e18)
            ),
            factoryCurveFee: vm.envOr("FACTORY_CURVE_FEE", uint256(0.1e18)),
            factoryFlatFee: vm.envOr("FACTORY_FLAT_FEE", uint256(0.0005e18)),
            factoryGovernanceFee: vm.envOr(
                "FACTORY_GOVERNANCE_FEE",
                uint256(0.15e18)
            ),
            factoryMaxCurveFee: vm.envOr(
                "FACTORY_MAX_CURVE_FEE",
                uint256(0.3e18)
            ),
            factoryMaxFlatFee: vm.envOr(
                "FACTORY_MAX_FLAT_FEE",
                uint256(0.0015e18)
            ),
            factoryMaxGovernanceFee: vm.envOr(
                "FACTORY_MAX_GOVERNANCE_FEE",
                uint256(0.3e18)
            ),
            hyperdriveContribution: vm.envOr(
                "HYPERDRIVE_CONTRIBUTION",
                uint256(100_000_000e18)
            ),
            hyperdriveFixedRate: vm.envOr(
                "HYPERDRIVE_FIXED_RATE",
                uint256(0.05e18)
            ),
            hyperdriveInitialSharePrice: vm.envOr(
                "HYPERDRIVE_INITIAL_SHARE_PRICE",
                uint256(1e18)
            ),
            hyperdriveMinimumShareReserves: vm.envOr(
                "HYPERDRIVE_MINIMUM_SHARE_RESERVES",
                uint256(10e18)
            ),
            hyperdriveMinimumTransactionAmount: vm.envOr(
                "HYPERDRIVE_MINIMUM_TRANSACTION_AMOUNT",
                uint256(0.001e18)
            ),
            hyperdrivePositionDuration: vm.envOr(
                "HYPERDRIVE_POSITION_DURATION",
                uint256(1 weeks)
            ),
            hyperdriveCheckpointDuration: vm.envOr(
                "HYPERDRIVE_CHECKPOINT_DURATION",
                uint256(1 hours)
            ),
            hyperdriveTimeStretchApr: vm.envOr(
                "HYPERDRIVE_TIME_STRETCH_APR",
                uint256(0.05e18)
            ),
            hyperdriveOracleSize: vm.envOr(
                "HYPERDRIVE_ORACLE_SIZE",
                uint256(10)
            ),
            hyperdriveUpdateGap: vm.envOr(
                "HYPERDRIVE_UPDATE_GAP",
                uint256(1 hours)
            )
        });

        // Deploy the base token and the vault.
        ERC20Mintable baseToken = new ERC20Mintable(
            config.baseTokenName,
            config.baseTokenSymbol,
            config.baseTokenDecimals,
            msg.sender,
            config.isCompetitionMode
        );
        MockERC4626 pool = new MockERC4626(
            baseToken,
            config.vaultName,
            config.vaultSymbol,
            config.vaultStartingRate,
            msg.sender,
            config.isCompetitionMode
        );
        if (config.isCompetitionMode) {
            baseToken.setUserRole(address(pool), 1, true);
            baseToken.setRoleCapability(
                1,
                bytes4(keccak256("mint(uint256)")),
                true
            );
            baseToken.setRoleCapability(
                1,
                bytes4(keccak256("burn(uint256)")),
                true
            );
        }

        // Deploy the Hyperdrive factory.
        ERC4626HyperdriveFactory factory;
        {
            address[] memory defaultPausers = new address[](1);
            defaultPausers[0] = config.admin;
            HyperdriveFactory.FactoryConfig
                memory factoryConfig = HyperdriveFactory.FactoryConfig({
                    governance: config.admin,
                    hyperdriveGovernance: config.admin,
                    feeCollector: config.admin,
                    fees: IHyperdrive.Fees({
                        curve: config.factoryCurveFee,
                        flat: config.factoryFlatFee,
                        governance: config.factoryGovernanceFee
                    }),
                    maxFees: IHyperdrive.Fees({
                        curve: config.factoryMaxCurveFee,
                        flat: config.factoryMaxFlatFee,
                        governance: config.factoryMaxGovernanceFee
                    }),
                    defaultPausers: defaultPausers
                });
            ForwarderFactory forwarderFactory = new ForwarderFactory();
            ERC4626HyperdriveDeployer deployer = new ERC4626HyperdriveDeployer(
                address(pool)
            );
            factory = new ERC4626HyperdriveFactory(
                factoryConfig,
                deployer,
                address(forwarderFactory),
                forwarderFactory.ERC20LINK_HASH(),
                new address[](0)
            );
        }

        // Deploy and initialize an initial Hyperdrive instance for the devnet.
        IHyperdrive hyperdrive;
        {
            uint256 contribution = config.hyperdriveContribution;
            uint256 fixedRate = config.hyperdriveFixedRate;
            baseToken.mint(msg.sender, contribution);
            baseToken.approve(address(factory), contribution);
            IHyperdrive.PoolConfig memory poolConfig = IHyperdrive.PoolConfig({
                baseToken: IERC20(address(baseToken)),
                initialSharePrice: config.hyperdriveInitialSharePrice,
                minimumShareReserves: config.hyperdriveMinimumShareReserves,
                minimumTransactionAmount: config
                    .hyperdriveMinimumTransactionAmount,
                positionDuration: config.hyperdrivePositionDuration,
                checkpointDuration: config.hyperdriveCheckpointDuration,
                timeStretch: config
                    .hyperdriveTimeStretchApr
                    .calculateTimeStretch(),
                governance: config.admin,
                feeCollector: config.admin,
                fees: IHyperdrive.Fees({
                    curve: config.factoryCurveFee,
                    flat: config.factoryFlatFee,
                    governance: config.factoryGovernanceFee
                }),
                oracleSize: config.hyperdriveOracleSize,
                updateGap: config.hyperdriveUpdateGap
            });
            hyperdrive = factory.deployAndInitialize(
                poolConfig,
                new bytes32[](0),
                contribution,
                fixedRate,
                new bytes(0),
                address(pool)
            );
        }

        // Deploy the MockHyperdriveMath contract.
        MockHyperdriveMath mockHyperdriveMath = new MockHyperdriveMath();

        // Transfer ownership of the base token and vault to the admin address
        // now that we're done minting tokens.
        baseToken.transferOwnership(config.admin);
        pool.transferOwnership(config.admin);

        vm.stopBroadcast();

        // Writes the addresses to a file.
        string memory result = "result";
        vm.serializeAddress(result, "baseToken", address(baseToken));
        vm.serializeAddress(result, "hyperdriveFactory", address(factory));
        // TODO: This is deprecated and should be removed by 0.0.11.
        vm.serializeAddress(result, "mockHyperdrive", address(hyperdrive));
        result = vm.serializeAddress(
            result,
            "mockHyperdriveMath",
            address(mockHyperdriveMath)
        );
        result.write("./artifacts/script_addresses.json");
    }
}
