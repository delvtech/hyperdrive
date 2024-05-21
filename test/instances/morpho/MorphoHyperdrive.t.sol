// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { MorphoHyperdriveCoreDeployer } from "contracts/src/deployers/morpho/MorphoHyperdriveCoreDeployer.sol";
import { MorphoHyperdriveDeployerCoordinator } from "contracts/src/deployers/morpho/MorphoHyperdriveDeployerCoordinator.sol";
import { MorphoTarget0Deployer } from "contracts/src/deployers/morpho/MorphoTarget0Deployer.sol";
import { MorphoTarget1Deployer } from "contracts/src/deployers/morpho/MorphoTarget1Deployer.sol";
import { MorphoTarget2Deployer } from "contracts/src/deployers/morpho/MorphoTarget2Deployer.sol";
import { MorphoTarget3Deployer } from "contracts/src/deployers/morpho/MorphoTarget3Deployer.sol";
import { MorphoTarget4Deployer } from "contracts/src/deployers/morpho/MorphoTarget4Deployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IMorpho, Market, MarketParams, Position, Id } from "contracts/src/interfaces/IMorpho.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { InstanceTest } from "test/utils/InstanceTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { MorphoSharesMath } from "contracts/src/libraries/MorphoSharesMath.sol";
import { Lib } from "test/utils/Lib.sol";

import "forge-std/console2.sol";

contract MorphoHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using FixedPointMath for uint128;

    using MorphoSharesMath for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    IMorpho internal constant MORPHO =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    Id internal constant MARKET_ID =
        Id.wrap(
            0xc581c5f70bd1afa283eed57d1418c6432cbff1d862f94eaf58fdd4e46afbb67f
        );

    MarketParams internal marketParams;

    // Renzo's restaking protocol was launch Dec, 2023 and their use of
    // oracles makes it difficult to test on a mainnet fork without heavy
    // mocking.  To test with their deployed code we use a shorter position
    // duration.
    uint256 internal constant POSITION_DURATION_15_DAYS = 15 days;
    uint256 internal constant STARTING_BLOCK = 19759592;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // Whale accounts.
    address internal WETH_WHALE = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
    address[] internal whaleAccounts = [WETH_WHALE];

    // The configuration for the Instance testing suite.
    InstanceTestConfig internal __testConfig =
        InstanceTestConfig(
            "MorphoHyperdrive",
            whaleAccounts,
            IERC20(WETH),
            IERC20(WETH),
            1e6,
            1e15,
            POSITION_DURATION_15_DAYS,
            true,
            false,
            true,
            false
        );

    /// @dev Instantiates the Instance testing suite with the configuration.
    constructor() InstanceTest(__testConfig) {
        marketParams = MarketParams(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            0x2a01EB9496094dA03c4E364Def50f5aD1280AD72,
            0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
            945000000000000000
        );
    }

    /// @dev Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(STARTING_BLOCK) {
        // Invoke the Instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Converts base amount to the equivalent about in EzETH.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        Market memory market = MORPHO.market(MARKET_ID);
        console2.log("$");

        uint128 assets = market.totalSupplyAssets;
        uint128 shares = market.totalSupplyShares;

        // share price = total assets / total shares
        console2.log("0");
        console2.log(assets);
        console2.log(assets.mulDown(1e24), assets);
        console2.log(ONE.mulDivDown(assets.mulDown(1e6), shares).divDown(1e6));
        console2.log(ONE.mulDivDown(assets.mulDown(1e6), shares));

        console2.log(shares);
        // console2.log(assets.divDown(shares));
        console2.log("$");

        return
            baseAmount.toSharesDown(
                market.totalSupplyAssets,
                market.totalSupplyShares
            );
    }

    /// @dev Converts share amount to the equivalent amount in ETH.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        Market memory market = MORPHO.market(MARKET_ID);

        // rounding down for withdraws
        return
            shareAmount.toAssetsDown(
                market.totalSupplyAssets,
                market.totalSupplyShares
            );
    }

    /// @dev Deploys the EzETH deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory contract.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new MorphoHyperdriveDeployerCoordinator(
                    _factory,
                    address(
                        new MorphoHyperdriveCoreDeployer(MORPHO, marketParams)
                    ),
                    address(new MorphoTarget0Deployer(MORPHO, marketParams)),
                    address(new MorphoTarget1Deployer(MORPHO, marketParams)),
                    address(new MorphoTarget2Deployer(MORPHO, marketParams)),
                    address(new MorphoTarget3Deployer(MORPHO, marketParams)),
                    address(new MorphoTarget4Deployer(MORPHO, marketParams)),
                    MORPHO,
                    marketParams
                )
            );
    }

    /// @dev Fetches the token balance information of an account.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        Position memory position = MORPHO.position(MARKET_ID, address(this));

        return (IERC20(WETH).balanceOf(account), position.supplyShares);
    }

    /// @dev Fetches the total supply of the base and share tokens.
    function getSupply() internal view override returns (uint256, uint256) {
        Market memory market = MORPHO.market(MARKET_ID);

        return (market.totalSupplyAssets, market.totalSupplyShares);
    }

    /// @dev Verifies that deposit accounting is correct when opening positions.
    function verifyDeposit(
        address trader,
        uint256 basePaid,
        bool asBase,
        uint256 totalBaseSupplyBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal override {}

    /// @dev Verifies that withdrawal accounting is correct when closing positions.
    function verifyWithdrawal(
        address trader,
        uint256 baseProceeds,
        bool asBase,
        uint256 totalPooledEtherBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal override {}

    /// Getters ///

    // function test_getters() external {
    //     assertEq(
    //         address(IEzETHHyperdriveRead(address(hyperdrive)).renzo()),
    //         address(RESTAKE_MANAGER)
    //     );
    //     assertEq(
    //         address(IEzETHHyperdriveRead(address(hyperdrive)).renzoOracle()),
    //         address(RENZO_ORACLE)
    //     );
    // }

    /// Price Per Share ///

    function test__pricePerVaultShare(uint256 basePaid) external {}

    /// Helpers ///

    function advanceTime(
        uint256 timeDelta, // assume a position duration jump
        int256 variableRate // annual variable rate
    ) internal override {}

    // returns share price information.
}
