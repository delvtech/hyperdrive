// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { ERC4626Hyperdrive } from "../../../contracts/src/instances/erc4626/ERC4626Hyperdrive.sol";
import { ERC4626Target0 } from "../../../contracts/src/instances/erc4626/ERC4626Target0.sol";
import { ERC4626Target1 } from "../../../contracts/src/instances/erc4626/ERC4626Target1.sol";
import { ERC4626Target2 } from "../../../contracts/src/instances/erc4626/ERC4626Target2.sol";
import { ERC4626Target3 } from "../../../contracts/src/instances/erc4626/ERC4626Target3.sol";
import { ERC4626Target4 } from "../../../contracts/src/instances/erc4626/ERC4626Target4.sol";
import { RETHHyperdrive } from "../../../contracts/src/instances/reth/RETHHyperdrive.sol";
import { RETHTarget0 } from "../../../contracts/src/instances/reth/RETHTarget0.sol";
import { RETHTarget1 } from "../../../contracts/src/instances/reth/RETHTarget1.sol";
import { RETHTarget2 } from "../../../contracts/src/instances/reth/RETHTarget2.sol";
import { RETHTarget3 } from "../../../contracts/src/instances/reth/RETHTarget3.sol";
import { RETHTarget4 } from "../../../contracts/src/instances/reth/RETHTarget4.sol";
import { StETHHyperdrive } from "../../../contracts/src/instances/steth/StETHHyperdrive.sol";
import { StETHTarget0 } from "../../../contracts/src/instances/steth/StETHTarget0.sol";
import { StETHTarget1 } from "../../../contracts/src/instances/steth/StETHTarget1.sol";
import { StETHTarget2 } from "../../../contracts/src/instances/steth/StETHTarget2.sol";
import { StETHTarget3 } from "../../../contracts/src/instances/steth/StETHTarget3.sol";
import { StETHTarget4 } from "../../../contracts/src/instances/steth/StETHTarget4.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../../contracts/src/interfaces/IERC4626.sol";
import { ILido } from "../../../contracts/src/interfaces/ILido.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { ISwapRouter } from "../../../contracts/src/interfaces/ISwapRouter.sol";
import { IUniV3Zap } from "../../../contracts/src/interfaces/IUniV3Zap.sol";
import { IWETH } from "../../../contracts/src/interfaces/IWETH.sol";
import { ETH } from "../../../contracts/src/libraries/Constants.sol";
import { UniV3Path } from "../../../contracts/src/libraries/UniV3Path.sol";
import { UniV3Zap } from "../../../contracts/src/zaps/UniV3Zap.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "../../../contracts/test/MockERC4626.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";

