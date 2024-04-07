// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

/// @author DELV
/// @title InstanceTest
/// @notice The base contract for the instance testing suite.
/// @dev A testing suite that provides a foundation to setup, deploy, and
///      test common cases for Hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract InstanceTest is HyperdriveTest {
    using Lib for *;
    using FixedPointMath for uint256;

    /// @dev Configuration for the Instance testing suite.
    struct InstanceTestConfig {
        address[] whaleAccounts;
        IERC20 baseToken;
        IERC20 vaultSharesToken;
        uint256 shareTolerance;
        uint256 minTransactionAmount;
        uint256 positionDuration;
        bool enableBaseDeposits;
        bool enableShareDeposits;
    }

    // Fixed rate used to configure market.
    uint256 internal constant FIXED_RATE = 0.05e18;

    // Default deployment constants.
    bytes32 private constant DEFAULT_DEPLOYMENT_ID =
        bytes32(uint256(0xdeadbeef));
    bytes32 private constant DEFAULT_DEPLOYMENT_SALT =
        bytes32(uint256(0xdeadbabe));

    // The configuration for the Instance testing suite.
    InstanceTestConfig private config;

    // The configuration for the pool.
    IHyperdrive.PoolDeployConfig private poolConfig;

    // The address of the deployer coordinator contract.
    address private deployerCoordinator;

    // The factory contract used for deployment in this testing suite.
    HyperdriveFactory private factory;

    // Flag for denoting if the base token is ETH.
    bool private immutable isBaseETH;

    /// @dev Constructor for the Instance testing suite.
    /// @param _config The Instance configuration.
    constructor(InstanceTestConfig storage _config) {
        config = _config;
        isBaseETH = config.baseToken == IERC20(ETH);
    }

    /// Deployments ///

    /// @notice Forge setup function.
    /// @dev Inherits from HyperdriveTest and deploys the
    ///      Hyperdrive factory, deployer coordinator, and targets.
    function setUp() public virtual override {
        super.setUp();

        // Initial contribution.
        uint256 contribution = 5_000e18;

        // Fund accounts with ETH and vault shares from whales.
        vm.deal(alice, 100_000e18);
        vm.deal(bob, 100_000e18);
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        for (uint256 i = 0; i < config.whaleAccounts.length; i++) {
            fundAccounts(
                address(hyperdrive),
                config.vaultSharesToken,
                config.whaleAccounts[i],
                accounts
            );
        }

        // Deploy the Hyperdrive Factory contract.
        deployFactory();

        // Set the deployer coordinator address and add to the factory.
        deployerCoordinator = deployCoordinator(address(factory));
        factory.addDeployerCoordinator(deployerCoordinator);

        // Deploy all Hyperdrive contracts using deployer coordinator contract.
        deployHyperdrive(
            DEFAULT_DEPLOYMENT_ID, // Deployment Id
            DEFAULT_DEPLOYMENT_SALT, // Deployment Salt
            contribution, // Contribution
            false // asBase
        );

        config.vaultSharesToken.approve(address(hyperdrive), 100_000e18);
        vm.startPrank(bob);
        config.vaultSharesToken.approve(address(hyperdrive), 100_000e18);

        // Ensure that Alice received the correct amount of LP tokens. She should
        // receive LP shares totaling the amount of shares that she contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            contribution - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
            config.shareTolerance
        );

        // Start recording event logs.
        vm.recordLogs();
    }

    /// @dev Deploys all Hyperdrive contracts using the
    ///      deployer coordinator contract.
    /// @param deploymentId The deployment id.
    /// @param deploymentSalt The deployment salt for create2.
    /// @param contribution The amount to initialize the market.
    /// @param asBase Initialize the market with base token.
    function deployHyperdrive(
        bytes32 deploymentId,
        bytes32 deploymentSalt,
        uint256 contribution,
        bool asBase
    ) private {
        // Alice is the default deployer.
        vm.startPrank(alice);

        // Deploy Hyperdrive target contracts.
        factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            0,
            deploymentSalt
        );
        factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            1,
            deploymentSalt
        );
        factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            2,
            deploymentSalt
        );
        factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            3,
            deploymentSalt
        );
        factory.deployTarget(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            FIXED_RATE,
            FIXED_RATE,
            4,
            deploymentSalt
        );

        // Alice gives approval to the deployer coordinator to fund the market.
        config.vaultSharesToken.approve(deployerCoordinator, 100_000e18);

        // We expect the deployAndInitialize to fail with an
        // UnsupportedToken error if depositing with base is not supported.
        // If the base token is ETH we expect a NotPayable error.
        if (!config.enableBaseDeposits && asBase) {
            vm.expectRevert(
                isBaseETH
                    ? IHyperdrive.NotPayable.selector
                    : IHyperdrive.UnsupportedToken.selector
            );
        }

        // We expect the deployAndInitialize to fail with an
        // UnsupportedToken error if depositing with shares is not supported.
        if (!config.enableShareDeposits && !asBase) {
            vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        }

        // Record Alice's ETH balance before the deployment call.
        uint256 aliceBalanceBefore = address(alice).balance;

        // Deploy and initialize the market. If the base token is ETH we pass the
        // contribution through the call.
        hyperdrive = factory.deployAndInitialize{
            value: asBase && isBaseETH ? contribution : 0
        }(
            deploymentId,
            deployerCoordinator,
            poolConfig,
            new bytes(0),
            contribution,
            FIXED_RATE,
            FIXED_RATE,
            IHyperdrive.Options({
                asBase: asBase,
                destination: alice,
                extraData: new bytes(0)
            }),
            deploymentSalt
        );

        // Ensure that refunds are handled properly.
        if (config.enableBaseDeposits && asBase && isBaseETH) {
            assertEq(aliceBalanceBefore - contribution, address(alice).balance);
        } else {
            assertEq(aliceBalanceBefore, address(alice).balance);
        }
    }

    /// @dev Deploys the Hyperdrive Factory contract and sets
    ///      the default pool configuration.
    function deployFactory() private {
        // Deploy the hyperdrive factory.
        vm.startPrank(deployer);
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ERC20ForwarderFactory();
        factory = new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: celine,
                sweepCollector: sweepCollector,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimeStretchAPR: 0.005e18,
                maxTimeStretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                }),
                maxFees: IHyperdrive.Fees({
                    curve: ONE,
                    flat: ONE,
                    governanceLP: ONE,
                    governanceZombie: ONE
                }),
                linkerFactory: address(forwarderFactory),
                linkerCodeHash: forwarderFactory.ERC20LINK_HASH()
            })
        );

        // Set the pool configuration that will be used for instance deployments.
        poolConfig = IHyperdrive.PoolDeployConfig({
            baseToken: config.baseToken,
            vaultSharesToken: config.vaultSharesToken,
            linkerFactory: factory.linkerFactory(),
            linkerCodeHash: factory.linkerCodeHash(),
            minimumShareReserves: 1e15,
            minimumTransactionAmount: config.minTransactionAmount,
            positionDuration: config.positionDuration,
            checkpointDuration: CHECKPOINT_DURATION,
            timeStretch: 0,
            governance: factory.hyperdriveGovernance(),
            feeCollector: factory.feeCollector(),
            sweepCollector: factory.sweepCollector(),
            fees: IHyperdrive.Fees({
                curve: 0,
                flat: 0,
                governanceLP: 0,
                governanceZombie: 0
            })
        });
    }

    /// Overrides ///

    /// @dev A virtual function that defines the deployer coordinator
    ///      contract that will be used to deploy all the instance targets.
    /// @param _factory The address of the Hyperdrive factory contract.
    function deployCoordinator(
        address _factory
    ) internal virtual returns (address);

    /// @dev A virtual function that converts an amount in terms of the base token
    ///      to equivalent amount in shares.
    /// @param baseAmount Amount in terms of base.
    /// @return shareAmount Amount in terms of shares.
    function convertToShares(
        uint256 baseAmount
    ) internal view virtual returns (uint256 shareAmount);

    /// @dev A virtual function that converts an amount in terms of the share token
    ///      to equivalent amount in base.
    /// @param shareAmount Amount in terms of shares.
    /// @return baseAmount Amount in terms of base.
    function convertToBase(
        uint256 shareAmount
    ) internal view virtual returns (uint256 baseAmount);

    /// @dev A virtual function that ensures the deposit accounting is correct
    ///      when opening positions.
    /// @param trader The account opening the position.
    /// @param basePaid The amount the position was opened with in terms of base.
    /// @param asBase Flag to determine whether the position was opened with the base or share token.
    /// @param totalBaseBefore Total supply of the base token before the trade.
    /// @param totalSharesBefore Total supply of the share token before the trade.
    /// @param traderBalancesBefore Balances of tokens of the trader before the trade.
    /// @param hyperdriveBalancesBefore Balances of tokens of the Hyperdrive contract before the trade.
    function verifyDeposit(
        address trader,
        uint256 basePaid,
        bool asBase,
        uint256 totalBaseBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal virtual;

    /// @dev A virtual function that fetches the token balance information of an account.
    /// @param account The account to fetch token balances of.
    /// @return baseBalance The shares token balance of the account.
    /// @return shareBalance The base token balance of the account.
    function getTokenBalances(
        address account
    ) internal view virtual returns (uint256 baseBalance, uint256 shareBalance);

    /// @dev A virtual function that fetches the total supply of the base and share tokens.
    /// @return totalSupplyBase The total supply of the base token.
    /// @return totalSupplyShares The total supply of the share token.
    function getSupply()
        internal
        virtual
        returns (uint256 totalSupplyBase, uint256 totalSupplyShares);

    /// Tests ///

    /// @dev Test to verify a market can be deployed and initialized funded by the
    ///      base token. Is expected to revert when base deposits are not supported.
    function test__deployAndInitialize__asBase() external virtual {
        uint256 aliceBalanceBefore = address(alice).balance;

        // Contribution in terms of base.
        uint256 contribution = 5_000e18;

        // Contribution in terms of shares.
        uint256 contributionShares = convertToShares(contribution);

        // Deploy all Hyperdrive contract using deployer coordinator contract.
        // This function reverts if base deposits are disabled.
        deployHyperdrive(
            bytes32(uint256(0xbeefbabe)), // Deployment Id
            bytes32(uint256(0xdeadfade)), // Deployment Salt
            contribution, // Contribution
            true // asBase
        );

        // Early termination if base deposits are not supported.
        if (!config.enableBaseDeposits) {
            return;
        }

        // If base deposits are enabled we verify some assertions.
        if (isBaseETH) {
            // If the base token is ETH we assert the ETH balance is correct.
            assertEq(address(alice).balance, aliceBalanceBefore - contribution);
        }

        // Ensure that the decimals are set correctly.
        assertEq(hyperdrive.decimals(), 18);

        // Ensure that Alice received the correct amount of LP tokens. She should
        // receive LP shares totaling the amount of shares that he contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            contribution.divDown(
                hyperdrive.getPoolConfig().initialVaultSharePrice
            ) - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
            config.shareTolerance // Custom share tolerance per instance.
        );

        // Ensure that the share reserves and LP total supply are equal and correct.
        assertApproxEqAbs(
            hyperdrive.getPoolInfo().shareReserves,
            contributionShares,
            1
        );
        assertEq(
            hyperdrive.getPoolInfo().lpTotalSupply,
            hyperdrive.getPoolInfo().shareReserves -
                hyperdrive.getPoolConfig().minimumShareReserves
        );

        // Verify that the correct events were emitted.
        verifyFactoryEvents(
            deployerCoordinator,
            hyperdrive,
            alice,
            contribution,
            FIXED_RATE,
            true,
            hyperdrive.getPoolConfig().minimumShareReserves,
            new bytes(0),
            config.shareTolerance
        );
    }

    /// @dev Test to verify a market can be deployed and initialized funded
    ///      by the share token.
    function test__deployAndInitialize__asShares() external {
        uint256 aliceBalanceBefore = address(alice).balance;

        // Contribution in terms of base.
        uint256 contribution = 5_000e18;

        // Contribution in terms of shares.
        uint256 contributionShares = convertToShares(contribution);

        // Deploy all Hyperdrive contracts using deployer coordinator contract.
        deployHyperdrive(
            bytes32(uint256(0xbeefbabe)), // Deployment Id
            bytes32(uint256(0xdeadfade)), // Deployment Salt
            contributionShares, // Contribution
            false // asBase
        );

        // Early termination if share deposits are not supported.
        if (!config.enableShareDeposits) {
            return;
        }

        // Ensure Alice's ETH balance remains the same.
        assertEq(address(alice).balance, aliceBalanceBefore);

        // Ensure that the decimals are set correctly.
        assertEq(hyperdrive.decimals(), 18);

        // Ensure that Alice received the correct amount of LP tokens. She should
        // receive LP shares totaling the amount of shares that he contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            contribution.divDown(
                hyperdrive.getPoolConfig().initialVaultSharePrice
            ) - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
            config.shareTolerance // Custom share tolerance per instance.
        );

        // Ensure that the share reserves and LP total supply are equal and correct.
        assertEq(hyperdrive.getPoolInfo().shareReserves, contributionShares);
        assertEq(
            hyperdrive.getPoolInfo().lpTotalSupply,
            hyperdrive.getPoolInfo().shareReserves -
                poolConfig.minimumShareReserves
        );

        // Verify that the correct events were emitted.
        verifyFactoryEvents(
            deployerCoordinator,
            hyperdrive,
            alice,
            contributionShares,
            FIXED_RATE,
            false,
            poolConfig.minimumShareReserves,
            new bytes(0),
            config.shareTolerance
        );
    }

    /// @dev Fuzz Test to ensure deposit accounting is correct when opening longs
    ///      with the share token.
    /// @param basePaid Amount in terms of base to open a long.
    function test_open_long_with_shares(uint256 basePaid) external {
        // Get balance information before opening a long.
        (
            uint256 totalBaseSupplyBefore,
            uint256 totalSharesSupplyBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalanceBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Calculate the maximum amount of basePaid we can test. The limit is
        // either the maximum long that Hyperdrive can open or the amount of the
        // share token the trader has.
        uint256 maxLongAmount = HyperdriveUtils.calculateMaxLong(hyperdrive);
        uint256 maxShareAmount = bobBalancesBefore.sharesBalance;

        // We normalize the basePaid variable within a valid range the market can support.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxLongAmount > maxShareAmount ? maxShareAmount : maxLongAmount
        );

        // Convert the amount to deposit in terms of the share token.
        uint256 sharesPaid = convertToShares(basePaid);

        // Bob opens a long by depositing the base token.
        // We expect openLong to fail with an UnsupportedToken error
        // if depositing with shares is not supported.
        vm.startPrank(bob);
        if (!config.enableShareDeposits) {
            vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        }
        (uint256 maturityTime, uint256 bondAmount) = hyperdrive.openLong(
            sharesPaid,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: false,
                extraData: new bytes(0)
            })
        );

        // Early termination if share deposits is not supported.
        if (!config.enableShareDeposits) {
            return;
        }

        // Ensure that Bob received the correct amount of bonds.
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                bob
            ),
            bondAmount
        );

        // Ensure the deposit accounting is correct.
        verifyDeposit(
            bob,
            basePaid,
            false,
            totalBaseSupplyBefore,
            totalSharesSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalanceBefore
        );
    }

    /// @dev Fuzz Test to ensure deposit accounting is correct when opening longs
    ///      with the base token. This test case is expected to fail if base deposits
    ///      is not supported.
    /// @param basePaid Amount in terms of base to open a long.
    function test_open_long_with_base(uint256 basePaid) external {
        // Get balance information before opening a long.
        (
            uint256 totalBaseSupplyBefore,
            uint256 totalSharesSupplyBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalanceBefore = getAccountBalances(
            address(hyperdrive)
        );

        // We normalize the basePaid variable within a valid range the market can support.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );

        // Bob opens a long by depositing the base token.
        // We expect openLong to fail with an UnsupportedToken error
        // if depositing with base is not supported or a NotPayable error
        // if the base token is ETH.
        vm.startPrank(bob);
        if (!config.enableBaseDeposits) {
            vm.expectRevert(
                isBaseETH
                    ? IHyperdrive.NotPayable.selector
                    : IHyperdrive.UnsupportedToken.selector
            );
        }
        (uint256 maturityTime, uint256 bondAmount) = hyperdrive.openLong{
            value: isBaseETH ? basePaid : 0
        }(
            basePaid,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Early termination if base deposits are not supported.
        if (!config.enableBaseDeposits) {
            return;
        }

        // Ensure that Bob received the correct amount of bonds.
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                bob
            ),
            bondAmount
        );

        // Ensure the deposit accounting is correct.
        verifyDeposit(
            bob,
            basePaid,
            true,
            totalBaseSupplyBefore,
            totalSharesSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalanceBefore
        );
    }

    /// @dev Fuzz Test to ensure deposit accounting is correct when opening shorts
    ///      with the share token. This test case is expected to fail if base deposits
    ///      is not supported.
    /// @param shortAmount Amount of bonds to short.
    function test_open_short_with_shares(uint256 shortAmount) external {
        // Get some balance information before opening a short.
        (
            uint256 totalBaseSupplyBefore,
            uint256 totalSharesSupplyBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // We normalize the short amount within a valid range the market can support.
        shortAmount = shortAmount.normalizeToRange(
            100 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );

        // Bob opens a short by depositing shares.
        // We expect the openShort to fail with an UnsupportedToken error
        // if depositing with shares is not supported.
        vm.startPrank(bob);
        if (!config.enableShareDeposits) {
            vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        }
        (uint256 maturityTime, uint256 sharesPaid) = hyperdrive.openShort(
            shortAmount,
            shortAmount,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: false,
                extraData: new bytes(0)
            })
        );

        // Early termination if base deposits is not supported.
        if (!config.enableShareDeposits) {
            return;
        }

        // Ensure that Bob received the correct amount of shorted bonds.
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                bob
            ),
            shortAmount
        );

        // Convert shares paid when opening short to base for deposit accounting.
        uint256 basePaid = convertToBase(sharesPaid);

        // Ensure that the amount of base paid by the short is reasonable.
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            1e18
        );
        assertGt(basePaid, 0);
        assertGe(
            realizedRate,
            FIXED_RATE.mulDown(config.positionDuration.divDown(365 days))
        );

        // Ensure the deposit accounting is correct.
        verifyDeposit(
            bob,
            basePaid,
            false,
            totalBaseSupplyBefore,
            totalSharesSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz Test to ensure deposit accounting is correct when opening shorts
    ///      with the share token. This test case is expected to fail if base deposits
    ///      is not supported.
    /// @param shortAmount Amount of bonds to short.
    function test_open_short_with_base(uint256 shortAmount) external {
        // Get some balance information before opening a short.
        (
            uint256 totalBaseSupplyBefore,
            uint256 totalSharesSupplyBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // We normalize the short amount within a valid range the market can support.
        shortAmount = shortAmount.normalizeToRange(
            100 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );

        // Bob opens a short by depositing base.
        // We expect the openShort to fail with an UnsupportedToken error
        // if depositing with base is not supported or a NotPayable error
        // if the base token is ETH.
        vm.startPrank(bob);
        if (!config.enableBaseDeposits) {
            vm.expectRevert(
                isBaseETH
                    ? IHyperdrive.NotPayable.selector
                    : IHyperdrive.UnsupportedToken.selector
            );
        }
        (uint256 maturityTime, uint256 basePaid) = hyperdrive.openShort{
            value: isBaseETH ? shortAmount : 0
        }(
            shortAmount,
            shortAmount,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Early termination if base deposits is not supported.
        if (!config.enableBaseDeposits) {
            return;
        }

        // Ensure that Bob received the correct amount of shorted bonds.
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                bob
            ),
            shortAmount
        );

        // Ensure that the amount of base paid by the short is reasonable.
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            1e18
        );
        assertGt(basePaid, 0);
        assertGe(
            realizedRate,
            FIXED_RATE.mulDown(config.positionDuration.divDown(365 days))
        );

        // Ensure the deposit accounting is correct.
        verifyDeposit(
            bob,
            basePaid,
            true,
            totalBaseSupplyBefore,
            totalSharesSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// Utilities ///

    struct AccountBalances {
        uint256 sharesBalance;
        uint256 baseBalance;
        uint256 ETHBalance;
    }

    function getAccountBalances(
        address account
    ) internal view returns (AccountBalances memory) {
        (uint256 base, uint256 shares) = getTokenBalances(account);

        return
            AccountBalances({
                sharesBalance: shares,
                baseBalance: base,
                ETHBalance: account.balance
            });
    }
}
