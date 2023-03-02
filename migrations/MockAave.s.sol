// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// import "../test/mocks/MockHyperdriveTestnet.sol";
import "../test/mocks/ERC20Mintable.sol";
import "../test/mocks/aave/MockACLManager.sol";
import "../test/mocks/aave/MockAavePool.sol";
import "../test/mocks/aave/MockPoolAddressesProvider.sol";

import { AToken } from "@aave/core-v3/contracts/protocol/tokenization/AToken.sol";
import { ConfiguratorInputTypes } from "@aave/core-v3/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";
import { DefaultReserveInterestRateStrategy } from "@aave/core-v3/contracts/protocol/pool/DefaultReserveInterestRateStrategy.sol";
import { DelegationAwareAToken } from "@aave/core-v3/contracts/protocol/tokenization/DelegationAwareAToken.sol";
import { IAaveIncentivesController } from "@aave/core-v3/contracts/interfaces/IAaveIncentivesController.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { MockReserveInterestRateStrategy } from "@aave/core-v3/contracts/mocks/tests/MockReserveInterestRateStrategy.sol";
import { PoolConfigurator } from "@aave/core-v3/contracts/protocol/pool/PoolConfigurator.sol";
import { ReservesSetupHelper } from "@aave/core-v3/contracts/deployments/ReservesSetupHelper.sol";
import { StableDebtToken } from "@aave/core-v3/contracts/protocol/tokenization/StableDebtToken.sol";
import { VariableDebtToken } from "@aave/core-v3/contracts/protocol/tokenization/VariableDebtToken.sol";

contract MockAaveScript is Script {
    string constant MARKET_ID = "Aave Testnet Market";
    ConfiguratorInputTypes.InitReserveInput[] internal reserveConfigs;

    function setUp() public {}

    function run() public {
        // Fetch deployer private key from env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start script with deployer as msg.sender
        vm.startBroadcast(deployerPrivateKey);
        address deployer = msg.sender;

        // Create mock ERC20 token
        ERC20Mintable baseToken = new ERC20Mintable();

        // Deploys the market registry
        // This contract also acts as a proxy factory
        MockPoolAddressesProvider poolAddressesProvider = new MockPoolAddressesProvider(
                MARKET_ID,
                deployer
            );

        // Deploy mock ACL manager
        MockACLManager aclManager = new MockACLManager();
        // Set ACL manager of registry
        poolAddressesProvider.setACLManager(address(aclManager));

        // Deploy Pool contract
        MockAavePool mockAavePool = new MockAavePool(poolAddressesProvider);
        mockAavePool.initialize(poolAddressesProvider);
        poolAddressesProvider.setPoolImpl(address(mockAavePool));
        IPool poolProxy = IPool(poolAddressesProvider.getPool());

        // Deploy Pool Configurator contract
        PoolConfigurator poolConfig = new PoolConfigurator();
        poolConfig.initialize(poolAddressesProvider);
        poolAddressesProvider.setPoolConfiguratorImpl(address(poolConfig));

        // dummy data
        bytes memory _param = new bytes(0);

        // Mock interest rate strategy
        // Source: https://github.com/aave/aave-v3-deploy/blob/main/markets/test/rateStrategies.ts#L28
        MockReserveInterestRateStrategy mockInterestRateStrategy = new MockReserveInterestRateStrategy(
                poolAddressesProvider,
                0.8e27,
                0,
                0.04e27,
                0.75e27,
                0.02e27,
                0.75e27
            );

        // Deploy aTokens contracts
        AToken aTokenImpl = new AToken(poolProxy);
        aTokenImpl.initialize(
            poolProxy,
            address(0),
            address(0),
            IAaveIncentivesController(address(0)),
            0,
            "ATOKEN_IMPL",
            "ATOKEN_IMPL",
            _param
        );

        DelegationAwareAToken delegationAwareATokenImpl = new DelegationAwareAToken(
                poolProxy
            );
        delegationAwareATokenImpl.initialize(
            poolProxy,
            address(0),
            address(0),
            IAaveIncentivesController(address(0)),
            0,
            "DELEGATION_AWARE_ATOKEN_IMPL",
            "DELEGATION_AWARE_ATOKEN_IMPL",
            _param
        );

        StableDebtToken stableDebtTokenImpl = new StableDebtToken(poolProxy);
        stableDebtTokenImpl.initialize(
            poolProxy,
            address(0),
            IAaveIncentivesController(address(0)),
            0,
            "STABLE_DEBT_ATOKEN_IMPL",
            "STABLE_DEBT_ATOKEN_IMPL",
            _param
        );

        VariableDebtToken variableDebtTokenImpl = new VariableDebtToken(
            poolProxy
        );
        variableDebtTokenImpl.initialize(
            poolProxy,
            address(0),
            IAaveIncentivesController(address(0)),
            0,
            "VARIABLE_DEBT_ATOKEN_IMPL",
            "VARIABLE_DEBT_ATOKEN_IMPL",
            _param
        );

        // Reserve configuration for base token
        ConfiguratorInputTypes.InitReserveInput
            memory baseReserveConfig = ConfiguratorInputTypes.InitReserveInput({
                aTokenImpl: address(aTokenImpl),
                stableDebtTokenImpl: address(stableDebtTokenImpl),
                variableDebtTokenImpl: address(variableDebtTokenImpl),
                underlyingAssetDecimals: 18,
                interestRateStrategyAddress: address(mockInterestRateStrategy),
                underlyingAsset: address(baseToken),
                treasury: address(0),
                incentivesController: address(0),
                aTokenName: "Aave BASE Token",
                aTokenSymbol: "aBASE",
                variableDebtTokenName: "Aave BASE Variable Debt Token",
                variableDebtTokenSymbol: "a-vd-BASE",
                stableDebtTokenName: "Aave BASE Stable Debt Token",
                stableDebtTokenSymbol: "a-sd-BASE",
                params: _param
            });

        // Initialize new reserves
        reserveConfigs.push(baseReserveConfig);
        poolConfig.initReserves(reserveConfigs);

        // Mint tokens to deployer
        baseToken.mint(10_000_000e18);

        // Approve pool proxy contract
        baseToken.approve(address(poolProxy), 100_000e18);

        // Supply base tokens to market
        poolProxy.supply(address(baseToken), 100_000e18, msg.sender, 0);

        vm.stopBroadcast();
    }
}