// FIXME: I need to update this test suite to support `safeTransferFrom`
//        and `safeBatchTransferFrom`.
contract UniV3ZapTest is HyperdriveTest {
    /// @dev The name of the zap contract.
    string internal constant NAME = "DELV Uniswap v3 Zap";

    /// @dev Uniswap's lowest fee tier.
    uint24 internal constant LOWEST_FEE_TIER = 100;

    /// @dev Uniswap's low fee tier.
    uint24 internal constant LOW_FEE_TIER = 500;

    /// @dev Uniswap's medium fee tier.
    uint24 internal constant MEDIUM_FEE_TIER = 3_000;

    /// @dev Uniswap's high fee tier.
    uint24 internal constant HIGH_FEE_TIER = 10_000;

    /// @dev The USDC token address.
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @dev The DAI token address.
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    /// @dev The sDAI token address.
    address internal constant SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;

    /// @dev The Wrapped Ether token address.
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @dev The rETH token address.
    address internal constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    /// @dev The stETH token address.
    address internal constant STETH =
        0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    /// @dev The wstETH token address.
    address internal constant WSTETH =
        0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @dev The USDC whale address
    address internal constant USDC_WHALE =
        0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;

    /// @dev The DAI whale address
    address internal constant DAI_WHALE =
        0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf;

    /// @dev The sDAI whale address
    address internal constant SDAI_WHALE =
        0x4C612E3B15b96Ff9A6faED838F8d07d479a8dD4c;

    /// @dev The WETH whale address
    address internal constant WETH_WHALE =
        0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;

    /// @dev The rETH whale address
    address internal constant RETH_WHALE =
        0xCc9EE9483f662091a1de4795249E24aC0aC2630f;

    /// @dev The stETH whale address
    address internal constant STETH_WHALE =
        0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @dev The Uniswap swap router.
    ISwapRouter internal constant SWAP_ROUTER =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    /// @dev The Hyperdrive mainnet sDAI pool.
    IHyperdrive internal SDAI_HYPERDRIVE;

    /// @dev The Hyperdrive mainnet stETH pool.
    IHyperdrive internal STETH_HYPERDRIVE;

    /// @dev The Hyperdrive mainnet rETH pool.
    IHyperdrive internal RETH_HYPERDRIVE;

    /// @dev A Hyperdrive instance that integrates with a MockERC4626 vault that
    ///      uses WETH as the base asset. This is useful for testing situations
    ///      where Hyperdrive's base token is WETH.
    IHyperdrive internal WETH_VAULT_HYPERDRIVE;

    /// @dev The Uniswap v3 zap contract.
    IUniV3Zap internal zap;

    /// @dev Set up balances and Hyperdrive instances to test the zap. This is
    ///      a mainnet fork test that uses real Hyperdrive instances.
    function setUp() public virtual override __mainnet_fork(20_830_093) {
        // Run the higher-level setup logic.
        super.setUp();

        // Instantiate the zap contract.
        zap = IUniV3Zap(new UniV3Zap(NAME, SWAP_ROUTER, IWETH(WETH)));

        // Set up Alice as the sender.
        vm.stopPrank();
        vm.startPrank(alice);

        // Fund Alice from some whale accounts.
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        fundAccounts(address(zap), IERC20(USDC), USDC_WHALE, accounts);
        fundAccounts(address(zap), IERC20(DAI), DAI_WHALE, accounts);
        fundAccounts(address(zap), IERC20(SDAI), SDAI_WHALE, accounts);
        fundAccounts(address(zap), IERC20(WETH), WETH_WHALE, accounts);
        fundAccounts(address(zap), IERC20(RETH), RETH_WHALE, accounts);
        fundAccounts(address(zap), IERC20(STETH), STETH_WHALE, accounts);

        // Deploy and initialize a Hyperdrive instance that integrates with a
        // WETH yield souce.
        MockERC4626 wethVault = new MockERC4626(
            ERC20Mintable(address(WETH)),
            "WETH Vault",
            "WETH_VAULT",
            0,
            address(0),
            false,
            type(uint256).max
        );
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        config.baseToken = IERC20(WETH);
        config.vaultSharesToken = IERC20(address(wethVault));
        config.minimumShareReserves = 1e15;
        config.fees.curve = 0.01e18;
        config.fees.flat = 0.0005e18;
        config.fees.governanceLP = 0.15e18;
        config.fees.governanceZombie = 0.03e18;
        WETH_VAULT_HYPERDRIVE = IHyperdrive(
            address(
                new ERC4626Hyperdrive(
                    "WETH Vault Hyperdrive",
                    config,
                    adminController,
                    address(new ERC4626Target0(config, adminController)),
                    address(new ERC4626Target1(config, adminController)),
                    address(new ERC4626Target2(config, adminController)),
                    address(new ERC4626Target3(config, adminController)),
                    address(new ERC4626Target4(config, adminController))
                )
            )
        );
        IERC20(WETH).approve(address(WETH_VAULT_HYPERDRIVE), 1e18);
        WETH_VAULT_HYPERDRIVE.initialize(
            1e18,
            0.05e18,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Deploy and initialize a sDAI Hyperdrive instance.
        config.baseToken = IERC20(DAI);
        config.vaultSharesToken = IERC20(SDAI);
        SDAI_HYPERDRIVE = IHyperdrive(
            address(
                new ERC4626Hyperdrive(
                    "sDAI Hyperdrive",
                    config,
                    adminController,
                    address(new ERC4626Target0(config, adminController)),
                    address(new ERC4626Target1(config, adminController)),
                    address(new ERC4626Target2(config, adminController)),
                    address(new ERC4626Target3(config, adminController)),
                    address(new ERC4626Target4(config, adminController))
                )
            )
        );
        IERC20(DAI).approve(address(SDAI_HYPERDRIVE), 1_000_000e18);
        SDAI_HYPERDRIVE.initialize(
            1_000_000e18,
            0.05e18,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Deploy and initialize a stETH Hyperdrive instance.
        config.baseToken = IERC20(ETH);
        config.vaultSharesToken = IERC20(STETH);
        STETH_HYPERDRIVE = IHyperdrive(
            address(
                new StETHHyperdrive(
                    "stETH Hyperdrive",
                    config,
                    adminController,
                    address(new StETHTarget0(config, adminController)),
                    address(new StETHTarget1(config, adminController)),
                    address(new StETHTarget2(config, adminController)),
                    address(new StETHTarget3(config, adminController)),
                    address(new StETHTarget4(config, adminController))
                )
            )
        );
        STETH_HYPERDRIVE.initialize{ value: 100e18 }(
            100e18,
            0.05e18,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Deploy and initialize a rETH Hyperdrive instance.
        config.baseToken = IERC20(ETH);
        config.vaultSharesToken = IERC20(RETH);
        RETH_HYPERDRIVE = IHyperdrive(
            address(
                new RETHHyperdrive(
                    "RETH Hyperdrive",
                    config,
                    adminController,
                    address(new RETHTarget0(config, adminController)),
                    address(new RETHTarget1(config, adminController)),
                    address(new RETHTarget2(config, adminController)),
                    address(new RETHTarget3(config, adminController)),
                    address(new RETHTarget4(config, adminController))
                )
            )
        );
        IERC20(RETH).approve(address(RETH_HYPERDRIVE), 100e18);
        RETH_HYPERDRIVE.initialize(
            100e18,
            0.05e18,
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: new bytes(0)
            })
        );
    }
}
