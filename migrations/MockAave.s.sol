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

        console.log("mock aave pool address ",address(mockAavePool));

        // Initialize pool
        mockAavePool.initialize(poolAddressesProvider);

        PoolConfigurator poolConfig = new PoolConfigurator();
        poolConfig.initialize(poolAddressesProvider);

        MockACLManager aclManager = new MockACLManager();
        poolAddressesProvider.setACLManager(address(aclManager));

        console.log("prev getPool",poolAddressesProvider.getPool());

        // setup utils
        ReservesSetupHelper reservesSetupHelper = new ReservesSetupHelper();
        // poolAddressesProvider.setAddressAsProxy("POOL",address(mockAavePool));
        poolAddressesProvider.setPoolImpl(address(mockAavePool));
        poolAddressesProvider.setPoolConfiguratorImpl(address(poolConfig));
        // poolAddressesProvider.getPool();
        console.log("after getPool",poolAddressesProvider.getPool());


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

        // setup token impls
        AToken aTokenImpl = new AToken(mockAavePool);
        aTokenImpl.initialize(
            mockAavePool,
            address(0),
            address(0),
            IAaveIncentivesController(address(0)),
            0,
            "DELEGATION_AWARE_ATOKEN_IMPL",
            "DELEGATION_AWARE_ATOKEN_IMPL",
            _param
        );
        DelegationAwareAToken delegationAwareATokenImpl = new DelegationAwareAToken(
                mockAavePool
            );
        delegationAwareATokenImpl.initialize(
            mockAavePool,
            address(0),
            address(0),
            IAaveIncentivesController(address(0)),
            0,
            "DELEGATION_AWARE_ATOKEN_IMPL",
            "DELEGATION_AWARE_ATOKEN_IMPL",
            _param
        );

        StableDebtToken stableDebtTokenImpl = new StableDebtToken(mockAavePool);
        stableDebtTokenImpl.initialize(
            mockAavePool,
            address(0),
            IAaveIncentivesController(address(0)),
            0,
            "DELEGATION_AWARE_ATOKEN_IMPL",
            "DELEGATION_AWARE_ATOKEN_IMPL",
            _param
        );

        VariableDebtToken variableDebtTokenImpl = new VariableDebtToken(
            mockAavePool
        );
        variableDebtTokenImpl.initialize(
            mockAavePool,
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

        ConfiguratorInputTypes.InitReserveInput
            memory baseReserveConfig = ConfiguratorInputTypes.InitReserveInput({
                aTokenImpl: address(aTokenImpl),
                stableDebtTokenImpl: address(stableDebtTokenImpl),
                variableDebtTokenImpl: address(variableDebtTokenImpl),
                underlyingAssetDecimals: 18,
                interestRateStrategyAddress: address(0),
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
