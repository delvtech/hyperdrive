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
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = msg.sender;

        ERC20Mintable baseToken = new ERC20Mintable();

        // Create Market Registry
        MockPoolAddressesProvider poolAddressesProvider = new MockPoolAddressesProvider(
                MARKET_ID,
                deployer
            );

        // Create Pool impl
        MockAavePool mockAavePool = new MockAavePool(poolAddressesProvider);

        // Initialize pool
        mockAavePool.initialize(poolAddressesProvider);

        MockACLManager aclManager = new MockACLManager();
        poolAddressesProvider.setACLManager(address(aclManager));

        // setup utils
        ReservesSetupHelper reservesSetupHelper = new ReservesSetupHelper();
        poolAddressesProvider.setPoolImpl(address(mockAavePool));
        console.log("after getPool", poolAddressesProvider.getPool());

        PoolConfigurator poolConfig = new PoolConfigurator();
        poolConfig.initialize(poolAddressesProvider);
        poolAddressesProvider.setPoolConfiguratorImpl(address(poolConfig));

        bytes memory _param = new bytes(0);

        MockReserveInterestRateStrategy strat = new MockReserveInterestRateStrategy(
                poolAddressesProvider,
                0.8e27,
                0,
                0.04e27,
                0.75e27,
                0.02e27,
                0.75e27
            );

        // setup token impls
        AToken aTokenImpl = new AToken(IPool(poolAddressesProvider.getPool()));
        aTokenImpl.initialize(
            IPool(poolAddressesProvider.getPool()),
            address(0),
            address(0),
            IAaveIncentivesController(address(0)),
            0,
            "DELEGATION_AWARE_ATOKEN_IMPL",
            "DELEGATION_AWARE_ATOKEN_IMPL",
            _param
        );
        DelegationAwareAToken delegationAwareATokenImpl = new DelegationAwareAToken(
                IPool(poolAddressesProvider.getPool())
            );
        delegationAwareATokenImpl.initialize(
            IPool(poolAddressesProvider.getPool()),
            address(0),
            address(0),
            IAaveIncentivesController(address(0)),
            0,
            "DELEGATION_AWARE_ATOKEN_IMPL",
            "DELEGATION_AWARE_ATOKEN_IMPL",
            _param
        );

        StableDebtToken stableDebtTokenImpl = new StableDebtToken(
            IPool(poolAddressesProvider.getPool())
        );
        stableDebtTokenImpl.initialize(
            IPool(poolAddressesProvider.getPool()),
            address(0),
            IAaveIncentivesController(address(0)),
            0,
            "DELEGATION_AWARE_ATOKEN_IMPL",
            "DELEGATION_AWARE_ATOKEN_IMPL",
            _param
        );

        VariableDebtToken variableDebtTokenImpl = new VariableDebtToken(
            IPool(poolAddressesProvider.getPool())
        );
        variableDebtTokenImpl.initialize(
            IPool(poolAddressesProvider.getPool()),
            address(0),
            IAaveIncentivesController(address(0)),
            0,
            "DELEGATION_AWARE_ATOKEN_IMPL",
            "DELEGATION_AWARE_ATOKEN_IMPL",
            _param
        );

        ConfiguratorInputTypes.InitReserveInput
            memory baseReserveConfig = ConfiguratorInputTypes.InitReserveInput({
                aTokenImpl: address(aTokenImpl),
                stableDebtTokenImpl: address(stableDebtTokenImpl),
                variableDebtTokenImpl: address(variableDebtTokenImpl),
                underlyingAssetDecimals: 18,
                interestRateStrategyAddress: address(strat),
                underlyingAsset: address(baseToken),
                treasury: address(0),
                incentivesController: address(0),
                aTokenName: "Aave BASE Token",
                aTokenSymbol: "aBASE",
                variableDebtTokenName: "Aave BASE Variable Debt Token",
                variableDebtTokenSymbol: "a-vd-BASE",
                stableDebtTokenName: "Aave BASE Stable Debt Token",
                stableDebtTokenSymbol: "a-vd-BASE",
                params: _param
            });

        reserveConfigs.push(baseReserveConfig);

        poolConfig.initReserves(reserveConfigs);

        baseToken.mint(1_000_000e18);

        baseToken.approve(poolAddressesProvider.getPool(), 100_000e18);

        IPool realPool = IPool(poolAddressesProvider.getPool());
        realPool.supply(address(baseToken), 100e18, msg.sender, 0);

        vm.stopBroadcast();
    }
}
