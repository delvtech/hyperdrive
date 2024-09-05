// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { VmSafe } from "forge-std/Vm.sol";
import { HyperdriveFactory } from "../../contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../contracts/src/interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveCheckpointRewarder } from "../../contracts/src/interfaces/IHyperdriveCheckpointRewarder.sol";
import { IHyperdriveEvents } from "../../contracts/src/interfaces/IHyperdriveEvents.sol";
import { IHyperdriveFactory } from "../../contracts/src/interfaces/IHyperdriveFactory.sol";
import { IHyperdriveGovernedRegistry } from "../../contracts/src/interfaces/IHyperdriveGovernedRegistry.sol";
import { AssetId } from "../../contracts/src/libraries/AssetId.sol";
import { ETH } from "../../contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../contracts/src/libraries/HyperdriveMath.sol";
import { LPMath } from "../../contracts/src/libraries/LPMath.sol";
import { YieldSpaceMath } from "../../contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveRegistry } from "../../contracts/src/registry/HyperdriveRegistry.sol";
import { ERC20ForwarderFactory } from "../../contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "../../contracts/test/ERC20Mintable.sol";
import { MockHyperdrive, MockHyperdriveAdminController } from "../../contracts/test/MockHyperdrive.sol";
import { BaseTest } from "./BaseTest.sol";
import { HyperdriveUtils } from "./HyperdriveUtils.sol";
import { Lib } from "./Lib.sol";

