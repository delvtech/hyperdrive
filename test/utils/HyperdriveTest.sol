// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { VmSafe } from "forge-std/Vm.sol";
import { HyperdriveBase } from "contracts/src/HyperdriveBase.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockHyperdrive, MockHyperdriveDataProvider } from "../mocks/MockHyperdrive.sol";
import { BaseTest } from "test/utils/BaseTest.sol";
import { ETH } from "test/utils/Constants.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract HyperdriveTest is BaseTest {
    using FixedPointMath for uint256;
    using Lib for *;

    ERC20Mintable baseToken;
    IHyperdrive hyperdrive;

    uint256 internal constant INITIAL_SHARE_PRICE = FixedPointMath.ONE_18;
    uint256 internal constant MINIMUM_SHARE_RESERVES = FixedPointMath.ONE_18;
    uint256 internal constant CHECKPOINT_DURATION = 1 days;
    uint256 internal constant POSITION_DURATION = 365 days;
    uint256 internal constant ORACLE_SIZE = 5;
    uint256 internal constant UPDATE_GAP = 1000;

    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(alice);

        // Instantiate the base token.
        baseToken = new ERC20Mintable();
        IHyperdrive.Fees memory fees = IHyperdrive.Fees({
            curve: 0,
            flat: 0,
            governance: 0
        });
        // Instantiate Hyperdrive.
        uint256 apr = 0.05e18;
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: IERC20(address(baseToken)),
            initialSharePrice: INITIAL_SHARE_PRICE,
            minimumShareReserves: MINIMUM_SHARE_RESERVES,
            positionDuration: POSITION_DURATION,
            checkpointDuration: CHECKPOINT_DURATION,
            timeStretch: HyperdriveUtils.calculateTimeStretch(apr),
            governance: governance,
            feeCollector: feeCollector,
            fees: fees,
            oracleSize: ORACLE_SIZE,
            updateGap: UPDATE_GAP
        });
        address dataProvider = address(new MockHyperdriveDataProvider(config));
        hyperdrive = IHyperdrive(
            address(new MockHyperdrive(config, dataProvider))
        );
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
        vm.stopPrank();
        vm.startPrank(deployer);
        address dataProvider = address(new MockHyperdriveDataProvider(_config));
        hyperdrive = IHyperdrive(
            address(new MockHyperdrive(_config, dataProvider))
        );
    }

    function deploy(
        address deployer,
        uint256 apr,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceFee
    ) internal {
        deploy(
            deployer,
            apr,
            INITIAL_SHARE_PRICE,
            curveFee,
            flatFee,
            governanceFee
        );
    }

    function deploy(
        address deployer,
        uint256 apr,
        uint256 initialSharePrice,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceFee
    ) internal {
        IHyperdrive.Fees memory fees = IHyperdrive.Fees({
            curve: curveFee,
            flat: flatFee,
            governance: governanceFee
        });
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: IERC20(address(baseToken)),
            initialSharePrice: initialSharePrice,
            minimumShareReserves: MINIMUM_SHARE_RESERVES,
            positionDuration: POSITION_DURATION,
            checkpointDuration: CHECKPOINT_DURATION,
            timeStretch: HyperdriveUtils.calculateTimeStretch(apr),
            governance: governance,
            feeCollector: feeCollector,
            fees: fees,
            oracleSize: ORACLE_SIZE,
            updateGap: UPDATE_GAP
        });
        deploy(deployer, config);
    }

    function testConfig(
        uint256 fixedRate
    ) internal view returns (IHyperdrive.PoolConfig memory) {
        IHyperdrive.Fees memory fees = IHyperdrive.Fees({
            curve: 0,
            flat: 0,
            governance: 0
        });
        return
            IHyperdrive.PoolConfig({
                baseToken: IERC20(address(baseToken)),
                initialSharePrice: FixedPointMath.ONE_18,
                minimumShareReserves: MINIMUM_SHARE_RESERVES,
                positionDuration: POSITION_DURATION,
                checkpointDuration: CHECKPOINT_DURATION,
                timeStretch: HyperdriveUtils.calculateTimeStretch(fixedRate),
                governance: governance,
                feeCollector: feeCollector,
                fees: fees,
                oracleSize: ORACLE_SIZE,
                updateGap: UPDATE_GAP
            });
    }

    /// Actions ///

    // Overrides for functions that use deposits.
    struct DepositOverrides {
        // A boolean flag specifying whether or not the underlying should be used.
        bool asUnderlying;
        // The amount of tokens the action should prepare to deposit. Note that
        // the actual deposit amount will still be specified by the action being
        // called; however, this is the amount that will be minted as a
        // convenience. In the case of ETH, this is the amount that will be
        // transferred into the YieldSource, which allows us to test ETH
        // reentrancy.
        uint256 depositAmount;
    }

    function initialize(
        address lp,
        uint256 apr,
        uint256 contribution,
        DepositOverrides memory overrides
    ) internal returns (uint256 lpShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        if (
            address(hyperdrive.getPoolConfig().baseToken) == address(ETH) &&
            overrides.asUnderlying
        ) {
            return
                hyperdrive.initialize{ value: overrides.depositAmount }(
                    contribution,
                    apr,
                    lp,
                    overrides.asUnderlying
                );
        } else {
            baseToken.mint(contribution);
            baseToken.approve(address(hyperdrive), contribution);
            return
                hyperdrive.initialize(
                    contribution,
                    apr,
                    lp,
                    overrides.asUnderlying
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
                    asUnderlying: true,
                    depositAmount: contribution
                })
            );
    }

    // FIXME: Implement the ETH flows in this wrapper. Also use the return
    // value instead of calculating the return in our tests.
    function addLiquidity(
        address lp,
        uint256 contribution
    ) internal returns (uint256 lpShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Add liquidity to the pool.
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        hyperdrive.addLiquidity(contribution, 0, type(uint256).max, lp, true);

        return hyperdrive.balanceOf(AssetId._LP_ASSET_ID, lp);
    }

    function removeLiquidity(
        address lp,
        uint256 shares
    ) internal returns (uint256 baseProceeds, uint256 withdrawalShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Remove liquidity from the pool.
        uint256 baseBalanceBefore = baseToken.balanceOf(lp);
        uint256 withdrawalShareBalanceBefore = hyperdrive.balanceOf(
            AssetId._WITHDRAWAL_SHARE_ASSET_ID,
            lp
        );
        hyperdrive.removeLiquidity(shares, 0, lp, true);

        return (
            baseToken.balanceOf(lp) - baseBalanceBefore,
            hyperdrive.balanceOf(AssetId._WITHDRAWAL_SHARE_ASSET_ID, lp) -
                withdrawalShareBalanceBefore
        );
    }

    function redeemWithdrawalShares(
        address lp,
        uint256 shares
    ) internal returns (uint256 baseProceeds, uint256 sharesRedeemed) {
        return redeemWithdrawalShares(lp, shares, 0);
    }

    function redeemWithdrawalShares(
        address lp,
        uint256 shares,
        uint256 minOutputPerShare
    ) internal returns (uint256 baseProceeds, uint256 sharesRedeemed) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Redeem the withdrawal shares.
        return
            hyperdrive.redeemWithdrawalShares(
                shares,
                minOutputPerShare,
                lp,
                true
            );
    }

    function openLong(
        address trader,
        uint256 baseAmount,
        bool asUnderlying
    ) internal returns (uint256 maturityTime, uint256 bondProceeds) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the long.
        if (
            address(hyperdrive.getPoolConfig().baseToken) == address(ETH) &&
            asUnderlying
        ) {
            return
                hyperdrive.openLong{ value: baseAmount }(
                    baseAmount,
                    0,
                    trader,
                    asUnderlying
                );
        } else {
            baseToken.mint(baseAmount);
            baseToken.approve(address(hyperdrive), baseAmount);
            return hyperdrive.openLong(baseAmount, 0, trader, asUnderlying);
        }
    }

    function openLong(
        address trader,
        uint256 baseAmount
    ) internal returns (uint256 maturityTime, uint256 bondAmount) {
        return openLong(trader, baseAmount, true);
    }

    function closeLong(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount,
        bool asUnderlying
    ) internal returns (uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Close the long.
        return
            hyperdrive.closeLong(
                maturityTime,
                bondAmount,
                0,
                trader,
                asUnderlying
            );
    }

    function closeLong(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount
    ) internal returns (uint256 baseAmount) {
        return closeLong(trader, maturityTime, bondAmount, true);
    }

    function openShort(
        address trader,
        uint256 bondAmount,
        bool asUnderlying
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);
        // Open the short
        maturityTime = HyperdriveUtils.maturityTimeFromLatestCheckpoint(
            hyperdrive
        );
        if (
            address(hyperdrive.getPoolConfig().baseToken) == address(ETH) &&
            asUnderlying
        ) {
            (maturityTime, baseAmount) = hyperdrive.openShort{
                value: bondAmount
            }(bondAmount, type(uint256).max, trader, asUnderlying);
        } else {
            baseToken.mint(bondAmount);
            baseToken.approve(address(hyperdrive), bondAmount);
            (maturityTime, baseAmount) = hyperdrive.openShort(
                bondAmount,
                type(uint256).max,
                trader,
                asUnderlying
            );
            baseToken.burn(bondAmount - baseAmount);
        }
        return (maturityTime, baseAmount);
    }

    function openShort(
        address trader,
        uint256 bondAmount
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        return openShort(trader, bondAmount, true);
    }

    function closeShort(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount,
        bool asUnderlying
    ) internal returns (uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Close the short.
        return
            hyperdrive.closeShort(
                maturityTime,
                bondAmount,
                0,
                trader,
                asUnderlying
            );
    }

    function closeShort(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount
    ) internal returns (uint256 baseAmount) {
        return closeShort(trader, maturityTime, bondAmount, true);
    }

    function estimateLongProceeds(
        uint256 bondAmount,
        uint256 normalizedTimeRemaining,
        uint256 openSharePrice,
        uint256 closeSharePrice
    ) internal view returns (uint256) {
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory poolConfig = hyperdrive.getPoolConfig();
        (, , uint256 shareProceeds) = HyperdriveMath.calculateCloseLong(
            poolInfo.shareReserves,
            poolInfo.bondReserves,
            bondAmount,
            normalizedTimeRemaining,
            poolConfig.timeStretch,
            openSharePrice,
            closeSharePrice,
            poolInfo.sharePrice,
            poolConfig.initialSharePrice
        );
        return shareProceeds.mulDivDown(poolInfo.sharePrice, 1e18);
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
            poolInfo.shareReserves,
            poolInfo.bondReserves,
            shortAmount,
            normalizedTimeRemaining,
            poolConfig.timeStretch,
            poolInfo.sharePrice,
            poolConfig.initialSharePrice
        );
        (, int256 expectedInterest) = HyperdriveUtils.calculateCompoundInterest(
            shortAmount,
            variableRate,
            timeElapsed
        );
        int256 delta = int256(
            shortAmount - poolInfo.sharePrice.mulDown(expectedSharePayment)
        );
        if (delta + expectedInterest > 0) {
            return uint256(delta + expectedInterest);
        } else {
            return 0;
        }
    }

    /// Utils ///

    function advanceTime(uint256 time, int256 apr) internal virtual {
        MockHyperdrive(address(hyperdrive)).accrue(time, apr);
        vm.warp(block.timestamp + time);
    }

    function pause(bool paused) internal {
        vm.startPrank(pauser);
        hyperdrive.pause(paused);
        vm.stopPrank();
    }

    /// Event Utils ///

    event Deployed(
        uint256 indexed version,
        address hyperdrive,
        IHyperdrive.PoolConfig config,
        address linkerFactory,
        bytes32 linkerCodeHash,
        bytes32[] extraData
    );

    event Initialize(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 apr
    );

    event AddLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount
    );

    event RemoveLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 withdrawalShareAmount
    );

    event RedeemWithdrawalShares(
        address indexed provider,
        uint256 withdrawalShareAmount,
        uint256 baseAmount
    );

    event OpenLong(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    event OpenShort(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    event CloseLong(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    event CloseShort(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    function verifyFactoryEvents(
        HyperdriveFactory factory,
        address deployer,
        uint256 contribution,
        uint256 apr,
        uint256 minimumShareReserves,
        bytes32[] memory expectedExtraData,
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
            VmSafe.Log memory log = filteredLogs[0];

            // Verify the event topics.
            assertEq(log.topics[0], Deployed.selector);
            assertEq(uint256(log.topics[1]), factory.versionCounter());

            // Verify the event data.
            (
                address eventHyperdrive,
                IHyperdrive.PoolConfig memory eventConfig,
                address eventLinkerFactory,
                bytes32 eventLinkerCodeHash,
                bytes32[] memory eventExtraData
            ) = abi.decode(
                    log.data,
                    (
                        address,
                        IHyperdrive.PoolConfig,
                        address,
                        bytes32,
                        bytes32[]
                    )
                );
            assertEq(eventHyperdrive, address(hyperdrive));
            assertEq(
                keccak256(abi.encode(eventConfig)),
                keccak256(abi.encode(hyperdrive.getPoolConfig()))
            );
            assertEq(eventLinkerFactory, address(forwarderFactory));
            assertEq(eventLinkerCodeHash, forwarderFactory.ERC20LINK_HASH());
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
            VmSafe.Log memory log = filteredLogs[0];

            // Verify the event topics.
            assertEq(log.topics[0], Initialize.selector);
            assertEq(address(uint160(uint256(log.topics[1]))), deployer);

            // Verify the event data.
            (
                uint256 eventLpAmount,
                uint256 eventBaseAmount,
                uint256 eventApr
            ) = abi.decode(log.data, (uint256, uint256, uint256));
            assertApproxEqAbs(
                eventLpAmount,
                contribution.divDown(
                    hyperdrive.getPoolConfig().initialSharePrice
                ) - 2 * minimumShareReserves,
                tolerance
            );
            assertEq(eventBaseAmount, contribution);
            assertEq(eventApr, apr);
        }
    }
}
