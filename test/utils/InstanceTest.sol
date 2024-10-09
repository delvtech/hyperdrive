// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { ERC20ForwarderFactory } from "../../contracts/src/token/ERC20ForwarderFactory.sol";
import { HyperdriveFactory } from "../../contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../../contracts/src/interfaces/IHyperdriveDeployerCoordinator.sol";
import { IHyperdriveFactory } from "../../contracts/src/interfaces/IHyperdriveFactory.sol";
import { AssetId } from "../../contracts/src/libraries/AssetId.sol";
import { ETH, VERSION } from "../../contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "../../contracts/src/libraries/FixedPointMath.sol";
import { SafeCast } from "../../contracts/src/libraries/SafeCast.sol";
import { ERC20Mintable } from "../../contracts/test/ERC20Mintable.sol";
import { HyperdriveTest } from "./HyperdriveTest.sol";
import { HyperdriveUtils } from "./HyperdriveUtils.sol";
import { Lib } from "./Lib.sol";

/// @author DELV
/// @title InstanceTest
/// @notice The base contract for the instance testing suite.
/// @dev A testing suite that provides a foundation to setup, deploy, and
///      test common cases for Hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract InstanceTest is HyperdriveTest {
    using HyperdriveUtils for *;
    using FixedPointMath for *;
    using Lib for *;
    using SafeCast for *;

    /// @dev Configuration for the Instance testing suite.
    struct InstanceTestConfig {
        /// @dev The instance's name.
        string name;
        /// @dev The instance's kind.
        string kind;
        /// @dev The amount of decimals used by the instance's base token.
        uint8 decimals;
        /// @dev The whale accounts for the base token.
        address[] baseTokenWhaleAccounts;
        /// @dev The whale accounts for the vault shares token.
        address[] vaultSharesTokenWhaleAccounts;
        /// @dev The instance's base token.
        IERC20 baseToken;
        /// @dev The instance's vault shares token.
        IERC20 vaultSharesToken;
        /// @dev The tolerance to use with assertions involving conversions from
        ///      base to shares.
        uint256 shareTolerance;
        /// @dev The instance's minimum share reserves.
        uint256 minimumShareReserves;
        /// @dev The instance's minimum transaction amount.
        uint256 minimumTransactionAmount;
        /// @dev The fees that will be used in these tests. This can be helpful
        ///      when testing pools with small amounts of precision to ensure
        ///      that the pools are safe.
        IHyperdrive.Fees fees;
        /// @dev The instance's position duration.
        uint256 positionDuration;
        /// @dev Indicates whether or not the instance accepts base deposits.
        bool enableBaseDeposits;
        /// @dev Indicates whether or not the instance accepts share deposits.
        bool enableShareDeposits;
        /// @dev Indicates whether or not the instance accepts base withdrawals.
        bool enableBaseWithdraws;
        /// @dev Indicates whether or not the instance accepts share withdrawals.
        bool enableShareWithdraws;
        /// @dev An optional error message that can be used in cases where base
        ///      withdrawals will fail with a message that isn't
        ///      "UnsupportedToken".
        bytes baseWithdrawError;
        /// @dev Indicates whether or not the vault shares token is a rebasing
        ///      token. If it is, we have to handle balances and approvals
        ///      differently.
        bool isRebasing;
        /// @dev Indicates whether or not we should accrue interest. Most yield
        ///      sources accrue interest, but in special cases, Hyperdrive may
        ///      integrate with yield sources that don't accrue interest.
        bool shouldAccrueInterest;
        /// @dev The equality tolerance in wei for the close long with shares
        ///      test.
        uint256 closeLongWithSharesTolerance;
        /// @dev The equality tolerance in wei for the close long with base
        ///      test.
        uint256 closeLongWithBaseTolerance;
        /// @dev The equality tolerance in wei for the close short with shares
        ///      test.
        uint256 closeShortWithSharesTolerance;
        /// @dev The equality tolerance in wei for the instantaneous LP with
        ///      base test.
        uint256 roundTripLpInstantaneousWithBaseTolerance;
        /// @dev The equality tolerance in wei for the instantaneous LP with
        ///      shares test.
        uint256 roundTripLpInstantaneousWithSharesTolerance;
        /// @dev The equality tolerance in wei for the LP withdrawal shares with
        ///      base test.
        uint256 roundTripLpWithdrawalSharesWithBaseTolerance;
        /// @dev The equality tolerance in wei for the LP withdrawal shares with
        ///      shares test.
        uint256 roundTripLpWithdrawalSharesWithSharesTolerance;
        /// @dev The upper bound tolerance in wei for the instantaneous long
        ///      round trip with base test.
        uint256 roundTripLongInstantaneousWithBaseUpperBoundTolerance;
        /// @dev The equality tolerance in wei for the instantaneous long round
        ///      trip with base test.
        uint256 roundTripLongInstantaneousWithBaseTolerance;
        /// @dev The upper bound tolerance in wei for the instantaneous long
        ///      round trip with shares test.
        uint256 roundTripLongInstantaneousWithSharesUpperBoundTolerance;
        /// @dev The equality tolerance in wei for the instantaneous long round
        ///      trip with shares test.
        uint256 roundTripLongInstantaneousWithSharesTolerance;
        /// @dev The upper bound tolerance in wei for the long at maturity round
        ///      trip with base test.
        uint256 roundTripLongMaturityWithBaseUpperBoundTolerance;
        /// @dev The equality tolerance in wei for the long at maturity round
        ///      trip with base test.
        uint256 roundTripLongMaturityWithBaseTolerance;
        /// @dev The upper bound tolerance in wei for the long at maturity round
        ///      trip with shares test.
        uint256 roundTripLongMaturityWithSharesUpperBoundTolerance;
        /// @dev The equality tolerance in wei for the long at maturity round
        ///      trip with shares test.
        uint256 roundTripLongMaturityWithSharesTolerance;
        /// @dev The upper bound tolerance in wei for the instantaneous short
        ///      round trip with base test.
        uint256 roundTripShortInstantaneousWithBaseUpperBoundTolerance;
        /// @dev The equality tolerance in wei for the instantaneous short round
        ///      trip with base test.
        uint256 roundTripShortInstantaneousWithBaseTolerance;
        /// @dev The upper bound tolerance in wei for the instantaneous short
        ///      round trip with shares test.
        uint256 roundTripShortInstantaneousWithSharesUpperBoundTolerance;
        /// @dev The equality tolerance in wei for the instantaneous short round
        ///      trip with shares test.
        uint256 roundTripShortInstantaneousWithSharesTolerance;
        /// @dev The equality tolerance in wei for the short at maturity round
        ///      trip with base test.
        uint256 roundTripShortMaturityWithBaseTolerance;
        /// @dev The equality tolerance in wei for the short at maturity round
        ///      trip with shares test.
        uint256 roundTripShortMaturityWithSharesTolerance;
        /// @dev The equality tolerance in wei for `verifyDeposit`.
        uint256 verifyDepositTolerance;
        /// @dev The equality tolerance in wei for `verifyWithdrawal`.
        uint256 verifyWithdrawalTolerance;
    }

    /// @dev Fixed rate used to configure market.
    uint256 internal constant FIXED_RATE = 0.05e18;

    /// @dev Default deployment constants.
    bytes32 private constant DEFAULT_DEPLOYMENT_ID =
        bytes32(uint256(0xdeadbeef));
    bytes32 private constant DEFAULT_DEPLOYMENT_SALT =
        bytes32(uint256(0xdeadbabe));

    /// @dev The configuration for the Instance testing suite.
    InstanceTestConfig internal config;

    /// @dev The configuration for the pool. This allows test authors to specify
    ///      parameters like fee parameters, minimum share reserves, etc. Some
    ///      parameters will be overridden by factory parameters.
    IHyperdrive.PoolDeployConfig internal poolConfig;

    /// @dev The Hyperdrive factory.
    IHyperdriveFactory internal factory;

    /// @dev The address of the deployer coordinator contract.
    address internal deployerCoordinator;

    /// @dev Flag for denoting if the base token is ETH.
    bool internal immutable isBaseETH;

    /// @dev Constructor for the Instance testing suite.
    /// @param _config The Instance configuration.
    constructor(InstanceTestConfig memory _config) {
        config = _config;
        isBaseETH = config.baseToken == IERC20(ETH);
    }

    /// Deployments ///

    /// @notice Forge setup function.
    /// @dev Inherits from HyperdriveTest and deploys the
    ///      Hyperdrive factory, deployer coordinator, and targets.
    function setUp() public virtual override {
        super.setUp();

        // Fund accounts with ETH and vault shares from whales.
        vm.deal(alice, 100_000e18);
        vm.deal(bob, 100_000e18);
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        for (uint256 i = 0; i < config.baseTokenWhaleAccounts.length; i++) {
            fundAccounts(
                address(hyperdrive),
                config.baseToken,
                config.baseTokenWhaleAccounts[i],
                accounts
            );
        }
        for (
            uint256 i = 0;
            i < config.vaultSharesTokenWhaleAccounts.length;
            i++
        ) {
            fundAccounts(
                address(hyperdrive),
                config.vaultSharesToken,
                config.vaultSharesTokenWhaleAccounts[i],
                accounts
            );
        }

        // Deploy the Hyperdrive Factory contract.
        deployFactory();

        // Set the deployer coordinator address and add to the factory.
        deployerCoordinator = deployCoordinator(address(factory));
        factory.addDeployerCoordinator(deployerCoordinator);

        // If share deposits are enabled and the vault shares token isn't a
        // rebasing token, the contribution is the minimum of a tenth of Alice's
        // vault shares balance and 1000 vault shares in units of vault shares.
        uint256 contribution;
        if (config.enableShareDeposits && !config.isRebasing) {
            contribution = (poolConfig.vaultSharesToken.balanceOf(alice) / 10)
                .min(1_000 * 10 ** config.decimals);
        }
        // If share deposits are enabled and the vault shares token is a
        // rebasing token, the contribution is the minimum of a tenth of Alice's
        // vault shares balance and 1000 vault shares in units of base.
        else if (config.enableShareDeposits) {
            contribution = convertToShares(
                (poolConfig.vaultSharesToken.balanceOf(alice) / 10).min(
                    1_000 * 10 ** config.decimals
                )
            );
        }
        // If share deposits are disabled and the base token isn't ETH, the
        // contribution is the minimum of a tenth of Alice's base balance and
        // 1000 base.
        else if (!isBaseETH) {
            contribution = (poolConfig.baseToken.balanceOf(alice) / 10).min(
                1_000 * 10 ** config.decimals
            );
        }
        // If share deposits are disabled and the base token is ETH, the
        // contribution is the minimum of a tenth of Alice's ETH balance and
        // 1000 base.
        else {
            contribution = (alice.balance / 10).min(
                1_000 * 10 ** config.decimals
            );
        }

        // Deploy all Hyperdrive contracts using deployer coordinator contract.
        deployHyperdrive(
            DEFAULT_DEPLOYMENT_ID, // Deployment Id
            DEFAULT_DEPLOYMENT_SALT, // Deployment Salt
            contribution, // Contribution
            !config.enableShareDeposits // asBase
        );

        // If base deposits are supported, approve a large amount of shares for
        // Alice and Bob.
        if (config.enableBaseDeposits && !isBaseETH) {
            vm.stopPrank();
            vm.startPrank(alice);
            config.baseToken.approve(
                address(hyperdrive),
                poolConfig.baseToken.balanceOf(alice)
            );
            vm.stopPrank();
            vm.startPrank(bob);
            config.baseToken.approve(
                address(hyperdrive),
                poolConfig.baseToken.balanceOf(bob)
            );
        }

        // If share deposits are supported, approve a large amount of shares for
        // Alice and Bob.
        if (config.enableShareDeposits) {
            vm.stopPrank();
            vm.startPrank(alice);
            config.vaultSharesToken.approve(
                address(hyperdrive),
                poolConfig.vaultSharesToken.balanceOf(alice)
            );
            vm.stopPrank();
            vm.startPrank(bob);
            config.vaultSharesToken.approve(
                address(hyperdrive),
                poolConfig.vaultSharesToken.balanceOf(bob)
            );
        }

        // Ensure that Alice received the correct amount of LP tokens. She should
        // receive LP shares totaling the amount of shares that she contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        if (config.enableShareDeposits) {
            assertApproxEqAbs(
                hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
                contribution -
                    2 *
                    hyperdrive.getPoolConfig().minimumShareReserves,
                config.shareTolerance
            );
        } else {
            assertApproxEqAbs(
                hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
                convertToShares(contribution) -
                    2 *
                    hyperdrive.getPoolConfig().minimumShareReserves,
                config.shareTolerance
            );
        }

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
        for (
            uint256 i = 0;
            i <
            IHyperdriveDeployerCoordinator(deployerCoordinator)
                .getNumberOfTargets();
            i++
        ) {
            factory.deployTarget(
                deploymentId,
                deployerCoordinator,
                poolConfig,
                getExtraData(),
                FIXED_RATE,
                FIXED_RATE,
                i,
                deploymentSalt
            );
        }

        // If base is being used and the base token isn't ETH, we set an
        // approval on the deployer coordinator with the contribution in base.
        if (asBase && !isBaseETH) {
            config.baseToken.approve(deployerCoordinator, contribution);
        }
        // If vault shares is being used and the vault shares token isn't a
        // rebasing token, we set an approval on the deployer coordinator
        // with the contribution in vault shares.
        else if (!asBase && !config.isRebasing) {
            config.vaultSharesToken.approve(deployerCoordinator, contribution);
        }
        // If vault shares is being used and the vault shares token is a
        // rebasing token, we set an approval on the deployer coordinator
        // with the contribution in base.
        else if (!asBase) {
            config.vaultSharesToken.approve(
                deployerCoordinator,
                convertToBase(contribution)
            );
        }

        // We expect the deployAndInitialize to fail with an
        // UnsupportedToken error if depositing with base are not supported.
        // If the base token is ETH we expect a NotPayable error.
        if (!config.enableBaseDeposits && asBase) {
            vm.expectRevert(
                isBaseETH
                    ? IHyperdrive.NotPayable.selector
                    : IHyperdrive.UnsupportedToken.selector
            );
        }

        // We expect the deployAndInitialize to fail with an
        // UnsupportedToken error if depositing with shares are not supported.
        if (!config.enableShareDeposits && !asBase) {
            vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        }

        // Record Alice's ETH balance before the deployment call.
        uint256 aliceBalanceBefore = address(alice).balance;

        // Deploy and initialize the market. If the base token is ETH we pass
        // twice the contribution through the call to test refunds.
        hyperdrive = factory.deployAndInitialize{
            value: asBase && isBaseETH ? 2 * contribution : 0
        }(
            deploymentId,
            deployerCoordinator,
            config.name,
            poolConfig,
            getExtraData(),
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
            // Ensure that alice's ETH balance only decreased by the contribution.
            assertEq(aliceBalanceBefore - contribution, address(alice).balance);
        } else {
            assertEq(aliceBalanceBefore, address(alice).balance);
        }
    }

    /// @dev Deploys the Hyperdrive Factory contract and sets the default pool
    ///      configuration.
    function deployFactory() private {
        // Deploy the hyperdrive factory.
        vm.startPrank(deployer);
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ERC20ForwarderFactory("ForwarderFactory");
        factory = new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                deployerCoordinatorManager: celine,
                hyperdriveGovernance: bob,
                feeCollector: celine,
                sweepCollector: sweepCollector,
                checkpointRewarder: address(0),
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minCircuitBreakerDelta: 0.15e18,
                // NOTE: This is a high max circuit breaker delta to ensure that
                // trading during tests isn't impeded by the circuit breaker.
                maxCircuitBreakerDelta: 2e18,
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
            }),
            "HyperdriveFactory"
        );

        // Update the pool configuration that will be used for instance
        // deployments.
        poolConfig = IHyperdrive.PoolDeployConfig({
            baseToken: config.baseToken,
            vaultSharesToken: config.vaultSharesToken,
            linkerFactory: factory.linkerFactory(),
            linkerCodeHash: factory.linkerCodeHash(),
            minimumShareReserves: config.minimumShareReserves,
            minimumTransactionAmount: config.minimumTransactionAmount,
            circuitBreakerDelta: 2e18,
            positionDuration: config.positionDuration,
            checkpointDuration: CHECKPOINT_DURATION,
            timeStretch: 0,
            governance: factory.hyperdriveGovernance(),
            feeCollector: factory.feeCollector(),
            sweepCollector: factory.sweepCollector(),
            checkpointRewarder: address(0),
            fees: config.fees
        });
    }

    /// Overrides ///

    /// @dev A virtual function that defines the deployer coordinator
    ///      contract that will be used to deploy all the instance targets.
    /// @param _factory The address of the Hyperdrive factory contract.
    function deployCoordinator(
        address _factory
    ) internal virtual returns (address);

    /// @dev Gets the extra data used to deploy Hyperdrive instances.
    /// @return The extra data.
    function getExtraData() internal view virtual returns (bytes memory);

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

    /// @dev Verifies that deposit accounting is correct when opening positions.
    /// @param trader The trader that is depositing.
    /// @param amountPaid The amount that was deposited.
    /// @param asBase Whether the deposit was made with base or vault shares.
    /// @param totalBaseBefore The total base before the deposit.
    /// @param totalSharesBefore The total shares before the deposit.
    /// @param traderBalancesBefore The trader balances before the deposit.
    /// @param hyperdriveBalancesBefore The hyperdrive balances before the deposit.
    function verifyDeposit(
        address trader,
        uint256 amountPaid,
        bool asBase,
        uint256 totalBaseBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view {
        // If we're depositing with base, verify that base was pulled from the
        // trader into Hyperdrive and correctly converted to vault shares.
        if (asBase) {
            // If base deposits aren't supported, we revert since this route
            // shouldn't be called.
            if (!config.enableBaseDeposits) {
                revert IHyperdrive.UnsupportedToken();
            }

            // Ensure that the total supply increased by the base paid.
            (uint256 totalBase, uint256 totalShares) = getSupply();
            assertApproxEqAbs(
                totalBase,
                totalBaseBefore + amountPaid,
                config.verifyDepositTolerance
            );
            assertApproxEqAbs(
                totalShares,
                totalSharesBefore + hyperdrive.convertToShares(amountPaid),
                config.verifyDepositTolerance
            );

            // If the base token isn't ETH, ensure that the ETH balances didn't
            // change.
            if (!isBaseETH) {
                assertEq(
                    address(hyperdrive).balance,
                    hyperdriveBalancesBefore.ETHBalance
                );
                assertEq(trader.balance, traderBalancesBefore.ETHBalance);
            }
            // Otherwise, the trader's ETH balance should be reduced by the
            // amount paid.
            else {
                assertEq(
                    address(hyperdrive).balance,
                    hyperdriveBalancesBefore.ETHBalance
                );
                assertEq(
                    trader.balance,
                    traderBalancesBefore.ETHBalance - amountPaid
                );
            }

            // Ensure that the Hyperdrive instance's base balance doesn't change
            // and that the trader's base balance decreased by the amount paid.
            (
                uint256 hyperdriveBaseAfter,
                uint256 hyperdriveSharesAfter
            ) = getTokenBalances(address(hyperdrive));
            (
                uint256 traderBaseAfter,
                uint256 traderSharesAfter
            ) = getTokenBalances(address(trader));
            assertEq(hyperdriveBaseAfter, hyperdriveBalancesBefore.baseBalance);
            assertEq(
                traderBaseAfter,
                traderBalancesBefore.baseBalance - amountPaid
            );

            // Ensure that the shares balances were updated correctly.
            assertApproxEqAbs(
                hyperdriveSharesAfter,
                hyperdriveBalancesBefore.sharesBalance +
                    hyperdrive.convertToShares(amountPaid),
                config.verifyDepositTolerance
            );
            assertEq(traderSharesAfter, traderBalancesBefore.sharesBalance);
        }
        // If we're depositing with vault shares, verify that the vault shares
        // were pulled from the trader into Hyperdrive.
        else {
            // If vault share deposits aren't supported, we revert since this
            // route shouldn't be called.
            if (!config.enableShareDeposits) {
                revert IHyperdrive.UnsupportedToken();
            }

            // Ensure that the total supply and scaled total supply stay the same.
            (uint256 totalBase, uint256 totalShares) = getSupply();
            assertEq(totalBase, totalBaseBefore);
            assertApproxEqAbs(
                totalShares,
                totalSharesBefore,
                config.verifyDepositTolerance
            );

            // Ensure that the ETH balances didn't change.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(bob.balance, traderBalancesBefore.ETHBalance);

            // Ensure that the base balances didn't change.
            (
                uint256 hyperdriveBaseAfter,
                uint256 hyperdriveSharesAfter
            ) = getTokenBalances(address(hyperdrive));
            (
                uint256 traderBaseAfter,
                uint256 traderSharesAfter
            ) = getTokenBalances(address(trader));
            assertEq(hyperdriveBaseAfter, hyperdriveBalancesBefore.baseBalance);
            assertEq(traderBaseAfter, traderBalancesBefore.baseBalance);

            // Ensure that the shares balances were updated correctly.
            assertApproxEqAbs(
                hyperdriveSharesAfter,
                hyperdriveBalancesBefore.sharesBalance +
                    convertToShares(amountPaid),
                config.verifyDepositTolerance
            );
            assertApproxEqAbs(
                traderSharesAfter,
                traderBalancesBefore.sharesBalance -
                    convertToShares(amountPaid),
                config.verifyDepositTolerance
            );
        }
    }

    /// @dev Verifies that withdrawal accounting is correct when closing positions.
    /// @param trader The trader that is withdrawing.
    /// @param baseProceeds The base proceeds of the deposit.
    /// @param asBase Whether the withdrawal was made with base or vault shares.
    /// @param totalBaseBefore The total base before the withdrawal.
    /// @param totalSharesBefore The total shares before the withdrawal.
    /// @param traderBalancesBefore The trader balances before the withdrawal.
    /// @param hyperdriveBalancesBefore The hyperdrive balances before the withdrawal.
    function verifyWithdrawal(
        address trader,
        uint256 baseProceeds,
        bool asBase,
        uint256 totalBaseBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view {
        // If we're withdrawing with base, ensure that Hyperdrive's vault shares
        // were reduced, successfully converted into base, and distributed to
        // the trader.
        if (asBase) {
            // If base withdrawals aren't supported, we revert since this
            // route shouldn't be called.
            if (!config.enableBaseWithdraws) {
                revert IHyperdrive.UnsupportedToken();
            }

            // Ensure that the total supply decreased by the base proceeds.
            (uint256 totalBase, uint256 totalShares) = getSupply();
            assertApproxEqAbs(totalBase, totalBaseBefore - baseProceeds, 1);
            assertApproxEqAbs(
                totalShares,
                totalSharesBefore - convertToShares(baseProceeds),
                config.verifyWithdrawalTolerance
            );

            // If the base token isn't ETH, ensure that the ETH balances didn't
            // change.
            if (!isBaseETH) {
                assertEq(
                    address(hyperdrive).balance,
                    hyperdriveBalancesBefore.ETHBalance
                );
                assertEq(bob.balance, traderBalancesBefore.ETHBalance);
            }
            // Otherwise, ensure that the trader's ETH balance increased.
            else {
                assertEq(
                    address(hyperdrive).balance,
                    hyperdriveBalancesBefore.ETHBalance
                );
                assertEq(
                    bob.balance,
                    traderBalancesBefore.ETHBalance + baseProceeds
                );
            }

            // Ensure that the base balances were updated correctly.
            (
                uint256 hyperdriveBaseAfter,
                uint256 hyperdriveSharesAfter
            ) = getTokenBalances(address(hyperdrive));
            (
                uint256 traderBaseAfter,
                uint256 traderSharesAfter
            ) = getTokenBalances(address(trader));
            assertEq(hyperdriveBaseAfter, hyperdriveBalancesBefore.baseBalance);
            assertEq(
                traderBaseAfter,
                traderBalancesBefore.baseBalance + baseProceeds
            );

            // Ensure that the shares balances were updated correctly.
            assertApproxEqAbs(
                hyperdriveSharesAfter,
                hyperdriveBalancesBefore.sharesBalance -
                    convertToShares(baseProceeds),
                config.verifyWithdrawalTolerance
            );
            assertApproxEqAbs(
                traderSharesAfter,
                traderBalancesBefore.sharesBalance,
                config.verifyWithdrawalTolerance
            );
        } else {
            // If vault share withdrawals aren't supported, we revert since this
            // route shouldn't be called.
            if (!config.enableShareWithdraws) {
                revert IHyperdrive.UnsupportedToken();
            }

            // Ensure that the total supply stayed the same.
            (uint256 totalBase, uint256 totalShares) = getSupply();
            assertApproxEqAbs(totalBase, totalBaseBefore, 1);
            assertApproxEqAbs(totalShares, totalSharesBefore, 1);

            // Ensure that the ETH balances didn't change.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(bob.balance, traderBalancesBefore.ETHBalance);

            // Ensure that the base balances didn't change.
            (
                uint256 hyperdriveBaseAfter,
                uint256 hyperdriveSharesAfter
            ) = getTokenBalances(address(hyperdrive));
            (
                uint256 traderBaseAfter,
                uint256 traderSharesAfter
            ) = getTokenBalances(address(trader));
            assertApproxEqAbs(
                hyperdriveBaseAfter,
                hyperdriveBalancesBefore.baseBalance,
                config.verifyWithdrawalTolerance
            );
            assertApproxEqAbs(
                traderBaseAfter,
                traderBalancesBefore.baseBalance,
                config.verifyWithdrawalTolerance
            );

            // Ensure that the shares balances were updated correctly.
            assertApproxEqAbs(
                hyperdriveSharesAfter,
                hyperdriveBalancesBefore.sharesBalance -
                    convertToShares(baseProceeds),
                config.verifyWithdrawalTolerance
            );
            assertApproxEqAbs(
                traderSharesAfter,
                traderBalancesBefore.sharesBalance +
                    convertToShares(baseProceeds),
                config.verifyWithdrawalTolerance
            );
        }
    }

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
        view
        virtual
        returns (uint256 totalSupplyBase, uint256 totalSupplyShares);

    /// Tests ///

    /// @dev Tests that the names of the Hyperdrive instance and deployer
    ///      coordinator are correct.
    function test__name() external view {
        assertEq(hyperdrive.name(), config.name);
        assertEq(
            IHyperdriveDeployerCoordinator(deployerCoordinator).name(),
            string.concat(config.name, "DeployerCoordinator")
        );
    }

    /// @dev Tests that the kinds of the Hyperdrive instance and deployer
    ///      coordinator are correct.
    function test__kind() external view {
        assertEq(hyperdrive.kind(), config.kind);
        assertEq(
            IHyperdriveDeployerCoordinator(deployerCoordinator).kind(),
            string.concat(config.kind, "DeployerCoordinator")
        );
    }

    /// @dev Tests that the versions of the Hyperdrive instance and deployer
    ///      coordinator are correct.
    function test__version() external view {
        assertEq(hyperdrive.version(), VERSION);
        assertEq(
            IHyperdriveDeployerCoordinator(deployerCoordinator).version(),
            VERSION
        );
    }

    /// @dev Test to verify a market can be deployed and initialized funded by the
    ///      base token. Is expected to revert when base deposits are not supported.
    function test__deployAndInitialize__asBase() external virtual {
        uint256 aliceBalanceBefore = address(alice).balance;

        // Early termination if base deposits are not supported.
        if (!config.enableBaseDeposits) {
            return;
        }

        // If the base asset isn't ETH, the contribution is the minimum of a
        // tenth of Alice's balance and 1000 base tokens.
        uint256 contribution;
        if (!isBaseETH) {
            contribution = (poolConfig.baseToken.balanceOf(alice) / 10).min(
                1_000 * 10 ** config.decimals
            );
        }
        // Otherwise, if the base asset is eth, the contribution is the minimum
        // of a tenth of Alice's balance and 1000 base tokens.
        else {
            contribution = (alice.balance / 10).min(
                1_000 * 10 ** config.decimals
            );
        }

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

        // If base deposits are enabled we verify some assertions.
        if (isBaseETH) {
            // If the base token is ETH we assert the ETH balance is correct.
            assertEq(address(alice).balance, aliceBalanceBefore - contribution);
        }

        // Ensure that the decimals are set correctly.
        assertEq(hyperdrive.decimals(), config.decimals);

        // Ensure that Alice received the correct amount of LP tokens. She should
        // receive LP shares totaling the amount of shares that he contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            hyperdrive.convertToShares(contribution) -
                2 *
                hyperdrive.getPoolConfig().minimumShareReserves,
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
            getExtraData(),
            config.shareTolerance
        );
    }

    /// @dev Test to verify a market can be deployed and initialized funded
    ///      by the share token.
    function test__deployAndInitialize__asShares() external {
        uint256 aliceBalanceBefore = address(alice).balance;

        // Early termination if share deposits are not supported.
        if (!config.enableShareDeposits) {
            return;
        }

        // Contribution in terms of shares.
        uint256 contribution = (poolConfig.vaultSharesToken.balanceOf(alice) /
            10).min(1_000 * 10 ** config.decimals);
        if (config.isRebasing) {
            contribution = convertToShares(contribution);
        }

        // Deploy all Hyperdrive contracts using deployer coordinator contract.
        deployHyperdrive(
            bytes32(uint256(0xbeefbabe)), // Deployment Id
            bytes32(uint256(0xdeadfade)), // Deployment Salt
            contribution, // Contribution
            false // asBase
        );

        // Ensure Alice's ETH balance remains the same.
        assertEq(address(alice).balance, aliceBalanceBefore);

        // Ensure that the decimals are set correctly.
        assertEq(hyperdrive.decimals(), config.decimals);

        // Ensure that Alice received the correct amount of LP tokens. She should
        // receive LP shares totaling the amount of shares that he contributed
        // minus the shares set aside for the minimum share reserves and the
        // zero address's initial LP contribution.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            contribution - 2 * hyperdrive.getPoolConfig().minimumShareReserves,
            config.shareTolerance // Custom share tolerance per instance.
        );

        // Ensure that the share reserves and LP total supply are equal and correct.
        assertEq(hyperdrive.getPoolInfo().shareReserves, contribution);
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
            contribution,
            FIXED_RATE,
            false,
            poolConfig.minimumShareReserves,
            getExtraData(),
            config.shareTolerance
        );
    }

    /// LPs ///

    /// @dev Fuzz test to ensure that LP payouts are correct when they withdraw
    ///      instantaneously and when depositing and withdrawing with base.
    /// @param _contribution The fuzz parameter for the LP's contribution.
    function test_round_trip_lp_instantaneous_with_base(
        uint256 _contribution
    ) external {
        // If base deposits aren't enabled, we skip the test.
        if (!config.enableBaseDeposits) {
            return;
        }

        // Bob adds liquidity with base.
        if (isBaseETH) {
            _contribution = _contribution.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                bob.balance / 10
            );
        } else {
            _contribution = _contribution.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                IERC20(hyperdrive.baseToken()).balanceOf(bob) / 10
            );
        }
        uint256 lpShares = addLiquidity(bob, _contribution);

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // If base withdrawals are supported, we withdraw with base.
        uint256 baseProceeds;
        if (config.enableBaseWithdraws) {
            // Bob removes his liquidity with base as the target asset.
            uint256 withdrawalShares;
            (baseProceeds, withdrawalShares) = removeLiquidity(bob, lpShares);
            assertEq(withdrawalShares, 0);

            // Bob should receive approximately as much base as he contributed since
            // no time as passed and the fees are zero.
            assertApproxEqAbs(
                baseProceeds,
                _contribution,
                config.roundTripLpInstantaneousWithBaseTolerance
            );
        }
        // Otherwise, we withdraw with shares.
        else {
            // Bob removes his liquidity with vault shares as the target asset.
            (
                uint256 vaultSharesProceeds,
                uint256 withdrawalShares
            ) = removeLiquidity(bob, lpShares, false);
            baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);
            assertEq(withdrawalShares, 0);

            // Bob should receive approximately as many vault shares as he
            // contributed since no time as passed and the fees are zero.
            assertApproxEqAbs(
                vaultSharesProceeds,
                hyperdrive.convertToShares(_contribution),
                config.roundTripLpInstantaneousWithSharesTolerance
            );
        }

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            config.enableBaseWithdraws,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz test to ensure that LP payouts are correct when they withdraw
    ///      instantaneously and when depositing and withdrawing with vault
    ///      shares.
    /// @param _contribution The fuzz parameter for the LP's contribution.
    function test_round_trip_lp_instantaneous_with_shares(
        uint256 _contribution
    ) external {
        // If share deposits aren't enabled, we skip the test.
        if (!config.enableShareDeposits) {
            return;
        }

        // Bob adds liquidity with vault shares.
        _contribution = _contribution.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            IERC20(hyperdrive.vaultSharesToken()).balanceOf(bob) / 10
        );
        if (config.isRebasing) {
            _contribution = convertToShares(_contribution);
        }
        uint256 lpShares = addLiquidity(bob, _contribution, false);

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // If vault share withdrawals are supported, we withdraw with vault
        // shares.
        uint256 baseProceeds;
        if (config.enableShareWithdraws) {
            // Bob removes his liquidity with vault shares as the target asset.
            (
                uint256 vaultSharesProceeds,
                uint256 withdrawalShares
            ) = removeLiquidity(bob, lpShares, false);
            baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);
            assertEq(withdrawalShares, 0);

            // Bob should receive approximately as many vault shares as he
            // contributed since no time as passed and the fees are zero.
            assertApproxEqAbs(
                vaultSharesProceeds,
                _contribution,
                config.roundTripLpInstantaneousWithSharesTolerance
            );
        }
        // Otherwise we withdraw with base.
        else {
            // Bob removes his liquidity with base as the target asset.
            uint256 withdrawalShares;
            (baseProceeds, withdrawalShares) = removeLiquidity(bob, lpShares);
            assertEq(withdrawalShares, 0);

            // Bob should receive approximately as much base as he contributed since
            // no time as passed and the fees are zero.
            assertApproxEqAbs(
                baseProceeds,
                _contribution,
                config.roundTripLpInstantaneousWithBaseTolerance
            );
        }

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            !config.enableShareWithdraws,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz test to ensure that the withdrawal shares payouts are correct
    ///      when depositing and withdrawing with base.
    /// @param _contribution The fuzz parameter for the LP's contribution.
    /// @param _variableRate The fuzz parameter for the variable rate.
    function test_round_trip_lp_withdrawal_shares_with_base(
        uint256 _contribution,
        uint256 _variableRate
    ) external {
        // If base deposits aren't enabled, we skip the test.
        if (!config.enableBaseDeposits) {
            return;
        }

        // Bob adds liquidity with base.
        if (isBaseETH) {
            _contribution = _contribution.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                bob.balance / 10
            );
        } else {
            _contribution = _contribution.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                IERC20(hyperdrive.baseToken()).balanceOf(bob) / 10
            );
        }
        uint256 lpShares = addLiquidity(bob, _contribution);

        // Alice opens a large short.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 shortAmount = hyperdrive.calculateMaxShort();
        openShort(alice, shortAmount);

        // If base withdrawals are supported, we withdraw with base.
        if (config.enableBaseWithdraws) {
            // Bob removes his liquidity with base as the target asset.
            (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
                bob,
                lpShares
            );
            assertGt(withdrawalShares, 0);

            // The term passes and interest accrues.
            if (config.shouldAccrueInterest) {
                _variableRate = _variableRate.normalizeToRange(0, 2.5e18);
            } else {
                _variableRate = 0;
            }
            advanceTime(
                hyperdrive.getPoolConfig().positionDuration,
                int256(_variableRate)
            );
            hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

            // Bob should be able to redeem all of his withdrawal shares for
            // approximately the LP share price.
            uint256 lpSharePrice = hyperdrive.getPoolInfo().lpSharePrice;
            uint256 withdrawalSharesRedeemed;
            (baseProceeds, withdrawalSharesRedeemed) = redeemWithdrawalShares(
                bob,
                withdrawalShares
            );
            assertEq(withdrawalSharesRedeemed, withdrawalShares);

            // Bob should receive base approximately equal in value to his present
            // value.
            assertApproxEqAbs(
                baseProceeds,
                withdrawalShares.mulDown(lpSharePrice),
                config.roundTripLpWithdrawalSharesWithBaseTolerance
            );
        }
        // Otherwise we withdraw with vault shares.
        else {
            // Bob removes his liquidity with vault shares as the target asset.
            (
                uint256 vaultSharesProceeds,
                uint256 withdrawalShares
            ) = removeLiquidity(bob, lpShares, false);
            assertGt(withdrawalShares, 0);

            // The term passes and interest accrues.
            if (config.shouldAccrueInterest) {
                _variableRate = _variableRate.normalizeToRange(0, 2.5e18);
            } else {
                _variableRate = 0;
            }
            advanceTime(
                hyperdrive.getPoolConfig().positionDuration,
                int256(_variableRate)
            );
            hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

            // Bob should be able to redeem all of his withdrawal shares for
            // approximately the LP share price.
            uint256 lpSharePrice = hyperdrive.getPoolInfo().lpSharePrice;
            uint256 withdrawalSharesRedeemed;
            (
                vaultSharesProceeds,
                withdrawalSharesRedeemed
            ) = redeemWithdrawalShares(bob, withdrawalShares, false);
            uint256 baseProceeds = hyperdrive.convertToBase(
                vaultSharesProceeds
            );
            assertEq(withdrawalSharesRedeemed, withdrawalShares);

            // Bob should receive base approximately equal in value to his present
            // value.
            assertApproxEqAbs(
                baseProceeds,
                withdrawalShares.mulDown(lpSharePrice),
                config.roundTripLpWithdrawalSharesWithSharesTolerance
            );
        }
    }

    /// @dev Fuzz test to ensure that the withdrawal shares payouts are correct
    ///      when depositing and withdrawing with vault shares.
    /// @param _contribution The fuzz parameter for the LP's contribution.
    /// @param _variableRate The fuzz parameter for the variable rate.
    function test_round_trip_lp_withdrawal_shares_with_shares(
        uint256 _contribution,
        uint256 _variableRate
    ) external {
        // If share deposits aren't enabled, we skip the test.
        if (!config.enableShareDeposits) {
            return;
        }

        // Bob adds liquidity with vault shares.
        _contribution = _contribution.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            IERC20(hyperdrive.vaultSharesToken()).balanceOf(bob) / 10
        );
        if (config.isRebasing) {
            _contribution = convertToShares(_contribution);
        }
        uint256 lpShares = addLiquidity(bob, _contribution, false);

        // Alice opens a large short.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 shortAmount = hyperdrive.calculateMaxShort();
        openShort(alice, shortAmount, false);

        // If vault share withdrawals are supported, we withdraw with vault
        // shares.
        if (config.enableShareWithdraws) {
            // Bob removes his liquidity with vault shares as the target asset.
            (
                uint256 vaultSharesProceeds,
                uint256 withdrawalShares
            ) = removeLiquidity(bob, lpShares, false);
            assertGt(withdrawalShares, 0);

            // The term passes and interest accrues.
            if (config.shouldAccrueInterest) {
                _variableRate = _variableRate.normalizeToRange(0, 2.5e18);
            } else {
                _variableRate = 0;
            }
            advanceTime(
                hyperdrive.getPoolConfig().positionDuration,
                int256(_variableRate)
            );
            hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

            // Bob should be able to redeem all of his withdrawal shares for
            // approximately the LP share price.
            uint256 lpSharePrice = hyperdrive.getPoolInfo().lpSharePrice;
            uint256 withdrawalSharesRedeemed;
            (
                vaultSharesProceeds,
                withdrawalSharesRedeemed
            ) = redeemWithdrawalShares(bob, withdrawalShares, false);
            uint256 baseProceeds = hyperdrive.convertToBase(
                vaultSharesProceeds
            );
            assertEq(withdrawalSharesRedeemed, withdrawalShares);

            // Bob should receive base approximately equal in value to his present
            // value.
            assertApproxEqAbs(
                baseProceeds,
                withdrawalShares.mulDown(lpSharePrice),
                config.roundTripLpWithdrawalSharesWithSharesTolerance
            );
        }
        // Otherwise we withdraw with base.
        else {
            // Bob removes his liquidity with base as the target asset.
            (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
                bob,
                lpShares
            );
            assertGt(withdrawalShares, 0);

            // The term passes and interest accrues.
            if (config.shouldAccrueInterest) {
                _variableRate = _variableRate.normalizeToRange(0, 2.5e18);
            } else {
                _variableRate = 0;
            }
            advanceTime(
                hyperdrive.getPoolConfig().positionDuration,
                int256(_variableRate)
            );
            hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

            // Bob should be able to redeem all of his withdrawal shares for
            // approximately the LP share price.
            uint256 lpSharePrice = hyperdrive.getPoolInfo().lpSharePrice;
            uint256 withdrawalSharesRedeemed;
            (baseProceeds, withdrawalSharesRedeemed) = redeemWithdrawalShares(
                bob,
                withdrawalShares
            );
            assertEq(withdrawalSharesRedeemed, withdrawalShares);

            // Bob should receive base approximately equal in value to his present
            // value.
            assertApproxEqAbs(
                baseProceeds,
                withdrawalShares.mulDown(lpSharePrice),
                config.roundTripLpWithdrawalSharesWithBaseTolerance
            );
        }
    }

    /// Longs ///

    /// @dev A test to make sure that ETH is handled correctly when longs are
    ///      opened. Instances that accept ETH should give users refunds when
    ///      they submit too much ETH, and instances that don't accept ETH
    ///      should revert.
    function test_open_long_with_eth() external {
        vm.startPrank(bob);

        if (isBaseETH && config.enableBaseDeposits) {
            // Ensure that Bob receives a refund on the excess ETH that he sent
            // when opening a long with "asBase" set to true.
            uint256 ethBalanceBefore = address(bob).balance;
            hyperdrive.openLong{ value: 2e18 }(
                1e18,
                0,
                0,
                IHyperdrive.Options({
                    destination: bob,
                    asBase: true,
                    extraData: new bytes(0)
                })
            );
            assertEq(address(bob).balance, ethBalanceBefore - 1e18);

            // Ensure that Bob receives a  refund when he opens a long with "asBase"
            // set to false and sends ether to the contract.
            ethBalanceBefore = address(bob).balance;
            hyperdrive.openLong{ value: 0.5e18 }(
                1e18,
                0,
                0,
                IHyperdrive.Options({
                    destination: bob,
                    asBase: false,
                    extraData: new bytes(0)
                })
            );
            assertEq(address(bob).balance, ethBalanceBefore);
        } else {
            // Ensure that sending ETH to `openLong` fails with `asBase` as true.
            vm.expectRevert(IHyperdrive.NotPayable.selector);
            hyperdrive.openLong{ value: 2e18 }(
                1e18,
                0,
                0,
                IHyperdrive.Options({
                    destination: bob,
                    asBase: true,
                    extraData: new bytes(0)
                })
            );

            // Ensure that sending ETH to `openLong` fails with `asBase` as false.
            vm.expectRevert(IHyperdrive.NotPayable.selector);
            hyperdrive.openLong{ value: 0.5e18 }(
                1e18,
                0,
                0,
                IHyperdrive.Options({
                    destination: bob,
                    asBase: false,
                    extraData: new bytes(0)
                })
            );
        }
    }

    /// @dev Fuzz test to ensure deposit accounting is correct when opening
    ///      longs with the share token. This test case is expected to fail if
    ///      share deposits are not supported.
    /// @param basePaid Amount in terms of base to open a long.
    function test_open_long_with_shares(uint256 basePaid) external {
        // Early termination if share deposits are not supported.
        if (!config.enableShareDeposits) {
            return;
        }

        // Get balance information before opening a long.
        (
            uint256 totalBaseSupplyBefore,
            uint256 totalShareSupplyBefore
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

        // Bob opens the long. We expect to fail with an UnsupportedToken error
        // if depositing with shares are not supported.
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
            totalShareSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalanceBefore
        );
    }

    /// @dev Fuzz test to ensure deposit accounting is correct when opening
    ///      longs with the base token. This test case is expected to fail if
    ///      base deposits are not supported.
    /// @param basePaid Amount in terms of base to open a long.
    function test_open_long_with_base(uint256 basePaid) external {
        // Get balance information before opening a long.
        (
            uint256 totalBaseSupplyBefore,
            uint256 totalShareSupplyBefore
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

        // If base deposits aren't enabled, we verify that ETH can't be sent to
        // `openLong` and that `openLong` can't be called with `asBase = true`.
        vm.startPrank(bob);
        if (!config.enableBaseDeposits) {
            // Check the `NotPayable` route.
            vm.expectRevert(IHyperdrive.NotPayable.selector);
            hyperdrive.openLong{ value: basePaid }(
                basePaid,
                0,
                0,
                IHyperdrive.Options({
                    destination: bob,
                    asBase: true,
                    extraData: new bytes(0)
                })
            );

            // Check the `UnsupportedToken` route.
            vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
            hyperdrive.openLong(
                basePaid,
                0,
                0,
                IHyperdrive.Options({
                    destination: bob,
                    asBase: true,
                    extraData: new bytes(0)
                })
            );

            return;
        }

        // Bob opens a long by depositing the base token.
        if (!isBaseETH) {
            IERC20(hyperdrive.baseToken()).approve(
                address(hyperdrive),
                basePaid
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
            totalShareSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalanceBefore
        );
    }

    /// @dev Fuzz test to ensure withdrawal accounting is correct when closing
    ///      longs with the share token. This test case is expected to fail if
    ///      share withdraws are not supported.
    /// @param basePaid Amount in terms of base.
    /// @param variableRate Rate of interest accrual over the position duration.
    function test_close_long_with_shares(
        uint256 basePaid,
        int256 variableRate
    ) external virtual {
        // Early termination if share withdrawals are not supported.
        if (!config.enableShareWithdraws) {
            return;
        }

        // Get Bob's account balances before opening the long.
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);

        // Accrue interest for a term.
        if (config.shouldAccrueInterest) {
            advanceTime(
                hyperdrive.getPoolConfig().positionDuration,
                int256(FIXED_RATE)
            );
        } else {
            advanceTime(hyperdrive.getPoolConfig().positionDuration, 0);
        }

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

        // Bob opens a long with the share token.
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            convertToShares(basePaid),
            false
        );

        // The term passes and some interest accrues.
        if (config.shouldAccrueInterest) {
            variableRate = variableRate.normalizeToRange(0, 2.5e18);
        } else {
            variableRate = 0;
        }
        advanceTime(hyperdrive.getPoolConfig().positionDuration, variableRate);

        // Get some balance information before closing the long.
        (
            uint256 totalBaseSupplyBefore,
            uint256 totalShareSupplyBefore
        ) = getSupply();
        bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with shares as the target asset.
        uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
        uint256 baseProceeds = convertToBase(shareProceeds);

        // Ensure that Bob received approximately the bond amount but wasn't
        // overpaid.
        assertLe(
            baseProceeds,
            longAmount.mulDown(ONE - hyperdrive.getPoolConfig().fees.flat)
        );
        assertApproxEqAbs(
            baseProceeds,
            longAmount.mulDown(ONE - hyperdrive.getPoolConfig().fees.flat),
            config.closeLongWithSharesTolerance
        );

        // Ensure the withdrawal accounting is correct.
        verifyWithdrawal(
            bob,
            baseProceeds,
            false,
            totalBaseSupplyBefore,
            totalShareSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz test to ensure withdrawal accounting is correct when closing
    ///      longs with the base token. This test case is expected to fail if
    ///      base withdraws are not supported.
    /// @param basePaid Amount in terms of base.
    /// @param variableRate Rate of interest accrual over the position duration.
    function test_close_long_with_base(
        uint256 basePaid,
        int256 variableRate
    ) external {
        // Get Bob's account balances before opening the long.
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);

        // Accrue interest for a term.
        if (config.shouldAccrueInterest) {
            advanceTime(
                hyperdrive.getPoolConfig().positionDuration,
                int256(FIXED_RATE)
            );
        } else {
            advanceTime(hyperdrive.getPoolConfig().positionDuration, 0);
        }

        // Calculate the maximum amount of basePaid we can test. The limit is
        // either the maximum long that Hyperdrive can open or the amount of the
        // base token the trader has.
        uint256 maxLongAmount = HyperdriveUtils.calculateMaxLong(hyperdrive);

        // Open a long in either base or shares, depending on which asset is
        // supported.
        uint256 maturityTime;
        uint256 longAmount;
        if (config.enableBaseDeposits) {
            // We normalize the basePaid variable within a valid range the market
            // can support.
            uint256 maxBaseAmount = bobBalancesBefore.baseBalance;
            basePaid = basePaid.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                maxLongAmount > maxBaseAmount ? maxBaseAmount : maxLongAmount
            );

            // Bob opens a long with the base token.
            (maturityTime, longAmount) = openLong(bob, basePaid);
        } else {
            // We normalize the sharesPaid variable within a valid range the market
            // can support.
            uint256 maxSharesAmount = bobBalancesBefore.sharesBalance;
            basePaid = basePaid.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                maxLongAmount
            );

            // Bob opens a long with the share token.
            (maturityTime, longAmount) = openLong(
                bob,
                convertToShares(basePaid).min(maxSharesAmount),
                false
            );
        }

        // The term passes and some interest accrues.
        if (config.shouldAccrueInterest) {
            variableRate = variableRate.normalizeToRange(0, 2.5e18);
        } else {
            variableRate = 0;
        }
        advanceTime(hyperdrive.getPoolConfig().positionDuration, variableRate);

        // Get some balance information before closing the long.
        (
            uint256 totalBaseSupplyBefore,
            uint256 totalShareSupplyBefore
        ) = getSupply();
        bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes the long. We expect to fail if withdrawing with base is
        // not supported.
        vm.startPrank(bob);
        if (!config.enableBaseWithdraws) {
            vm.expectRevert(config.baseWithdrawError);
        }
        uint256 baseProceeds = hyperdrive.closeLong(
            maturityTime,
            longAmount,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Early termination if base withdraws are not supported.
        if (!config.enableBaseWithdraws) {
            return;
        }

        // Ensure Bob is credited the correct amount of bonds.
        assertLe(
            baseProceeds,
            longAmount.mulDown(ONE - hyperdrive.getPoolConfig().fees.flat)
        );
        assertApproxEqAbs(
            baseProceeds,
            longAmount.mulDown(ONE - hyperdrive.getPoolConfig().fees.flat),
            config.closeLongWithBaseTolerance
        );

        // Ensure the withdrawal accounting is correct.
        verifyWithdrawal(
            bob,
            baseProceeds,
            true,
            totalBaseSupplyBefore,
            totalShareSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz test that ensures that longs receive the correct payouts if
    ///      they open and close instantaneously when deposits and withdrawals
    ///      are made with base.
    /// @param _basePaid The fuzz parameter for the base paid.
    function test_round_trip_long_instantaneous_with_base(
        uint256 _basePaid
    ) external {
        // If base deposits aren't enabled, we skip the test.
        if (!config.enableBaseDeposits) {
            return;
        }

        // Bob opens a long with base.
        _basePaid = _basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxLong()
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, _basePaid);

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // If base withdrawals are supported, we withdraw with base.
        uint256 baseProceeds;
        if (config.enableBaseWithdraws) {
            // Bob closes his long with base as the target asset.
            baseProceeds = closeLong(bob, maturityTime, longAmount);

            // Bob should receive less base than he paid since no time as passed.
            assertLt(
                baseProceeds,
                _basePaid +
                    config.roundTripLongInstantaneousWithBaseUpperBoundTolerance
            );
            // NOTE: If the fees aren't zero, we can't make an equality comparison.
            if (hyperdrive.getPoolConfig().fees.curve == 0) {
                assertApproxEqAbs(
                    baseProceeds,
                    _basePaid,
                    config.roundTripLongInstantaneousWithBaseTolerance
                );
            }
        }
        // Otherwise we withdraw with vault shares.
        else {
            // Bob closes his long with vault shares as the target asset.
            uint256 vaultSharesProceeds = closeLong(
                bob,
                maturityTime,
                longAmount,
                false
            );
            baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

            // NOTE: We add a slight buffer since the fees are zero.
            //
            // Bob should receive less base than he paid since no time as passed.
            assertLt(
                vaultSharesProceeds,
                hyperdrive.convertToShares(_basePaid) +
                    config
                        .roundTripLongInstantaneousWithSharesUpperBoundTolerance
            );
            // NOTE: If the fees aren't zero, we can't make an equality comparison.
            if (hyperdrive.getPoolConfig().fees.curve == 0) {
                assertApproxEqAbs(
                    vaultSharesProceeds,
                    hyperdrive.convertToShares(_basePaid),
                    config.roundTripLongInstantaneousWithSharesTolerance
                );
            }
        }

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            config.enableBaseWithdraws,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz test that ensures that longs receive the correct payouts if
    ///      they open and close instantaneously when deposits and withdrawals
    ///      are made with vault shares.
    /// @param _vaultSharesPaid The fuzz parameter for the vault shares paid.
    function test_round_trip_long_instantaneous_with_shares(
        uint256 _vaultSharesPaid
    ) external {
        // If share deposits aren't enabled, we skip the test.
        if (!config.enableShareDeposits) {
            return;
        }

        // Bob opens a long with vault shares.
        _vaultSharesPaid = hyperdrive.convertToShares(
            _vaultSharesPaid.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                hyperdrive.calculateMaxLong()
            )
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            _vaultSharesPaid,
            false
        );

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // If vault share withdrawals are supported, we withdraw with vault
        // shares.
        uint256 baseProceeds;
        if (config.enableShareWithdraws) {
            // Bob closes his long with vault shares as the target asset.
            uint256 vaultSharesProceeds = closeLong(
                bob,
                maturityTime,
                longAmount,
                false
            );
            baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

            // Bob should receive less base than he paid since no time as passed.
            assertLt(
                vaultSharesProceeds,
                _vaultSharesPaid +
                    config
                        .roundTripLongInstantaneousWithSharesUpperBoundTolerance
            );
            // NOTE: If the fees aren't zero, we can't make an equality comparison.
            if (hyperdrive.getPoolConfig().fees.curve == 0) {
                assertApproxEqAbs(
                    vaultSharesProceeds,
                    _vaultSharesPaid,
                    config.roundTripLongInstantaneousWithSharesTolerance
                );
            }
        }
        // Otherwise we withdraw with base.
        else {
            // Bob closes his long with base as the target asset.
            baseProceeds = closeLong(bob, maturityTime, longAmount);

            // Bob should receive less base than he paid since no time as passed.
            assertLt(
                baseProceeds,
                hyperdrive.convertToBase(_vaultSharesPaid) +
                    config.roundTripLongInstantaneousWithBaseUpperBoundTolerance
            );
            // NOTE: If the fees aren't zero, we can't make an equality comparison.
            if (hyperdrive.getPoolConfig().fees.curve == 0) {
                assertApproxEqAbs(
                    baseProceeds,
                    hyperdrive.convertToBase(_vaultSharesPaid),
                    config.roundTripLongInstantaneousWithBaseTolerance
                );
            }
        }

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            !config.enableShareWithdraws,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz test that ensures that shorts receive the correct payouts at
    ///      maturity when deposits and withdrawals are made with base.
    /// @param _basePaid The fuzz parameter for the base paid.
    /// @param _variableRate The fuzz parameter for the variable rate.
    function test_round_trip_long_maturity_with_base(
        uint256 _basePaid,
        uint256 _variableRate
    ) external {
        // If base deposits aren't enabled, we skip the test.
        if (!config.enableBaseDeposits) {
            return;
        }

        // Bob opens a long with base.
        _basePaid = _basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxLong()
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, _basePaid);

        // Advance the time and accrue a large amount of interest.
        if (config.shouldAccrueInterest) {
            _variableRate = _variableRate.normalizeToRange(0, 1000e18);
        } else {
            _variableRate = 0;
        }
        advanceTime(POSITION_DURATION, int256(_variableRate));

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // If base withdrawals are supported, we withdraw with base.
        uint256 baseProceeds;
        if (config.enableBaseWithdraws) {
            // Bob closes his long with base as the target asset.
            baseProceeds = closeLong(bob, maturityTime, longAmount);

            // Bob should receive almost exactly his bond amount.
            assertLe(
                baseProceeds,
                longAmount.mulDown(ONE - hyperdrive.getPoolConfig().fees.flat) +
                    config.roundTripLongMaturityWithBaseUpperBoundTolerance
            );
            assertApproxEqAbs(
                baseProceeds,
                longAmount.mulDown(ONE - hyperdrive.getPoolConfig().fees.flat),
                config.roundTripLongMaturityWithBaseTolerance
            );
        }
        // Otherwise we withdraw with vault shares.
        else {
            // Bob closes his long with vault shares as the target asset.
            uint256 vaultSharesProceeds = closeLong(
                bob,
                maturityTime,
                longAmount,
                false
            );
            baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

            // Bob should receive almost exactly his bond amount.
            assertLe(
                baseProceeds,
                longAmount.mulDown(ONE - hyperdrive.getPoolConfig().fees.flat) +
                    config.roundTripLongMaturityWithSharesUpperBoundTolerance
            );
            assertApproxEqAbs(
                baseProceeds,
                longAmount.mulDown(ONE - hyperdrive.getPoolConfig().fees.flat),
                config.roundTripLongMaturityWithSharesTolerance
            );
        }

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            config.enableBaseWithdraws,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz test that ensures that shorts receive the correct payouts at
    ///      maturity when deposits and withdrawals are made with vault shares.
    /// @param _vaultSharesPaid The fuzz parameter for the vault shares paid.
    /// @param _variableRate The fuzz parameter for the variable rate.
    function test_round_trip_long_maturity_with_shares(
        uint256 _vaultSharesPaid,
        uint256 _variableRate
    ) external {
        // If share deposits aren't enabled, we skip the test.
        if (!config.enableShareDeposits) {
            return;
        }

        // Bob opens a long with vault shares.
        _vaultSharesPaid = hyperdrive.convertToShares(
            _vaultSharesPaid.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                hyperdrive.calculateMaxLong()
            )
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            _vaultSharesPaid,
            false
        );

        // Advance the time and accrue a large amount of interest.
        if (config.shouldAccrueInterest) {
            _variableRate = _variableRate.normalizeToRange(0, 1000e18);
        } else {
            _variableRate = 0;
        }
        advanceTime(
            hyperdrive.getPoolConfig().positionDuration,
            int256(_variableRate)
        );

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // If vault share withdrawals are supported, we withdraw with vault
        // shares.
        uint256 baseProceeds;
        if (config.enableShareWithdraws) {
            // Bob closes his long with vault shares as the target asset.
            uint256 vaultSharesProceeds = closeLong(
                bob,
                maturityTime,
                longAmount,
                false
            );
            baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

            // Bob should receive almost exactly his bond amount.
            assertLe(
                baseProceeds,
                longAmount.mulDown(ONE - hyperdrive.getPoolConfig().fees.flat) +
                    config.roundTripLongMaturityWithSharesUpperBoundTolerance
            );
            assertApproxEqAbs(
                baseProceeds,
                longAmount.mulDown(ONE - hyperdrive.getPoolConfig().fees.flat),
                config.roundTripLongMaturityWithSharesTolerance
            );
        }
        // Otherwise we withdraw with base.
        else {
            // Bob closes his long with base as the target asset.
            baseProceeds = closeLong(bob, maturityTime, longAmount);

            // Bob should receive almost exactly his bond amount.
            assertLe(
                baseProceeds,
                longAmount.mulDown(ONE - hyperdrive.getPoolConfig().fees.flat) +
                    config.roundTripLongMaturityWithBaseUpperBoundTolerance
            );
            assertApproxEqAbs(
                baseProceeds,
                longAmount.mulDown(ONE - hyperdrive.getPoolConfig().fees.flat),
                config.roundTripLongMaturityWithBaseTolerance
            );
        }

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            !config.enableShareWithdraws,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// Shorts ///

    /// @dev A test to make sure that ETH is handled correctly when shorts are
    ///      opened. Instances that accept ETH should give users refunds when
    ///      they submit too much ETH, and instances that don't accept ETH
    ///      should revert.
    function test_open_short_with_eth() external {
        vm.startPrank(bob);

        if (isBaseETH && config.enableBaseDeposits) {
            // Ensure that Bob receives a refund on the excess ETH that he sent
            // when opening a short with "asBase" set to true.
            uint256 ethBalanceBefore = address(bob).balance;
            (, uint256 basePaid) = hyperdrive.openShort{ value: 2e18 }(
                1e18,
                1e18,
                0,
                IHyperdrive.Options({
                    destination: bob,
                    asBase: true,
                    extraData: new bytes(0)
                })
            );
            assertEq(address(bob).balance, ethBalanceBefore - basePaid);

            // Ensure that Bob receives a refund when he opens a short with "asBase"
            // set to false and sends ether to the contract.
            ethBalanceBefore = address(bob).balance;
            hyperdrive.openShort{ value: 0.5e18 }(
                1e18,
                1e18,
                0,
                IHyperdrive.Options({
                    destination: bob,
                    asBase: false,
                    extraData: new bytes(0)
                })
            );
            assertEq(address(bob).balance, ethBalanceBefore);
        } else {
            // Ensure that sending ETH to `openShort` fails with `asBase` as true.
            vm.expectRevert(IHyperdrive.NotPayable.selector);
            hyperdrive.openShort{ value: 2e18 }(
                1e18,
                1e18,
                0,
                IHyperdrive.Options({
                    destination: bob,
                    asBase: true,
                    extraData: new bytes(0)
                })
            );

            // Ensure that sending ETH to `openShort` fails with `asBase` as false.
            vm.expectRevert(IHyperdrive.NotPayable.selector);
            hyperdrive.openShort{ value: 0.5e18 }(
                1e18,
                1e18,
                0,
                IHyperdrive.Options({
                    destination: bob,
                    asBase: false,
                    extraData: new bytes(0)
                })
            );
        }
    }

    /// @dev Fuzz test to ensure deposit accounting is correct when opening shorts
    ///      with the base token. This test case is expected to fail if base deposits
    ///      are not supported.
    /// @param shortAmount Amount of bonds to short.
    function test_open_short_with_base(uint256 shortAmount) external {
        // Get some balance information before opening a short.
        (
            uint256 totalBaseSupplyBefore,
            uint256 totalShareSupplyBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // We normalize the short amount within a valid range the market can support.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
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
        } else if (!isBaseETH) {
            IERC20(hyperdrive.baseToken()).approve(
                address(hyperdrive),
                shortAmount
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

        // Early termination if base deposits are not supported.
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
            totalShareSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz test to ensure deposit accounting is correct when opening
    ///      shorts with the share token. This test case is expected to fail if
    ///      base deposits are not supported.
    /// @param shortAmount Amount of bonds to short.
    function test_open_short_with_shares(uint256 shortAmount) external {
        // Early termination if base deposits are not supported.
        if (!config.enableShareDeposits) {
            return;
        }

        // Get some balance information before opening a short.
        (
            uint256 totalBaseSupplyBefore,
            uint256 totalShareSupplyBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // We normalize the short amount within a valid range the market can support.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );

        // Bob opens a short by depositing shares.
        // We expect the openShort to fail with an UnsupportedToken error
        // if depositing with shares are not supported.
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
            totalShareSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz test to ensure withdrawal accounting is correct when closing shorts
    ///      with the base token. This test case is expected to fail if base withdraws
    ///      are not supported.
    /// @param shortAmount Amount of bonds to short.
    function test_close_short_with_base(
        uint256 shortAmount,
        int256 variableRate
    ) external virtual {
        // Accrue interest for a term.
        if (config.shouldAccrueInterest) {
            advanceTime(
                hyperdrive.getPoolConfig().positionDuration,
                int256(FIXED_RATE)
            );
        } else {
            advanceTime(hyperdrive.getPoolConfig().positionDuration, 0);
        }

        // Bob opens a short with the base token if base deposits are supported
        // and the shares token if they aren't.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        (uint256 maturityTime, ) = openShort(
            bob,
            shortAmount,
            config.enableBaseDeposits
        );

        // The term passes and interest accrues.
        uint256 startingVaultSharePrice = hyperdrive
            .getPoolInfo()
            .vaultSharePrice;
        if (config.shouldAccrueInterest) {
            variableRate = variableRate.normalizeToRange(0.01e18, 2.5e18);
        } else {
            variableRate = 0;
        }
        advanceTime(hyperdrive.getPoolConfig().positionDuration, variableRate);

        // Get some balance information before closing the long.
        (
            uint256 totalBaseSupplyBefore,
            uint256 totalShareSupplyBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );
        // Bob closes his short with shares as the target asset. Bob's proceeds
        // should be the variable interest that accrued on the shorted bonds
        vm.startPrank(bob);
        uint256 expectedBaseProceeds = shortAmount.mulDivDown(
            hyperdrive.getPoolInfo().vaultSharePrice - startingVaultSharePrice,
            startingVaultSharePrice
        );
        if (!config.enableBaseWithdraws && variableRate > 0) {
            vm.expectRevert(config.baseWithdrawError);
        }
        uint256 baseProceeds = hyperdrive.closeShort(
            maturityTime,
            shortAmount,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Early termination if share withdraws are not supported.
        if (!config.enableBaseWithdraws) {
            return;
        }

        // Convert proceeds to the base token and ensure the proper about of
        // interest was credited to Bob.
        assertLe(baseProceeds, expectedBaseProceeds + 10);
        assertApproxEqAbs(baseProceeds, expectedBaseProceeds, 100);

        // Ensure the withdrawal accounting is correct.
        verifyWithdrawal(
            bob,
            baseProceeds,
            true,
            totalBaseSupplyBefore,
            totalShareSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz test to ensure withdrawal accounting is correct when closing shorts
    ///      with the share token. This test case is expected to fail if share withdraws
    ///      are not supported.
    function test_close_short_with_shares(
        uint256 shortAmount,
        int256 variableRate
    ) external virtual {
        // Early termination if share withdrawals are not supported.
        if (!config.enableShareWithdraws) {
            return;
        }

        // Accrue interest for a term.
        if (config.shouldAccrueInterest) {
            advanceTime(
                hyperdrive.getPoolConfig().positionDuration,
                int256(FIXED_RATE)
            );
        } else {
            advanceTime(hyperdrive.getPoolConfig().positionDuration, 0);
        }

        // Bob opens a short with the share token.
        shortAmount = shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        (uint256 maturityTime, ) = openShort(bob, shortAmount, false);

        // The term passes and interest accrues.
        uint256 startingVaultSharePrice = hyperdrive
            .getPoolInfo()
            .vaultSharePrice;
        if (config.shouldAccrueInterest) {
            variableRate = variableRate.normalizeToRange(0, 2.5e18);
        } else {
            variableRate = 0;
        }
        advanceTime(hyperdrive.getPoolConfig().positionDuration, variableRate);

        // Get some balance information before closing the long.
        (
            uint256 totalBaseSupplyBefore,
            uint256 totalShareSupplyBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );
        // Bob closes his short with shares as the target asset. Bob's proceeds
        // should be the variable interest that accrued on the shorted bonds.
        uint256 expectedBaseProceeds = shortAmount.mulDivDown(
            hyperdrive.getPoolInfo().vaultSharePrice - startingVaultSharePrice,
            startingVaultSharePrice
        );
        if (!config.enableShareWithdraws) {
            vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        }
        uint256 shareProceeds = closeShort(
            bob,
            maturityTime,
            shortAmount,
            false
        );

        // Convert proceeds to the base token and ensure the proper about of
        // interest was credited to Bob.
        uint256 baseProceeds = convertToBase(shareProceeds);
        assertLe(baseProceeds, expectedBaseProceeds + 10);
        assertApproxEqAbs(
            baseProceeds,
            expectedBaseProceeds,
            config.closeShortWithSharesTolerance
        );

        // Ensure the withdrawal accounting is correct.
        verifyWithdrawal(
            bob,
            baseProceeds,
            false,
            totalBaseSupplyBefore,
            totalShareSupplyBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz test that ensures that shorts receive the correct payouts if
    ///      they open and close instantaneously when deposits and withdrawals
    ///      are made with base.
    /// @param _shortAmount The fuzz parameter for the short amount.
    function test_round_trip_short_instantaneous_with_base(
        uint256 _shortAmount
    ) external {
        // If base deposits aren't enabled, we skip the test.
        if (!config.enableBaseDeposits) {
            return;
        }

        // Bob opens a short with base.
        _shortAmount = _shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, _shortAmount);

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // If base withdrawals are supported, we withdraw with base.
        uint256 baseProceeds;
        if (config.enableBaseWithdraws) {
            // Bob closes his long with base as the target asset.
            baseProceeds = closeShort(bob, maturityTime, _shortAmount);

            // Bob should receive approximately as much base as he paid since no
            // time as passed and the fees are zero.
            assertLt(
                baseProceeds,
                basePaid +
                    config
                        .roundTripShortInstantaneousWithBaseUpperBoundTolerance
            );
            // NOTE: If the fees aren't zero, we can't make an equality comparison.
            if (hyperdrive.getPoolConfig().fees.curve == 0) {
                assertApproxEqAbs(
                    baseProceeds,
                    basePaid,
                    config.roundTripShortInstantaneousWithBaseTolerance
                );
            }
        }
        // Otherwise we withdraw with vault shares.
        else {
            // Bob closes his long with vault shares as the target asset.
            uint256 vaultSharesProceeds = closeShort(
                bob,
                maturityTime,
                _shortAmount,
                false
            );
            baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

            // Bob should receive approximately as many vault shares as he paid
            // since no time as passed and the fees are zero.
            assertLt(
                vaultSharesProceeds,
                hyperdrive.convertToShares(basePaid) +
                    config
                        .roundTripShortInstantaneousWithSharesUpperBoundTolerance
            );
            // NOTE: If the fees aren't zero, we can't make an equality comparison.
            if (hyperdrive.getPoolConfig().fees.curve == 0) {
                assertApproxEqAbs(
                    vaultSharesProceeds,
                    hyperdrive.convertToShares(basePaid),
                    config.roundTripShortInstantaneousWithSharesTolerance
                );
            }
        }

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            config.enableBaseWithdraws,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz test that ensures that shorts receive the correct payouts if
    ///      they open and close instantaneously when deposits and withdrawals
    ///      are made with vault shares.
    /// @param _shortAmount The fuzz parameter for the short amount.
    function test_round_trip_short_instantaneous_with_shares(
        uint256 _shortAmount
    ) external {
        // If share deposits aren't enabled, we skip the test.
        if (!config.enableShareDeposits) {
            return;
        }

        // Bob opens a short with vault shares.
        _shortAmount = _shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        (uint256 maturityTime, uint256 vaultSharesPaid) = openShort(
            bob,
            _shortAmount,
            false
        );

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // If vault share withdrawals are supported, we withdraw with vault
        // shares.
        uint256 baseProceeds;
        if (config.enableShareWithdraws) {
            // Bob closes his long with vault shares as the target asset.
            uint256 vaultSharesProceeds = closeShort(
                bob,
                maturityTime,
                _shortAmount,
                false
            );
            baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

            // Bob should receive approximately as many vault shares as he paid
            // since no time as passed and the fees are zero.
            assertLt(
                vaultSharesProceeds,
                vaultSharesPaid +
                    config
                        .roundTripShortInstantaneousWithSharesUpperBoundTolerance
            );
            // NOTE: If the fees aren't zero, we can't make an equality comparison.
            if (hyperdrive.getPoolConfig().fees.curve == 0) {
                assertApproxEqAbs(
                    vaultSharesProceeds,
                    vaultSharesPaid,
                    config.roundTripShortInstantaneousWithSharesTolerance
                );
            }
        }
        // Otherwise we withdraw with base.
        else {
            // Bob closes his long with base as the target asset.
            baseProceeds = closeShort(bob, maturityTime, _shortAmount);

            // Bob should receive approximately as much base as he paid since no
            // time as passed and the fees are zero.
            assertLt(
                baseProceeds,
                hyperdrive.convertToBase(vaultSharesPaid) +
                    config
                        .roundTripShortInstantaneousWithBaseUpperBoundTolerance
            );
            // NOTE: If the fees aren't zero, we can't make an equality comparison.
            if (hyperdrive.getPoolConfig().fees.curve == 0) {
                assertApproxEqAbs(
                    baseProceeds,
                    hyperdrive.convertToBase(vaultSharesPaid),
                    config.roundTripShortInstantaneousWithBaseTolerance
                );
            }
        }

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            !config.enableShareWithdraws,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz test that ensures that shorts receive the correct payouts at
    ///      maturity when deposits and withdrawals are made with base.
    /// @param _shortAmount The fuzz parameter for the short amount.
    /// @param _variableRate The fuzz parameter for the variable rate.
    function test_round_trip_short_maturity_with_base(
        uint256 _shortAmount,
        uint256 _variableRate
    ) external {
        // If base deposits aren't enabled, we skip the test.
        if (!config.enableBaseDeposits) {
            return;
        }

        // Bob opens a short with base.
        _shortAmount = _shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        (uint256 maturityTime, ) = openShort(bob, _shortAmount);

        // The term passes and some interest accrues.
        if (config.shouldAccrueInterest) {
            _variableRate = _variableRate.normalizeToRange(0, 2.5e18);
        } else {
            _variableRate = 0;
        }
        advanceTime(
            hyperdrive.getPoolConfig().positionDuration,
            int256(_variableRate)
        );

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // If base withdrawals are supported, we withdraw with base.
        uint256 baseProceeds;
        if (config.enableBaseWithdraws) {
            // Bob closes his long with base as the target asset.
            baseProceeds = closeShort(bob, maturityTime, _shortAmount);

            // Bob should receive almost exactly the interest that accrued on the
            // bonds that were shorted.
            assertApproxEqAbs(
                baseProceeds,
                _shortAmount.mulDown(_variableRate),
                config.roundTripShortMaturityWithBaseTolerance
            );
        }
        // Otherwise we withdraw with vault shares.
        else {
            // Bob closes his long with vault shares as the target asset.
            uint256 vaultSharesProceeds = closeShort(
                bob,
                maturityTime,
                _shortAmount,
                false
            );
            baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

            // Bob should receive almost exactly the interest that accrued on the
            // bonds that were shorted.
            assertApproxEqAbs(
                baseProceeds,
                _shortAmount.mulDown(_variableRate),
                config.roundTripShortMaturityWithSharesTolerance
            );
        }

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            config.enableBaseWithdraws,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// @dev Fuzz test that ensures that shorts receive the correct payouts at
    ///      maturity when deposits and withdrawals are made with vault shares.
    /// @param _shortAmount The fuzz parameter for the short amount.
    /// @param _variableRate The fuzz parameter for the variable rate.
    function test_round_trip_short_maturity_with_shares(
        uint256 _shortAmount,
        int256 _variableRate
    ) external {
        // If share deposits aren't enabled, we skip the test.
        if (!config.enableShareDeposits) {
            return;
        }

        // Bob opens a short with vault shares.
        _shortAmount = _shortAmount.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        (uint256 maturityTime, ) = openShort(bob, _shortAmount, false);

        // The term passes and some interest accrues.
        if (config.shouldAccrueInterest) {
            _variableRate = _variableRate.normalizeToRange(0, 2.5e18);
        } else {
            _variableRate = 0;
        }
        advanceTime(hyperdrive.getPoolConfig().positionDuration, _variableRate);

        // Get some balance information before the withdrawal.
        (
            uint256 totalSupplyAssetsBefore,
            uint256 totalSupplySharesBefore
        ) = getSupply();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // If vault share withdrawals are supported, we withdraw with vault
        // shares.
        uint256 baseProceeds;
        uint256 interest;
        {
            (, int256 interest_) = _shortAmount.calculateInterest(
                _variableRate,
                hyperdrive.getPoolConfig().positionDuration
            );
            interest = interest_.toUint256();
        }
        if (config.enableShareWithdraws) {
            // Bob closes his long with vault shares as the target asset.
            uint256 vaultSharesProceeds = closeShort(
                bob,
                maturityTime,
                _shortAmount,
                false
            );
            baseProceeds = hyperdrive.convertToBase(vaultSharesProceeds);

            // Bob should receive almost exactly the interest that accrued on the
            // bonds that were shorted.
            assertApproxEqAbs(
                baseProceeds,
                interest,
                config.roundTripShortMaturityWithSharesTolerance
            );
        }
        // Otherwise we withdraw with base.
        else {
            // Bob closes his long with base as the target asset.
            baseProceeds = closeShort(bob, maturityTime, _shortAmount);

            // Bob should receive almost exactly the interest that accrued on the
            // bonds that were shorted.
            assertApproxEqAbs(
                baseProceeds,
                interest,
                config.roundTripShortMaturityWithBaseTolerance
            );
        }

        // Ensure that the withdrawal was processed as expected.
        verifyWithdrawal(
            bob,
            baseProceeds,
            !config.enableShareWithdraws,
            totalSupplyAssetsBefore,
            totalSupplySharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /// Sweep ///

    function test_sweep_failure_directSweep() external {
        // Return early if the vault shares token is zero.
        address vaultSharesToken = hyperdrive.vaultSharesToken();
        if (vaultSharesToken == address(0)) {
            return;
        }

        // Fails to sweep the vault shares token.
        vm.startPrank(factory.sweepCollector());
        vm.expectRevert(IHyperdrive.SweepFailed.selector);
        hyperdrive.sweep(IERC20(vaultSharesToken));
    }

    function test_sweep_success() external {
        vm.startPrank(factory.sweepCollector());

        // Create a sweepable ERC20Mintable and send some tokens to Hyperdrive.
        ERC20Mintable sweepable = new ERC20Mintable(
            "Sweepable",
            "SWEEP",
            18,
            address(0),
            false,
            type(uint256).max
        );
        sweepable.mint(address(hyperdrive), 10e18);

        // Successfully sweep a token that isn't the vault shares token.
        hyperdrive.sweep(IERC20(address(sweepable)));
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

/// @author DELV
/// @title NonPayableDeployer
/// @dev A testing contract that will call `deployAndInitialize` on the
///      specified hyperdrive factory and will revert if ether is refunded.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract NonPayableDeployer {
    function deployTarget(
        HyperdriveFactory _factory,
        bytes32 _deploymentId,
        address _deployerCoordinator,
        IHyperdrive.PoolDeployConfig memory _config,
        bytes memory _extraData,
        uint256 _fixedAPR,
        uint256 _timeStretchAPR,
        uint256 _targetIndex,
        bytes32 _salt
    ) external {
        _factory.deployTarget(
            _deploymentId,
            _deployerCoordinator,
            _config,
            _extraData,
            _fixedAPR,
            _timeStretchAPR,
            _targetIndex,
            _salt
        );
    }

    function deployAndInitialize(
        HyperdriveFactory _factory,
        bytes32 _deploymentId,
        string memory __name,
        address _deployerCoordinator,
        IHyperdrive.PoolDeployConfig memory _config,
        bytes memory _extraData,
        uint256 _contribution,
        uint256 _fixedAPR,
        uint256 _timeStretchAPR,
        IHyperdrive.Options memory _options,
        bytes32 _salt
    ) external payable {
        _factory.deployAndInitialize{ value: msg.value }(
            _deploymentId,
            _deployerCoordinator,
            __name,
            _config,
            _extraData,
            _contribution,
            _fixedAPR,
            _timeStretchAPR,
            _options,
            _salt
        );
    }
}
