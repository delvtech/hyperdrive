// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../test/mocks/ERC20Mintable.sol";
// import "../test/mocks/MockHyperdriveTestnet.sol";
import "../test/mocks/aave/MockPoolAddressesProvider.sol";
import "../test/mocks/aave/MockAavePool.sol";
import "../test/mocks/aave/MockACLManager.sol";

import { PoolConfigurator } from "@aave/core-v3/contracts/protocol/pool/PoolConfigurator.sol";
import { ReservesSetupHelper } from "@aave/core-v3/contracts/deployments/ReservesSetupHelper.sol";
import { ConfiguratorInputTypes } from "@aave/core-v3/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";
import { AToken } from "@aave/core-v3/contracts/protocol/tokenization/AToken.sol";
import { DelegationAwareAToken } from "@aave/core-v3/contracts/protocol/tokenization/DelegationAwareAToken.sol";
import { IAaveIncentivesController } from "@aave/core-v3/contracts/interfaces/IAaveIncentivesController.sol";
import { StableDebtToken } from "@aave/core-v3/contracts/protocol/tokenization/StableDebtToken.sol";
import { VariableDebtToken } from "@aave/core-v3/contracts/protocol/tokenization/VariableDebtToken.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

import { DefaultReserveInterestRateStrategy } from "@aave/core-v3/contracts/protocol/pool/DefaultReserveInterestRateStrategy.sol";

import { MockReserveInterestRateStrategy } from "@aave/core-v3/contracts/mocks/tests/MockReserveInterestRateStrategy.sol";

contract MockAaveScript is Script {
    string constant MARKET_ID = "Aave Testnet Market";

    ConfiguratorInputTypes.InitReserveInput[] internal reserveConfigs;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = msg.sender;

        ERC20Mintable baseToken = new ERC20Mintable();

        // console.logAddress(deployer);

        // Create Market Registry
        MockPoolAddressesProvider poolAddressesProvider = new MockPoolAddressesProvider(
                MARKET_ID,
                deployer
            );

        // Create Pool impl
        MockAavePool mockAavePool = new MockAavePool(poolAddressesProvider);

        console.log("mock aave pool address ", address(mockAavePool));

        // Initialize pool
        mockAavePool.initialize(poolAddressesProvider);

        MockACLManager aclManager = new MockACLManager();
        poolAddressesProvider.setACLManager(address(aclManager));

        console.log("prev getPool", poolAddressesProvider.getPool());

        // setup utils
        ReservesSetupHelper reservesSetupHelper = new ReservesSetupHelper();
        // poolAddressesProvider.setAddressAsProxy("POOL",address(mockAavePool));
        poolAddressesProvider.setPoolImpl(address(mockAavePool));
        // poolAddressesProvider.getPool();
        console.log("after getPool", poolAddressesProvider.getPool());

        PoolConfigurator poolConfig = new PoolConfigurator();
        poolConfig.initialize(poolAddressesProvider);
        poolAddressesProvider.setPoolConfiguratorImpl(address(poolConfig));

        //           struct InitReserveInput {
        //     address aTokenImpl;
        //     address stableDebtTokenImpl;
        //     address variableDebtTokenImpl;
        //     uint8 underlyingAssetDecimals;
        //     address interestRateStrategyAddress;
        //     address underlyingAsset;
        //     address treasury;
        //     address incentivesController;
        //     string aTokenName;
        //     string aTokenSymbol;
        //     string variableDebtTokenName;
        //     string variableDebtTokenSymbol;
        //     string stableDebtTokenName;
        //     string stableDebtTokenSymbol;
        //     bytes params;
        //   }

        bytes memory _param = new bytes(0);

        //        OPTIMAL_USAGE_RATIO = optimalUsageRatio;
        // ADDRESSES_PROVIDER = provider;
        // _baseVariableBorrowRate = baseVariableBorrowRate;
        // _variableRateSlope1 = variableRateSlope1;
        // _variableRateSlope2 = variableRateSlope2;
        // _stableRateSlope1 = stableRateSlope1;
        // _stableRateSlope2 = stableRateSlope2;

        //   optimalUsageRatio: parseUnits("0.8", 27).toString(),
        //   baseVariableBorrowRate: parseUnits("0", 27).toString(),
        //   variableRateSlope1: parseUnits("0.04", 27).toString(),
        //   variableRateSlope2: parseUnits("0.75", 27).toString(),
        //   stableRateSlope1: parseUnits("0.02", 27).toString(),
        //   stableRateSlope2: parseUnits("0.75", 27).toString(),
        //   baseStableRateOffset: parseUnits("0.02", 27).toString(),
        //   stableRateExcessOffset: parseUnits("0.05", 27).toString(),
        //   optimalStableToTotalDebtRatio: parseUnits("0.2", 27).toString(),

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

        // console.log("aToken impl ", address(aTokenImpl));
        //         console.log("aToken impl ", address(aTokenImpl));

        // ConfiguratorInputTypes.InitReserveInput[] memory reserveConfigs;

        //           name: "rateStrategyStableTwo",

        //           strategy: rateStrategyStableTwo,
        //   baseLTVAsCollateral: "7500",
        //   liquidationThreshold: "8000",
        //   liquidationBonus: "10500",
        //   liquidationProtocolFee: "1000",
        //   borrowingEnabled: true,
        //   stableBorrowRateEnabled: true,
        //   flashLoanEnabled: true,
        //   reserveDecimals: "18",
        //   aTokenImpl: eContractid.AToken,
        //   reserveFactor: "1000",
        //   supplyCap: "0",
        //   borrowCap: "0",
        //   debtCeiling: "0",
        //   borrowableIsolation: true,

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
        // mockAavePool.supply(address(baseToken), 100e18, msg.sender, 0);

        IPool realPool =   IPool(poolAddressesProvider.getPool());
        realPool.supply(address(baseToken), 100e18, msg.sender, 0);

        // poolConfig.initReserves([{
        //     aTokenImpl: address(0),
        //     stableDebtTokenImpl: address(0),
        //     variableDebtTokenImpl: address(0),
        //     interestRateStrategyAddress: address(0),
        //     underlyingAsset: address(0),
        //     treasury: address(0),
        //     incentivesController: address(0),
        //     aTokenName: "Aave BASE Token",
        //     aTokenSymbol: "aBASE",
        //     variableDebtTokenName: "Aave BASE Variable Debt Token",
        //     variableDebtTokenSymbol: "a-vd-BASE",
        //                 stableDebtTokenName: "Aave BASE Stable Debt Token",
        //     stableDebtTokenSymbol: "a-vd-BASE",
        //     params: 0x8,
        // }]);

        // // Mock ERC20
        // ERC20Mintable BASE = new ERC20Mintable();
        // BASE.mint(1_000_000 * 1e18);

        // // Mock Hyperdrive, 1 year term
        // MockHyperdriveTestnet hyperdrive = new MockHyperdriveTestnet(
        //     BASE,
        //     5e18,
        //     FixedPointMath.ONE_18,
        //     365,
        //     1 days,
        //     FixedPointMath.ONE_18.divDown(22.186877016851916266e18),
        //     0,
        //     0
        // );

        // BASE.approve(address(hyperdrive), 10_000_000e18);
        // hyperdrive.initialize(100_000e18, 0.05e18, msg.sender, false);
        // hyperdrive.openLong(10_000e18, 0, msg.sender, false);

        vm.stopBroadcast();
    }
}