contract HyperdriveTest is IHyperdriveEvents, BaseTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    ERC20ForwarderFactory internal forwarderFactory;
    ERC20Mintable internal baseToken;
    IHyperdriveGovernedRegistry internal registry;
    IHyperdriveCheckpointRewarder internal checkpointRewarder =
        IHyperdriveCheckpointRewarder(address(0));
    IHyperdrive internal hyperdrive;
    IHyperdriveAdminController internal adminController;

    uint256 internal constant INITIAL_SHARE_PRICE = ONE;
    uint256 internal constant MINIMUM_SHARE_RESERVES = ONE;
    uint256 internal constant MINIMUM_TRANSACTION_AMOUNT = 0.001e18;
    uint256 internal constant CIRCUIT_BREAKER_DELTA = 2e18;
    uint256 internal constant CHECKPOINT_DURATION = 1 days;
    uint256 internal constant POSITION_DURATION = 365 days;

    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(alice);

        // Instantiate the base token.
        baseToken = new ERC20Mintable(
            "Base",
            "BASE",
            18,
            address(0),
            false,
            type(uint256).max
        );

        // Instantiate the forwarder factory.
        forwarderFactory = new ERC20ForwarderFactory("ForwarderFactory");

        // Instantiate the Hyperdrive registry.
        registry = new HyperdriveRegistry();
        registry.initialize("HyperdriveRegistry", registrar);

        // Instantiate the Hyperdrive factory.
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        address[] memory pausers = new address[](1);
        pausers[0] = pauser;
        adminController = IHyperdriveAdminController(
            address(
                new MockHyperdriveAdminController(
                    config.governance,
                    config.feeCollector,
                    config.sweepCollector,
                    config.checkpointRewarder,
                    pausers
                )
            )
        );

        // Instantiate Hyperdrive.
        deploy(alice, config);
        vm.stopPrank();
        vm.startPrank(governance);
        hyperdrive.setPauser(pauser, true);

        // If this isn't a forked environment, advance time so that Hyperdrive
        // can look back more than a position duration. We assume that fork
        // tests are using a sufficiently recent block that this won't be an
        // issue.
        if (!isForked) {
            vm.warp(POSITION_DURATION * 3);
        }
    }

    function deploy(
        address deployer,
        IHyperdrive.PoolConfig memory _config
    ) internal {
        // Deploy the Hyperdrive instance.
        vm.stopPrank();
        vm.startPrank(deployer);
        hyperdrive = IHyperdrive(
            address(new MockHyperdrive(_config, adminController))
        );

        // Update the factory's configuration to match the pool config.
        MockHyperdriveAdminController(address(adminController))
            .updateHyperdriveGovernance(_config.governance);
        MockHyperdriveAdminController(address(adminController))
            .updateFeeCollector(_config.feeCollector);
        MockHyperdriveAdminController(address(adminController))
            .updateSweepCollector(_config.feeCollector);
        MockHyperdriveAdminController(address(adminController))
            .updateCheckpointRewarder(_config.checkpointRewarder);

        // Register the new instance.
        vm.stopPrank();
        vm.startPrank(registrar);
        address[] memory instances = new address[](1);
        uint128[] memory data = new uint128[](1);
        address[] memory factories = new address[](1);
        instances[0] = address(hyperdrive);
        data[0] = 1;
        factories[0] = address(0);
        registry.setInstanceInfo(instances, data, factories);
    }

    function deploy(
        address deployer,
        uint256 apr,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceLPFee,
        uint256 governanceZombieFee
    ) internal {
        // Deploy the Hyperdrive instance.
        deploy(
            deployer,
            apr,
            INITIAL_SHARE_PRICE,
            curveFee,
            flatFee,
            governanceLPFee,
            governanceZombieFee
        );
    }

    function deploy(
        address deployer,
        uint256 apr,
        uint256 initialVaultSharePrice,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceLPFee,
        uint256 governanceZombieFee
    ) internal {
        // Deploy the Hyperdrive instance.
        IHyperdrive.PoolConfig memory config = testConfig(
            apr,
            POSITION_DURATION
        );
        config.initialVaultSharePrice = initialVaultSharePrice;
        config.fees.curve = curveFee;
        config.fees.flat = flatFee;
        config.fees.governanceLP = governanceLPFee;
        config.fees.governanceZombie = governanceZombieFee;
        deploy(deployer, config);
    }

    function testConfig(
        uint256 fixedRate,
        uint256 positionDuration
    ) internal view returns (IHyperdrive.PoolConfig memory _config) {
        IHyperdrive.PoolDeployConfig memory _deployConfig = testDeployConfig(
            fixedRate,
            positionDuration
        );
        _config.baseToken = _deployConfig.baseToken;
        _config.vaultSharesToken = _deployConfig.vaultSharesToken;
        _config.linkerFactory = _deployConfig.linkerFactory;
        _config.linkerCodeHash = _deployConfig.linkerCodeHash;
        _config.minimumShareReserves = _deployConfig.minimumShareReserves;
        _config.minimumTransactionAmount = _deployConfig
            .minimumTransactionAmount;
        _config.circuitBreakerDelta = _deployConfig.circuitBreakerDelta;
        _config.positionDuration = _deployConfig.positionDuration;
        _config.checkpointDuration = _deployConfig.checkpointDuration;
        _config.timeStretch = _deployConfig.timeStretch;
        _config.governance = _deployConfig.governance;
        _config.feeCollector = _deployConfig.feeCollector;
        _config.sweepCollector = _deployConfig.sweepCollector;
        _config.checkpointRewarder = _deployConfig.checkpointRewarder;
        _config.fees = _deployConfig.fees;
        _config.initialVaultSharePrice = ONE;
    }

    function testDeployConfig(
        uint256 fixedRate,
        uint256 positionDuration
    ) internal view returns (IHyperdrive.PoolDeployConfig memory) {
        IHyperdrive.Fees memory fees = IHyperdrive.Fees({
            curve: 0,
            flat: 0,
            governanceLP: 0,
            governanceZombie: 0
        });
        return
            IHyperdrive.PoolDeployConfig({
                baseToken: IERC20(address(baseToken)),
                // NOTE: This isn't used by MockHyperdrive.
                vaultSharesToken: IERC20(address(0)),
                linkerFactory: address(forwarderFactory),
                linkerCodeHash: forwarderFactory.ERC20LINK_HASH(),
                minimumShareReserves: MINIMUM_SHARE_RESERVES,
                minimumTransactionAmount: MINIMUM_TRANSACTION_AMOUNT,
                circuitBreakerDelta: CIRCUIT_BREAKER_DELTA,
                positionDuration: positionDuration,
                checkpointDuration: CHECKPOINT_DURATION,
                timeStretch: HyperdriveMath.calculateTimeStretch(
                    fixedRate,
                    positionDuration
                ),
                governance: governance,
                feeCollector: feeCollector,
                sweepCollector: sweepCollector,
                checkpointRewarder: address(checkpointRewarder),
                fees: fees
            });
    }

    /// Actions ///

    // Overrides for functions that initiate deposits.
    struct DepositOverrides {
        // A boolean flag specifying whether or not the underlying should be used.
        bool asBase;
        // The destination address.
        address destination;
        // The extra data to pass to the yield source.
        bytes extraData;
        // The amount of tokens the action should prepare to deposit. Note that
        // the actual deposit amount will still be specified by the action being
        // called; however, this is the amount that will be minted as a
        // convenience. In the case of ETH, this is the amount that will be
        // transferred into the YieldSource, which allows us to test ETH
        // reentrancy.
        uint256 depositAmount;
        // The minimum share price that will be accepted. It may not be used by
        // some actions.
        uint256 minSharePrice;
        // This is the slippage parameter that defines a lower bound on the
        // quantity being measured. It may not be used by some actions.
        uint256 minSlippage;
        // This is the slippage parameter that defines an upper bound on the
        // quantity being measured. It may not be used by some actions.
        uint256 maxSlippage;
    }

    // Overrides for functions that initiate withdrawals.
    struct WithdrawalOverrides {
        // A boolean flag specifying whether or not the underlying should be used.
        bool asBase;
        // The destination address.
        address destination;
        // The extra data to pass to the yield source.
        bytes extraData;
        // This is the slippage parameter that defines a lower bound on the
        // quantity being measured.
        uint256 minSlippage;
    }

    function initialize(
        address lp,
        uint256 apr,
        uint256 contribution,
        DepositOverrides memory overrides
    ) internal returns (uint256 lpShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Initialize the pool.
        if (
            address(hyperdrive.getPoolConfig().baseToken) == address(ETH) &&
            overrides.asBase
        ) {
            return
                hyperdrive.initialize{ value: overrides.depositAmount }(
                    contribution,
                    apr,
                    IHyperdrive.Options({
                        destination: lp,
                        asBase: overrides.asBase,
                        extraData: overrides.extraData
                    })
                );
        } else {
            baseToken.mint(overrides.depositAmount);
            baseToken.approve(address(hyperdrive), overrides.depositAmount);
            return
                hyperdrive.initialize(
                    contribution,
                    apr,
                    IHyperdrive.Options({
                        destination: overrides.destination,
                        asBase: overrides.asBase,
                        extraData: overrides.extraData
                    })
                );
        }
    }

    function initialize(
        address lp,
        uint256 apr,
        uint256 contribution
    ) internal returns (uint256 lpShares) {
        return
            initialize(
                lp,
                apr,
                contribution,
                DepositOverrides({
                    asBase: true,
                    destination: lp,
                    depositAmount: contribution,
                    minSharePrice: 0, // unused
                    minSlippage: 0, // unused
                    maxSlippage: type(uint256).max, // unused
                    extraData: new bytes(0) // unused
                })
            );
    }

    function initialize(
        address lp,
        uint256 apr,
        uint256 contribution,
        bool asBase
    ) internal returns (uint256 lpShares) {
        return
            initialize(
                lp,
                apr,
                contribution,
                DepositOverrides({
                    asBase: asBase,
                    destination: lp,
                    depositAmount: contribution,
                    minSharePrice: 0, // unused
                    minSlippage: 0, // unused
                    maxSlippage: type(uint256).max, // unused
                    extraData: new bytes(0) // unused
                })
            );
    }

    function addLiquidity(
        address lp,
        uint256 contribution,
        DepositOverrides memory overrides
    ) internal returns (uint256 lpShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Add liquidity to the pool.
        if (
            address(hyperdrive.getPoolConfig().baseToken) == address(ETH) &&
            overrides.asBase
        ) {
            return
                hyperdrive.addLiquidity{ value: overrides.depositAmount }(
                    contribution,
                    overrides.minSharePrice, // min lp share price
                    overrides.minSlippage, // min spot rate
                    overrides.maxSlippage, // max spot rate
                    IHyperdrive.Options({
                        destination: overrides.destination,
                        asBase: overrides.asBase,
                        extraData: overrides.extraData
                    })
                );
        } else {
            baseToken.mint(overrides.depositAmount);
            baseToken.approve(address(hyperdrive), overrides.depositAmount);
            return
                hyperdrive.addLiquidity(
                    contribution,
                    overrides.minSharePrice, // min lp share price
                    overrides.minSlippage, // min spot rate
                    overrides.maxSlippage, // max spot rate
                    IHyperdrive.Options({
                        destination: overrides.destination,
                        asBase: overrides.asBase,
                        extraData: overrides.extraData
                    })
                );
        }
    }

    function addLiquidity(
        address lp,
        uint256 contribution
    ) internal returns (uint256 lpShares) {
        return
            addLiquidity(
                lp,
                contribution,
                DepositOverrides({
                    asBase: true,
                    destination: lp,
                    depositAmount: contribution,
                    minSharePrice: 0, // unused
                    minSlippage: 0, // min spot rate of 0
                    maxSlippage: type(uint256).max, // max spot rate of uint256 max
                    extraData: new bytes(0) // unused
                })
            );
    }

    function addLiquidity(
        address lp,
        uint256 contribution,
        bool asBase
    ) internal returns (uint256 lpShares) {
        return
            addLiquidity(
                lp,
                contribution,
                DepositOverrides({
                    asBase: asBase,
                    destination: lp,
                    depositAmount: contribution,
                    minSharePrice: 0, // min lp share price of 0
                    minSlippage: 0, // min spot rate of 0
                    maxSlippage: type(uint256).max, // max spot rate of uint256 max
                    extraData: new bytes(0) // unused
                })
            );
    }

    function removeLiquidity(
        address lp,
        uint256 shares,
        WithdrawalOverrides memory overrides
    ) internal returns (uint256 baseProceeds, uint256 withdrawalShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Remove liquidity from the pool.
        return
            hyperdrive.removeLiquidity(
                shares,
                overrides.minSlippage, // min lp share price
                IHyperdrive.Options({
                    destination: overrides.destination,
                    asBase: overrides.asBase,
                    extraData: overrides.extraData
                })
            );
    }

    function removeLiquidity(
        address lp,
        uint256 shares
    ) internal returns (uint256 baseProceeds, uint256 withdrawalShares) {
        return
            removeLiquidity(
                lp,
                shares,
                WithdrawalOverrides({
                    asBase: true,
                    destination: lp,
                    minSlippage: 0, // min lp share price of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    function removeLiquidity(
        address lp,
        uint256 shares,
        bool asBase
    ) internal returns (uint256 baseProceeds, uint256 withdrawalShares) {
        return
            removeLiquidity(
                lp,
                shares,
                WithdrawalOverrides({
                    asBase: asBase,
                    destination: lp,
                    minSlippage: 0, // min base proceeds of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    function redeemWithdrawalShares(
        address lp,
        uint256 shares,
        WithdrawalOverrides memory overrides
    ) internal returns (uint256 baseProceeds, uint256 sharesRedeemed) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Redeem the withdrawal shares.
        return
            hyperdrive.redeemWithdrawalShares(
                shares,
                overrides.minSlippage, // min output per share
                IHyperdrive.Options({
                    destination: overrides.destination,
                    asBase: overrides.asBase,
                    extraData: overrides.extraData
                })
            );
    }

    function redeemWithdrawalShares(
        address lp,
        uint256 shares
    ) internal returns (uint256 baseProceeds, uint256 sharesRedeemed) {
        return
            redeemWithdrawalShares(
                lp,
                shares,
                WithdrawalOverrides({
                    asBase: true,
                    destination: lp,
                    minSlippage: 0, // min output per share of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    function redeemWithdrawalShares(
        address lp,
        uint256 shares,
        bool asBase
    ) internal returns (uint256 baseProceeds, uint256 sharesRedeemed) {
        return
            redeemWithdrawalShares(
                lp,
                shares,
                WithdrawalOverrides({
                    asBase: asBase,
                    destination: lp,
                    minSlippage: 0, // min output per share of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    function openLong(
        address trader,
        uint256 baseAmount,
        DepositOverrides memory overrides
    ) internal returns (uint256 maturityTime, uint256 bondProceeds) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the long.
        hyperdrive.getPoolConfig();
        if (
            address(hyperdrive.getPoolConfig().baseToken) == address(ETH) &&
            overrides.asBase
        ) {
            return
                hyperdrive.openLong{ value: overrides.depositAmount }(
                    baseAmount,
                    overrides.minSlippage, // min bond proceeds
                    overrides.minSharePrice, // min vault share price
                    IHyperdrive.Options({
                        destination: overrides.destination,
                        asBase: overrides.asBase,
                        extraData: overrides.extraData
                    })
                );
        } else {
            baseToken.mint(baseAmount);
            baseToken.approve(address(hyperdrive), baseAmount);
            return
                hyperdrive.openLong(
                    baseAmount,
                    overrides.minSlippage, // min bond proceeds
                    overrides.minSharePrice, // min vault share price
                    IHyperdrive.Options({
                        destination: overrides.destination,
                        asBase: overrides.asBase,
                        extraData: overrides.extraData
                    })
                );
        }
    }

    function openLong(
        address trader,
        uint256 baseAmount
    ) internal returns (uint256 maturityTime, uint256 bondAmount) {
        return
            openLong(
                trader,
                baseAmount,
                DepositOverrides({
                    asBase: true,
                    destination: trader,
                    depositAmount: baseAmount,
                    minSharePrice: 0, // min vault share price of 0
                    minSlippage: baseAmount, // min bond proceeds of baseAmount
                    maxSlippage: type(uint256).max, // unused
                    extraData: new bytes(0) // unused
                })
            );
    }

    function openLong(
        address trader,
        uint256 baseAmount,
        bool asBase
    ) internal returns (uint256 maturityTime, uint256 bondAmount) {
        return
            openLong(
                trader,
                baseAmount,
                DepositOverrides({
                    asBase: asBase,
                    destination: trader,
                    depositAmount: baseAmount,
                    minSharePrice: 0, // min vault share price of 0
                    minSlippage: baseAmount, // min bond proceeds of baseAmount
                    maxSlippage: type(uint256).max, // unused
                    extraData: new bytes(0) // unused
                })
            );
    }

    function closeLong(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount,
        WithdrawalOverrides memory overrides
    ) internal returns (uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Close the long.
        return
            hyperdrive.closeLong(
                maturityTime,
                bondAmount,
                overrides.minSlippage, // min base proceeds
                IHyperdrive.Options({
                    destination: overrides.destination,
                    asBase: overrides.asBase,
                    extraData: overrides.extraData
                })
            );
    }

    function closeLong(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount
    ) internal returns (uint256 baseAmount) {
        return
            closeLong(
                trader,
                maturityTime,
                bondAmount,
                WithdrawalOverrides({
                    destination: trader,
                    asBase: true,
                    minSlippage: 0, // min base proceeds of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    function closeLong(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount,
        bool asBase
    ) internal returns (uint256 baseAmount) {
        return
            closeLong(
                trader,
                maturityTime,
                bondAmount,
                WithdrawalOverrides({
                    asBase: asBase,
                    destination: trader,
                    minSlippage: 0, // min base proceeds of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    function openShort(
        address trader,
        uint256 bondAmount,
        DepositOverrides memory overrides
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the short.
        maturityTime = HyperdriveUtils.maturityTimeFromLatestCheckpoint(
            hyperdrive
        );
        if (
            address(hyperdrive.getPoolConfig().baseToken) == address(ETH) &&
            overrides.asBase
        ) {
            (maturityTime, baseAmount) = hyperdrive.openShort{
                value: overrides.depositAmount
            }(
                bondAmount,
                overrides.maxSlippage, // max base payment
                overrides.minSharePrice, // min vault share price
                IHyperdrive.Options({
                    destination: overrides.destination,
                    asBase: overrides.asBase,
                    extraData: overrides.extraData
                })
            );
        } else {
            baseToken.mint(overrides.depositAmount);
            baseToken.approve(address(hyperdrive), overrides.maxSlippage);
            (maturityTime, baseAmount) = hyperdrive.openShort(
                bondAmount,
                overrides.maxSlippage, // max base payment
                overrides.minSharePrice, // min vault share price
                IHyperdrive.Options({
                    destination: overrides.destination,
                    asBase: overrides.asBase,
                    extraData: overrides.extraData
                })
            );
            baseToken.burn(overrides.depositAmount - baseAmount);
        }

        return (maturityTime, baseAmount);
    }

    function openShort(
        address trader,
        uint256 bondAmount
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        return
            openShort(
                trader,
                bondAmount,
                DepositOverrides({
                    asBase: true,
                    destination: trader,
                    depositAmount: bondAmount,
                    minSharePrice: 0, // min vault share price of 0
                    minSlippage: 0, // unused
                    maxSlippage: bondAmount, // max base payment of bondAmount
                    extraData: new bytes(0) // unused
                })
            );
    }

    function openShort(
        address trader,
        uint256 bondAmount,
        bool asBase
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        return
            openShort(
                trader,
                bondAmount,
                DepositOverrides({
                    asBase: asBase,
                    destination: trader,
                    depositAmount: bondAmount,
                    minSharePrice: 0, // min vault share price of 0
                    minSlippage: 0, // unused
                    maxSlippage: bondAmount, // max base payment of bondAmount
                    extraData: new bytes(0) // unused
                })
            );
    }

    function closeShort(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount,
        WithdrawalOverrides memory overrides
    ) internal returns (uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Close the short.
        return
            hyperdrive.closeShort(
                maturityTime,
                bondAmount,
                overrides.minSlippage, // min base proceeds
                IHyperdrive.Options({
                    destination: overrides.destination,
                    asBase: overrides.asBase,
                    extraData: overrides.extraData
                })
            );
    }

    function closeShort(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount
    ) internal returns (uint256 baseAmount) {
        return
            closeShort(
                trader,
                maturityTime,
                bondAmount,
                WithdrawalOverrides({
                    asBase: true,
                    destination: trader,
                    minSlippage: 0, // min base proceeds of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    function closeShort(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount,
        bool asBase
    ) internal returns (uint256 baseAmount) {
        return
            closeShort(
                trader,
                maturityTime,
                bondAmount,
                WithdrawalOverrides({
                    asBase: asBase,
                    destination: trader,
                    minSlippage: 0, // min base proceeds of 0
                    extraData: new bytes(0) // unused
                })
            );
    }

    /// Utils ///

    function advanceTime(uint256 time, int256 variableRate) internal virtual {
        MockHyperdrive(address(hyperdrive)).accrue(time, variableRate);
        vm.warp(block.timestamp + time);
    }

    function advanceTimeWithCheckpoints(
        uint256 time,
        int256 variableRate
    ) internal virtual {
        uint256 startTimeElapsed = block.timestamp;
        // Note: if time % CHECKPOINT_DURATION != 0 then it ends up
        // advancing time to the next checkpoint.
        while (block.timestamp - startTimeElapsed < time) {
            advanceTime(CHECKPOINT_DURATION, variableRate);
            hyperdrive.checkpoint(
                HyperdriveUtils.latestCheckpoint(hyperdrive),
                0
            );
        }
    }

    function advanceTimeWithCheckpoints2(
        uint256 time,
        int256 variableRate
    ) internal virtual {
        if (time % CHECKPOINT_DURATION == 0) {
            advanceTimeWithCheckpoints(time, variableRate);
        } else if (time < CHECKPOINT_DURATION) {
            advanceTime(time, variableRate);
        } else {
            // time > CHECKPOINT_DURATION
            uint256 startTimeElapsed = block.timestamp;
            while (
                block.timestamp - startTimeElapsed + CHECKPOINT_DURATION < time
            ) {
                advanceTime(CHECKPOINT_DURATION, variableRate);
                hyperdrive.checkpoint(
                    HyperdriveUtils.latestCheckpoint(hyperdrive),
                    0
                );
            }
            advanceTime(time % CHECKPOINT_DURATION, variableRate);
        }
    }

    function pause(bool paused) internal {
        vm.startPrank(pauser);
        hyperdrive.pause(paused);
        vm.stopPrank();
    }

    function estimateLongProceeds(
        uint256 bondAmount,
        uint256 normalizedTimeRemaining,
        uint256 openVaultSharePrice,
        uint256 closeVaultSharePrice
    ) internal view returns (uint256) {
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory poolConfig = hyperdrive.getPoolConfig();
        (, , uint256 shareProceeds) = HyperdriveMath.calculateCloseLong(
            HyperdriveMath.calculateEffectiveShareReserves(
                poolInfo.shareReserves,
                poolInfo.shareAdjustment
            ),
            poolInfo.bondReserves,
            bondAmount,
            normalizedTimeRemaining,
            poolConfig.timeStretch,
            poolInfo.vaultSharePrice,
            poolConfig.initialVaultSharePrice
        );
        if (closeVaultSharePrice < openVaultSharePrice) {
            shareProceeds = shareProceeds.mulDivDown(
                closeVaultSharePrice,
                openVaultSharePrice
            );
        }
        return shareProceeds.mulDivDown(poolInfo.vaultSharePrice, 1e18);
    }

    function estimateShortProceeds(
        uint256 shortAmount,
        int256 variableRate,
        uint256 normalizedTimeRemaining,
        uint256 timeElapsed
    ) internal view returns (uint256) {
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory poolConfig = hyperdrive.getPoolConfig();

        (, , uint256 expectedSharePayment) = HyperdriveMath.calculateCloseShort(
            HyperdriveMath.calculateEffectiveShareReserves(
                poolInfo.shareReserves,
                poolInfo.shareAdjustment
            ),
            poolInfo.bondReserves,
            shortAmount,
            normalizedTimeRemaining,
            poolConfig.timeStretch,
            poolInfo.vaultSharePrice,
            poolConfig.initialVaultSharePrice
        );
        (, int256 expectedInterest) = HyperdriveUtils.calculateCompoundInterest(
            shortAmount,
            variableRate,
            timeElapsed
        );
        int256 delta = int256(shortAmount) -
            int256(poolInfo.vaultSharePrice.mulDown(expectedSharePayment));
        if (delta + expectedInterest > 0) {
            return uint256(delta + expectedInterest);
        } else {
            return 0;
        }
    }

    function calculateExpectedRemoveLiquidityProceeds(
        uint256 _lpShares
    ) internal view returns (uint256 baseProceeds, uint256 withdrawalShares) {
        // Apply the LP shares that will be removed to the withdrawal shares
        // outstanding and calculate the results of distributing excess idle.
        LPMath.DistributeExcessIdleParams memory params = hyperdrive
            .getDistributeExcessIdleParams();
        params.activeLpTotalSupply -= _lpShares;
        params.withdrawalSharesTotalSupply += _lpShares;
        (uint256 withdrawalSharesRedeemed, uint256 shareProceeds) = LPMath
            .calculateDistributeExcessIdle(params, 0);
        return (
            shareProceeds.mulDown(hyperdrive.getPoolInfo().vaultSharePrice),
            _lpShares - withdrawalSharesRedeemed
        );
    }

    /// Event Utils ///

    event Deployed(
        address indexed deployerCoordinator,
        address hyperdrive,
        string name,
        IHyperdrive.PoolDeployConfig config,
        bytes extraData
    );

    function verifyFactoryEvents(
        address deployerCoordinator,
        IHyperdrive _hyperdrive,
        address deployer,
        uint256 contribution,
        uint256 apr,
        bool asBase,
        uint256 minimumShareReserves,
        bytes memory expectedExtraData,
        uint256 tolerance
    ) internal {
        // Ensure that the correct `Deployed` and `Initialize` events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        // Verify that a single `Deployed` event was emitted.
        {
            VmSafe.Log[] memory filteredLogs = logs.filterLogs(
                Deployed.selector
            );
            assertEq(filteredLogs.length, 1);

            // Verify the event topics.
            assertEq(filteredLogs[0].topics[0], Deployed.selector);
            assertEq(
                uint256(filteredLogs[0].topics[1]),
                uint256(uint160(deployerCoordinator))
            );

            // Verify the event data.
            (
                address eventHyperdrive,
                string memory eventName,
                IHyperdrive.PoolDeployConfig memory eventConfig,
                bytes memory eventExtraData
            ) = abi.decode(
                    filteredLogs[0].data,
                    (address, string, IHyperdrive.PoolDeployConfig, bytes)
                );
            assertEq(eventHyperdrive, address(_hyperdrive));
            assertEq(eventName, _hyperdrive.name());

            IHyperdrive.PoolConfig memory poolConfig = _hyperdrive
                .getPoolConfig();

            assertEq(
                address(eventConfig.baseToken),
                address(poolConfig.baseToken)
            );
            assertEq(
                address(eventConfig.vaultSharesToken),
                address(poolConfig.vaultSharesToken)
            );
            assertEq(eventConfig.linkerFactory, poolConfig.linkerFactory);
            assertEq(eventConfig.linkerCodeHash, poolConfig.linkerCodeHash);
            assertEq(
                eventConfig.minimumShareReserves,
                poolConfig.minimumShareReserves
            );
            assertEq(
                eventConfig.minimumTransactionAmount,
                poolConfig.minimumTransactionAmount
            );
            assertEq(eventConfig.positionDuration, poolConfig.positionDuration);
            assertEq(
                eventConfig.checkpointDuration,
                poolConfig.checkpointDuration
            );
            assertEq(eventConfig.timeStretch, poolConfig.timeStretch);
            assertEq(eventConfig.governance, poolConfig.governance);
            assertEq(eventConfig.feeCollector, poolConfig.feeCollector);
            assertEq(eventConfig.fees.curve, poolConfig.fees.curve);
            assertEq(eventConfig.fees.flat, poolConfig.fees.flat);
            assertEq(
                eventConfig.fees.governanceLP,
                poolConfig.fees.governanceLP
            );
            assertEq(
                eventConfig.fees.governanceZombie,
                poolConfig.fees.governanceZombie
            );

            assertEq(
                keccak256(abi.encode(eventExtraData)),
                keccak256(abi.encode(expectedExtraData))
            );
        }

        // Verify that the second log is the expected `Initialize` event.
        {
            VmSafe.Log[] memory filteredLogs = Lib.filterLogs(
                logs,
                Initialize.selector
            );
            assertEq(filteredLogs.length, 1);

            // Verify the event topics.
            assertEq(filteredLogs[0].topics[0], Initialize.selector);
            assertEq(
                address(uint160(uint256(filteredLogs[0].topics[1]))),
                deployer
            );

            // Verify the event data.
            IHyperdrive hyperdrive_ = _hyperdrive;
            (
                uint256 eventLpAmount,
                uint256 eventAmount,
                uint256 eventVaultSharePrice,
                bool eventAsBase,
                uint256 eventApr
            ) = abi.decode(
                    filteredLogs[0].data,
                    (uint256, uint256, uint256, bool, uint256)
                );
            uint256 contribution_ = contribution;
            if (asBase) {
                assertApproxEqAbs(
                    eventLpAmount,
                    contribution_.divDown(
                        hyperdrive_.getPoolConfig().initialVaultSharePrice
                    ) - 2 * minimumShareReserves,
                    tolerance
                );
            } else {
                assertApproxEqAbs(
                    eventLpAmount,
                    contribution_ - 2 * minimumShareReserves,
                    tolerance
                );
            }
            assertEq(eventAmount, contribution_);
            assertApproxEqAbs(
                eventVaultSharePrice,
                hyperdrive_.getPoolConfig().initialVaultSharePrice,
                1e5
            );
            assertEq(eventAsBase, asBase);
            assertEq(eventApr, apr);
        }
    }
}
